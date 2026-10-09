#!/usr/bin/env python3
"""Generates blake2b_x3_arm64.S: the Apple Silicon hashing kernel.

Same job as blake2b80_x3_word0 in blake2b_x3.h (output word 0 of three BLAKE2b
hashes of the 80-byte input, differing only in word 4), but hand-scheduled:

  - One NEON vector hashes two nonces, using the SHA3 extension's XAR
    instruction for BLAKE2b's xor-and-rotate (one instruction instead of two).
  - One integer lane hashes a third nonce at the same time, so the vector
    pipes and the integer ALUs both stay busy.
  - Every state and message word has its own register: no spills to memory.
  - Work that doesn't reach output word 0 is dropped from the last round.

On an M4 Pro this is about twice the hashrate of the C kernel; the C kernel
stays for Intel Macs and as the reference (b2m_hash80 checks both).

  void b2m_blake2b80_x3_arm64(const uint64_t m[10], const uint64_t pre[16], uint64_t base, uint64_t out[3])

hashes word 4 = base, base + 1 (vector) and base + 2 (integer lane).

Run: python3 gen_blake2b_arm64.py > ../Sources/CEngine/blake2b_x3_arm64.S
"""

SIGMA = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
]
COLUMNS = [(0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15),
           (0, 5, 10, 15), (1, 6, 11, 12), (2, 7, 8, 13), (3, 4, 9, 14)]
PRECOMPUTED = (0, 1, 3)
H0 = 0x6a09e667f3bcc908 ^ 0x01010020


def ir():
    """High-level ops: ('add', dst_state, ('v', i) | ('m', i)) and ('xr', dst, src, n) = dst = ror(dst ^ src, n).
    The 4 G calls of each half-round are interleaved step by step (they touch disjoint words)."""
    ops = []
    for r in range(12):
        s = SIGMA[r % 10]
        for half in (range(0, 4), range(4, 8)):
            gs = []
            for g in half:
                if r == 0 and g in PRECOMPUTED:
                    continue
                a, b, c, d = COLUMNS[g]
                x, y = s[2 * g], s[2 * g + 1]
                st = []
                if x < 10: st.append(("add", a, ("m", x)))
                st.append(("add", a, ("v", b)))
                st.append(("xr", d, a, 32))
                st.append(("add", c, ("v", d)))
                st.append(("xr", b, c, 24))
                if y < 10: st.append(("add", a, ("m", y)))
                st.append(("add", a, ("v", b)))
                st.append(("xr", d, a, 16))
                st.append(("add", c, ("v", d)))
                st.append(("xr", b, c, 63))
                gs.append(st)
            for k in range(max(len(x) for x in gs)):
                for st in gs:
                    if k < len(st): ops.append(st[k])
    # Dead-code elimination: only v0 and v8 feed output word 0.
    live, kept = {0, 8}, []
    for op in reversed(ops):
        dst = op[1]
        if dst not in live:
            continue
        kept.append(op)
        if op[0] == "add" and op[2][0] == "v": live.add(op[2][1])
        if op[0] == "xr": live.add(op[2])
    return kept[::-1]


# Registers. Integer lane: state v0..v15 in XS, message words m0..m9 in XM
# (m4 = that lane's nonce). x2 and x3 (the base and out arguments) hold m8 and m9
# once they are used; x18 (reserved by macOS) and x29/x30 (frame pointer and link
# register, which backtraces rely on) are never touched. NEON lanes: state in
# v16..v31, message words in v0..v9.
XS = ["x%d" % i for i in (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20)]
XM = ["x%d" % i for i in (21, 22, 23, 24, 25, 26, 27, 28, 2, 3)]
VS = ["v%d" % i for i in range(16, 32)]
VM = ["v%d" % i for i in range(0, 10)]


def scalar(op):
    if op[0] == "add":
        src = XS[op[2][1]] if op[2][0] == "v" else XM[op[2][1]]
        return ["add %s, %s, %s" % (XS[op[1]], XS[op[1]], src)]
    d, s, n = XS[op[1]], XS[op[2]], op[3]
    return ["eor %s, %s, %s" % (d, d, s), "ror %s, %s, #%d" % (d, d, n)]


