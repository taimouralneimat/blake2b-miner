import CEngine
import Foundation
import Metal

/// The Mac's GPU, for settings and messages.
public enum GPUInfo {
    /// The GPU's name, e.g. "Apple M4 Pro"; nil if there is no Metal GPU.
    public static let name: String? = MTLCreateSystemDefaultDevice()?.name
}

/// Mines on the GPU with Metal, next to the CPU engine (see `Engine`).
///
/// A feeder thread sends the GPU batches of nonces, two at a time so it never
/// idles. The batch size is calibrated once so a batch takes about `burst` seconds:
/// short bursts (responsive mode) leave gaps for the window server to draw, longer
/// ones keep overhead low. Below 100% load the GPU works at full speed for that
/// share of each quarter second and rests for the rest. The GPU only does the quick
/// check on the hash's first word; every hit is re-checked on the CPU with the full
/// hash before it is reported.
///
/// The GPU searches nonces with the top bit of nonce2 set (bit 63 of the nonce
/// word); CPU threads never do, so the two never repeat each other's work.
final class GPUEngine: @unchecked Sendable {  // mutable state is guarded by `cond`
    let deviceName: String

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    /// Bound by every batch: because each batch may write it, Metal runs batches
    /// one after another instead of overlapping them, which is ~12% faster.
    private let serial: MTLBuffer
    /// Result buffers for the batches: one more than can be queued.
    private let slots: [Slot]
    private let load: Int
    private let burst: TimeInterval
    private let cond = NSCondition()

