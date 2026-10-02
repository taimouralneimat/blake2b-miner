// Portable BLAKE2b-256 (RFC 7693), unkeyed. Used for reference hashing and
// for computing per-job values; the hot path lives in engine.c.

#include <string.h>

#include "engine.h"

static const uint64_t IV[8] = {
    0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL, 0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL,
};

static const uint8_t SIGMA[12][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
    {11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
    {7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
    {9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
    {2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
    {12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
    {13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
    {6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
    {10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
};

static uint64_t rotr(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }

static uint64_t load64(const uint8_t *p)
{
    uint64_t v = 0;
    for (int i = 7; i >= 0; --i) v = (v << 8) | p[i];
    return v;
}

static void compress(uint64_t h[8], const uint8_t block[128], uint64_t t, int last)
{
    uint64_t m[16], v[16];
    for (int i = 0; i < 16; ++i) m[i] = load64(block + 8 * i);
    for (int i = 0; i < 8; ++i) { v[i] = h[i]; v[i + 8] = IV[i]; }
    v[12] ^= t;
    if (last) v[14] = ~v[14];
    for (int r = 0; r < 12; ++r) {
        const uint8_t *s = SIGMA[r];
#define G(a, b, c, d, x, y)                         \
        v[a] += v[b] + (x); v[d] = rotr(v[d] ^ v[a], 32); \
        v[c] += v[d];       v[b] = rotr(v[b] ^ v[c], 24); \
        v[a] += v[b] + (y); v[d] = rotr(v[d] ^ v[a], 16); \
        v[c] += v[d];       v[b] = rotr(v[b] ^ v[c], 63);
        G(0, 4, 8, 12, m[s[0]], m[s[1]]);
        G(1, 5, 9, 13, m[s[2]], m[s[3]]);
        G(2, 6, 10, 14, m[s[4]], m[s[5]]);
        G(3, 7, 11, 15, m[s[6]], m[s[7]]);
        G(0, 5, 10, 15, m[s[8]], m[s[9]]);
        G(1, 6, 11, 12, m[s[10]], m[s[11]]);
        G(2, 7, 8, 13, m[s[12]], m[s[13]]);
        G(3, 4, 9, 14, m[s[14]], m[s[15]]);
#undef G
    }
    for (int i = 0; i < 8; ++i) h[i] ^= v[i] ^ v[i + 8];
}

void b2m_blake2b256(uint8_t out[32], const uint8_t *in, size_t len)
{
    uint64_t h[8];
    memcpy(h, IV, sizeof h);
    h[0] ^= 0x01010020ULL;  // digest length 32, no key, fanout 1, depth 1
    uint8_t block[128];
    uint64_t t = 0;
    while (len > 128) {
        t += 128;
        compress(h, in, t, 0);
        in += 128;
        len -= 128;
    }
    memset(block, 0, sizeof block);
    if (len) memcpy(block, in, len);
    t += len;
    compress(h, block, t, 1);
    for (int i = 0; i < 32; ++i) out[i] = (uint8_t)(h[i / 8] >> (8 * (i % 8)));
}
