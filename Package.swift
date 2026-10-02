// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BLAKE2bMiner",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BLAKE2bMiner", targets: ["BLAKE2bMinerApp"]),
        .executable(name: "b2bminer", targets: ["b2bminer"]),
    ],
    targets: [
        // Hashing engine. -O3 without -march/-mcpu: the defaults for each
        // architecture run on every Apple Silicon and every Intel Mac.
        .target(name: "CEngine", cSettings: [.unsafeFlags(["-O3"])]),
        .target(name: "MinerCore", dependencies: ["CEngine"]),
        .executableTarget(name: "b2bminer", dependencies: ["MinerCore"]),
        .executableTarget(name: "BLAKE2bMinerApp", dependencies: ["MinerCore"]),
    ]
)