    private struct Work {
        let jobID: UInt64
        let input: [UInt8]
        let target: [UInt8]  // big-endian
        let params: [UInt64]
        var nextNonce: UInt64
    }
    private var work: Work?
    private var stopping = false
    private var solutions: [(UInt64, Data)] = []
    private var hashCount: UInt64 = 0
    private var lastProblem: String?
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)

    /// First nonce of every job: nonce2's top bit set.
    static let firstNonce: UInt64 = 1 << 63
    /// GPU time per batch: short in responsive mode so the screen stays smooth.
    static let responsiveBurst: TimeInterval = 0.004
    static let normalBurst: TimeInterval = 0.025
    /// Work-and-rest cycle for loads below 100%.
    private static let loadPeriod: TimeInterval = 0.25
    /// Batches queued on the GPU at once, so it never idles between them.
    private static let depth = 2
    private static let minThreads = 16_384
    private static let maxThreads = 1 << 22
    /// Like the CPU engine, keep at most this many solutions waiting.
    private static let maxSolutions = 64

    /// - Parameters:
    ///   - load: percent of the GPU's time to use, 10...100.
    ///   - responsive: short batches so the Mac stays smooth.
    init(load: Int, responsive: Bool) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MinerError.config("This Mac has no Metal GPU")
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: GPUKernel.source, options: Self.compileOptions)
        } catch {
            throw MinerError.config("The GPU kernel didn't compile: \(error.localizedDescription)")
        }
        guard let function = library.makeFunction(name: "blake2b80"),
              let queue = device.makeCommandQueue() else {
            throw MinerError.config("Could not set up the GPU kernel")
        }
        guard let serial = device.makeBuffer(length: 8, options: .storageModeShared) else {
            throw MinerError.config("Could not set up the GPU kernel")
        }
        let slots = (0...Self.depth).compactMap { _ in Self.makeSlot(device: device, words: serial) }
        guard slots.count == Self.depth + 1 else { throw MinerError.config("Not enough GPU memory") }
        self.slots = slots
        self.device = device
        self.queue = queue
        self.serial = serial
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw MinerError.config("Could not set up the GPU kernel: \(error.localizedDescription)")
        }
        deviceName = device.name
        self.load = min(max(load, 10), 100)
        burst = responsive ? Self.responsiveBurst : Self.normalBurst
    }

    /// Fast math: the kernel is integer-only, but the strict default compiles slower code.
    private static var compileOptions: MTLCompileOptions {
        let options = MTLCompileOptions()
        if #available(macOS 15.0, *) {
            options.mathMode = .fast
        } else {
            options.fastMathEnabled = true
        }
        return options
    }

    // MARK: Control (any thread)

    func start() {
        cond.lock()
        defer { cond.unlock() }
        guard thread == nil else { return }
        stopping = false
        let t = Thread { [weak self] in self?.feed() }
        t.name = "gpu-feeder"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        cond.lock()
        guard thread != nil else { cond.unlock(); return }
        stopping = true
        cond.broadcast()
        cond.unlock()
        finished.wait()
        cond.lock()
        thread = nil
        work = nil
        solutions.removeAll()
        cond.unlock()
    }

    func setWork(jobID: UInt64, input: Data, target: UInt256) {
        let bytes = [UInt8](input)
        var m = [UInt64](repeating: 0, count: 10), pre = [UInt64](repeating: 0, count: 16)
        b2m_precompute(bytes, &m, &pre)
        let targetBytes = [UInt8](target.bigEndianData)
        let target0 = targetBytes[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        // Laid out like the kernel's Params: m[10], pre[16], base, target0, debug (+ padding).
        let params = m + pre + [0, target0, 0]
        cond.lock()
        work = Work(jobID: jobID, input: bytes, target: targetBytes, params: params, nextNonce: Self.firstNonce)
        cond.broadcast()
        cond.unlock()
    }

    func clearWork() {
        cond.lock()
        work = nil
        cond.unlock()
    }

    func takeSolution() -> (UInt64, Data)? {
        cond.lock()
        defer { cond.unlock() }
        return solutions.isEmpty ? nil : solutions.removeFirst()
    }

    var hashes: UInt64 {
        cond.lock()
        defer { cond.unlock() }
        return hashCount
    }

    /// Why the last batch failed (e.g. a Metal error), until one succeeds.
    var problem: String? {
        cond.lock()
        defer { cond.unlock() }
        return lastProblem
    }

    // MARK: Feeder thread

    /// GPU buffers for one batch's results, reused across batches. `words` (written
    /// only in debug mode) is the shared `serial` buffer.
    private struct Slot {
        let hitCount: MTLBuffer
        let hits: MTLBuffer
        let words: MTLBuffer
    }

    private static func makeSlot(device: MTLDevice, words: MTLBuffer) -> Slot? {
        guard let hitCount = device.makeBuffer(length: 4, options: .storageModeShared),
              let hits = device.makeBuffer(length: 8 * GPUKernel.maxHits, options: .storageModeShared) else { return nil }
        return Slot(hitCount: hitCount, hits: hits, words: words)
    }

    private struct Batch {
        let buffer: MTLCommandBuffer
        let committed: Date
        let slot: Slot
        let jobID: UInt64
        let input: [UInt8]
        let target: [UInt8]
        let nonces: UInt64
    }

    private func feed() {
        defer { finished.signal() }
        var threads = Self.minThreads
        // Calibrated on the first batches, run one at a time so their GPU times don't
        // overlap; then fixed.
        var calibrated = false
        var inFlight: [Batch] = []
        var free = slots
        var busy: TimeInterval = 0  // GPU time in the current work phase (load < 100%)
        loop: while true {
            switch nextStep(threads: threads, queued: !inFlight.isEmpty) {
            case .stop:
                break loop
            case .finishQueued:
                break
            case let .hash(w, base):
                // There are depth + 1 slots and at most depth batches queued.
                guard let slot = free.popLast() else { continue }
                guard let batch = encode(w, base: base, threads: threads, slot: slot) else {
                    free.append(slot)
                    rest(1)  // out of GPU memory or similar: try again shortly
                    continue
                }
                inFlight.append(batch)
                guard inFlight.count >= (calibrated ? Self.depth : 1) else { continue }
            }
            let done = inFlight.removeFirst()
            free.append(done.slot)
            guard let gpuTime = finish(done) else {
                rest(1)  // the GPU reported an error: back off, then try again
                continue
            }
            if !calibrated { (threads, calibrated) = calibrate(threads: threads, gpuTime: gpuTime) }
            busy += gpuTime
            if load < 100 && calibrated && busy >= Self.loadPeriod * Double(load) / 100 {
                // Rest phase: let the queued batches finish, then pause.
                for batch in inFlight { _ = finish(batch); free.append(batch.slot) }
                inFlight.removeAll()
                rest(Self.loadPeriod * Double(100 - load) / 100)
                busy = 0
            }
        }
        for batch in inFlight { batch.buffer.waitUntilCompleted() }
    }

    private enum Step {
        case stop
        /// No work (cleared), but batches are still queued: finish them.
        case finishQueued
        /// Hash `threads` × noncesPerThread nonces of this work from `base`.
        case hash(Work, base: UInt64)
    }

    /// Waits until there is something to do; for new work, reserves the next range of nonces.
    private func nextStep(threads: Int, queued: Bool) -> Step {
        cond.lock()
        defer { cond.unlock() }
        while !stopping && work == nil && !queued { cond.wait() }
        if stopping { return .stop }
        guard var w = work else { return .finishQueued }
        let base = w.nextNonce
        w.nextNonce &+= UInt64(threads * GPUKernel.noncesPerThread)
        work = w
        return .hash(w, base: base)
    }

    /// Grows the batch until one takes about `burst`; returns the new size and
    /// whether calibration is done.
    private func calibrate(threads: Int, gpuTime: TimeInterval) -> (Int, Bool) {
        let scale = burst / gpuTime
        guard scale >= 1.25 && threads < Self.maxThreads else { return (threads, true) }
        return (min(Int(Double(threads) * min(scale, 4)) / 1024 * 1024, Self.maxThreads), false)
    }

    /// Sleeps for the load setting, waking early to stop.
    private func rest(_ seconds: TimeInterval) {
        cond.lock()
        if !stopping { _ = cond.wait(until: Date().addingTimeInterval(min(seconds, 1))) }
        cond.unlock()
    }

    private func encode(_ w: Work, base: UInt64, threads: Int, slot: Slot, debug: Bool = false) -> Batch? {
        var params = w.params
        params[26] = base
        if debug { params[28] = 1 }
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else { return nil }
        slot.hitCount.contents().storeBytes(of: UInt32(0), as: UInt32.self)
        encoder.setComputePipelineState(pipeline)
        params.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.setBuffer(slot.hitCount, offset: 0, index: 1)
        encoder.setBuffer(slot.hits, offset: 0, index: 2)
        encoder.setBuffer(slot.words, offset: 0, index: 3)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        buffer.commit()
        return Batch(buffer: buffer, committed: Date(), slot: slot, jobID: w.jobID, input: w.input,
                     target: w.target, nonces: UInt64(threads * GPUKernel.noncesPerThread))
    }

    /// Waits for a batch, checks its hits on the CPU, and returns how long it ran
    /// (nil if the GPU reported an error).
    private func finish(_ batch: Batch) -> TimeInterval? {
        batch.buffer.waitUntilCompleted()
        guard batch.buffer.status == .completed else {
            let reason = batch.buffer.error?.localizedDescription ?? "the GPU did not finish a batch"
            cond.lock()
            lastProblem = reason
            cond.unlock()
            return nil
        }
        let count = min(Int(batch.slot.hitCount.contents().load(as: UInt32.self)), GPUKernel.maxHits)
        let hits = batch.slot.hits.contents().bindMemory(to: UInt64.self, capacity: GPUKernel.maxHits)
        var found: [(UInt64, Data)] = []
        for i in 0..<count where b2m_check_nonce(batch.input, batch.target, hits[i]) == 1 {
            found.append((batch.jobID, withUnsafeBytes(of: hits[i].littleEndian) { Data($0) }))
        }
        cond.lock()
        hashCount &+= batch.nonces
        lastProblem = nil
        // Easy test networks can find many; keep the first few.
        solutions.append(contentsOf: found.prefix(max(0, Self.maxSolutions - solutions.count)))
        cond.unlock()
        // GPU timestamps, or the wall clock where the GPU doesn't report them.
        let gpuTime = batch.buffer.gpuEndTime - batch.buffer.gpuStartTime
        return gpuTime > 0 ? gpuTime : Date().timeIntervalSince(batch.committed)
    }

    // MARK: Self-test

    /// Word 0 of the hash for `threads` × noncesPerThread nonces from `base`, computed
    /// on the GPU (to compare with the CPU reference).
    func debugWords(input: Data, base: UInt64, threads: Int) -> [UInt64]? {
        let n = threads * GPUKernel.noncesPerThread
        guard let words = device.makeBuffer(length: 8 * n, options: .storageModeShared) else { return nil }
        var m = [UInt64](repeating: 0, count: 10), pre = [UInt64](repeating: 0, count: 16)
        b2m_precompute([UInt8](input), &m, &pre)
        let w = Work(jobID: 0, input: [UInt8](input), target: [UInt8](repeating: 0, count: 32),
                     params: m + pre + [0, 0, 0], nextNonce: base)
        guard let slot = Self.makeSlot(device: device, words: words),
              let batch = encode(w, base: base, threads: threads, slot: slot, debug: true) else { return nil }
        batch.buffer.waitUntilCompleted()
        guard batch.buffer.status == .completed else { return nil }
        let p = words.contents().bindMemory(to: UInt64.self, capacity: n)
        return Array(UnsafeBufferPointer(start: p, count: n))
    }
}