def neon(op):
    if op[0] == "add":
        src = VS[op[2][1]] if op[2][0] == "v" else VM[op[2][1]]
        return ["add %s.2d, %s.2d, %s.2d" % (VS[op[1]], VS[op[1]], src)]
    d, s, n = VS[op[1]], VS[op[2]], op[3]
    return ["xar %s.2d, %s.2d, %s.2d, #%d" % (d, d, s, n)]


def merge(a, b):
    """Interleaves two instruction streams in proportion to their lengths."""
    out, i, j = [], 0, 0
    while i < len(a) or j < len(b):
        if j >= len(b) or (i < len(a) and i * len(b) <= j * len(a)):
            out.append(a[i]); i += 1
        else:
            out.append(b[j]); j += 1
    return out


def function(name):
    """void name(const uint64_t m[10] /* x0 */, const uint64_t pre[16] /* x1 */,
                 uint64_t base /* x2 */, uint64_t out[3] /* x3 */)"""
    ops = ir()
    o = [".globl _%s" % name, ".p2align 6", "_%s:" % name]
    # Save the callee-saved registers used: x19-x28 and d8-d11 (low halves of v8-v11);
    # keep `out` for the end.
    o += ["stp x19, x20, [sp, #-112]!", "stp x21, x22, [sp, #16]", "stp x23, x24, [sp, #32]",
          "stp x25, x26, [sp, #48]", "stp x27, x28, [sp, #64]", "stp d8, d9, [sp, #80]",
          "stp d10, d11, [sp, #96]"]
    o.append("str x3, [sp, #-16]!")
    # Integer lane: state, message words m0..m7, and its nonce word (base + 2).
    o += ["ldp %s, %s, [x1, #%d]" % (XS[i], XS[i + 1], 8 * i) for i in range(0, 16, 2)]
    o += ["ldp %s, %s, [x0, #%d]" % (XM[i], XM[i + 1], 8 * i) for i in range(0, 8, 2)]
    o.append("add %s, x2, #2" % XM[4])
    # NEON lanes: state and message words, then the nonce words base and base + 1.
    o += ["ld1r {%s.2d}, [x1], #8" % VS[i] for i in range(16)]
    o += ["ld1r {%s.2d}, [x0], #8" % VM[i] for i in range(10)]
    o += ["fmov d4, x2", "add x2, x2, #1", "mov v4.d[1], x2"]
    # Now x2 and x3 are free: m8 and m9 (x0 has moved past m[9]).
    o.append("ldp %s, %s, [x0, #-16]" % (XM[8], XM[9]))
    o += merge([i for op in ops for i in neon(op)], [i for op in ops for i in scalar(op)])
    # out[0..1] = NEON lanes, out[2] = integer lane: H0 ^ v0 ^ v8.
    o += ["mov x0, #0x%x" % (H0 & 0xffff)] + ["movk x0, #0x%x, lsl #%d" % ((H0 >> s) & 0xffff, s) for s in (16, 32, 48)]
    o.append("ldr x3, [sp], #16")
    o += ["dup v10.2d, x0", "eor %s.16b, %s.16b, %s.16b" % (VS[0], VS[0], VS[8]),
          "eor %s.16b, %s.16b, v10.16b" % (VS[0], VS[0]), "st1 {%s.2d}, [x3], #16" % VS[0]]
    o += ["eor %s, %s, %s" % (XS[0], XS[0], XS[8]), "eor %s, %s, x0" % (XS[0], XS[0]), "str %s, [x3]" % XS[0]]
    o += ["ldp d10, d11, [sp, #96]", "ldp d8, d9, [sp, #80]", "ldp x27, x28, [sp, #64]",
          "ldp x25, x26, [sp, #48]", "ldp x23, x24, [sp, #32]", "ldp x21, x22, [sp, #16]",
          "ldp x19, x20, [sp], #112", "ret"]
    return "\n".join(("" if l.endswith(":") or l.startswith(".") else "    ") + l for l in o)


def main():
    print("// Generated by scripts/gen_blake2b_arm64.py; do not edit.")
    print("#if defined(__aarch64__)")
    print(".text")
    print(".arch armv8.2-a+sha3")
    print(".private_extern _b2m_blake2b80_x3_arm64")
    print(function("b2m_blake2b80_x3_arm64"))
    print("#endif")


if __name__ == "__main__":
    main()
