// Multithreaded search over the 80-byte header-v2 work input. See engine.h.

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#if defined(__APPLE__)
#include <pthread/qos.h>
#endif

#include "blake2b_x3.h"
#include "engine.h"

#define MAX_THREADS 256
#define MAX_SOLUTIONS 64
#define BATCH 21846  // x3 calls between checks for new work (~65k hashes)
#define NONCE2_LANE_BITS 24  // nonce2 = thread << 24 | sweep counter

static inline uint64_t load64le(const uint8_t *p)
{
    uint64_t v;
    memcpy(&v, p, 8);
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    v = __builtin_bswap64(v);
#endif
    return v;
}

// Full BLAKE2b-256 of the 80-byte input in m[0..9] (words 10..15 are zero).
static void blake2b80_full(const uint64_t m[10], uint64_t out[4])
{
    uint8_t in[80], digest[32];
    for (int i = 0; i < 10; ++i)
        for (int b = 0; b < 8; ++b) in[8 * i + b] = (uint8_t)(m[i] >> (8 * b));
    b2m_blake2b256(digest, in, sizeof in);
    for (int i = 0; i < 4; ++i) out[i] = load64le(digest + 8 * i);
}

// The block hash as a 256-bit number is the BLAKE2b output bytes read
// big-endian: byte-swapped output words, most significant first.
static int meets_target(const uint64_t out[4], const uint64_t target[4])
{
    for (int i = 0; i < 4; ++i) {
        uint64_t w = __builtin_bswap64(out[i]);
        if (w != target[i]) return w < target[i];
    }
    return 1;
}

struct work {
    uint64_t job_id;
    uint64_t m[10];       // input words; m[4] is replaced by the search
    uint64_t target[4];   // most significant word first
    bool valid;
};

struct solution {
    uint64_t job_id;
    uint64_t nonce64;
};

static struct {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    struct work work;
    atomic_uint_fast64_t generation;
    atomic_bool stopping;
    int nthreads;
    int low_priority;
    pthread_t threads[MAX_THREADS];
    struct { _Alignas(128) atomic_uint_fast64_t hashes; } counters[MAX_THREADS];
    struct solution solutions[MAX_SOLUTIONS];
    int nsolutions;
} E = { .lock = PTHREAD_MUTEX_INITIALIZER, .cond = PTHREAD_COND_INITIALIZER };

static void check_candidate(const struct work *w, uint64_t nonce64)
{
    uint64_t m[10], out[4];
    memcpy(m, w->m, sizeof m);
    m[4] = nonce64;
    blake2b80_full(m, out);
    if (!meets_target(out, w->target)) return;
    pthread_mutex_lock(&E.lock);
    if (E.nsolutions < MAX_SOLUTIONS) {
        E.solutions[E.nsolutions++] = (struct solution){w->job_id, nonce64};
    }
    pthread_mutex_unlock(&E.lock);
}

static void *worker(void *arg)
{
    const uint32_t tid = (uint32_t)(intptr_t)arg;
#if defined(__APPLE__)
    pthread_set_qos_class_self_np(E.low_priority ? QOS_CLASS_UTILITY : QOS_CLASS_USER_INITIATED, 0);
#endif
    uint64_t seen = 0;
    struct work w = {0};
    uint64_t pre[16];
    uint32_t sweep = 0;
    while (!atomic_load(&E.stopping)) {
        if (atomic_load(&E.generation) != seen) {
            pthread_mutex_lock(&E.lock);
            w = E.work;
            seen = atomic_load(&E.generation);
            pthread_mutex_unlock(&E.lock);
            sweep = 0;
            if (w.valid) blake2b80_precompute(w.m, pre);
        }
        if (!w.valid) {
            pthread_mutex_lock(&E.lock);
            while (atomic_load(&E.generation) == seen && !atomic_load(&E.stopping))
                pthread_cond_wait(&E.cond, &E.lock);
            pthread_mutex_unlock(&E.lock);
            continue;
        }
        const uint32_t nonce2 = (tid << NONCE2_LANE_BITS) | (sweep & ((1u << NONCE2_LANE_BITS) - 1));
        const uint64_t hi = (uint64_t)nonce2 << 32;
        uint64_t n = 0;
        // Sweep the 2^32 nNonce values for this nonce2 three at a time. The last
        // batch may wrap and repeat a few nonces, which is harmless.
        do {
            for (uint32_t i = 0; i < BATCH; ++i, n += 3) {
                const uint64_t a = hi | (uint32_t)n, b = hi | (uint32_t)(n + 1), c = hi | (uint32_t)(n + 2);
                uint64_t word0[3];
                blake2b80_x3_word0(w.m, pre, a, b, c, word0);
                if (__builtin_expect(__builtin_bswap64(word0[0]) <= w.target[0], 0)) check_candidate(&w, a);
                if (__builtin_expect(__builtin_bswap64(word0[1]) <= w.target[0], 0)) check_candidate(&w, b);
                if (__builtin_expect(__builtin_bswap64(word0[2]) <= w.target[0], 0)) check_candidate(&w, c);
            }
            atomic_fetch_add_explicit(&E.counters[tid].hashes, 3ULL * BATCH, memory_order_relaxed);
        } while (n < (1ULL << 32) && atomic_load_explicit(&E.generation, memory_order_relaxed) == seen
                 && !atomic_load_explicit(&E.stopping, memory_order_relaxed));
        if (n >= (1ULL << 32)) ++sweep;
    }
    return NULL;
}

int b2m_start(int nthreads, int low_priority)
{
    if (nthreads < 1 || nthreads > (1 << (32 - NONCE2_LANE_BITS)) || nthreads > MAX_THREADS) return -1;
    if (E.nthreads) return -1;
    atomic_store(&E.stopping, false);
    E.low_priority = low_priority;
    for (int i = 0; i < nthreads; ++i) {
        atomic_store(&E.counters[i].hashes, 0);
        if (pthread_create(&E.threads[i], NULL, worker, (void *)(intptr_t)i) != 0) {
            b2m_stop();
            return -1;
        }
        E.nthreads = i + 1;
    }
    return 0;
}

void b2m_stop(void)
{
    pthread_mutex_lock(&E.lock);
    atomic_store(&E.stopping, true);
    pthread_cond_broadcast(&E.cond);
    pthread_mutex_unlock(&E.lock);
    for (int i = 0; i < E.nthreads; ++i) pthread_join(E.threads[i], NULL);
    E.nthreads = 0;
    pthread_mutex_lock(&E.lock);
    E.work.valid = false;
    E.nsolutions = 0;
    pthread_mutex_unlock(&E.lock);
}

static void publish(struct work w)
{
    pthread_mutex_lock(&E.lock);
    E.work = w;
    atomic_fetch_add(&E.generation, 1);
    pthread_cond_broadcast(&E.cond);
    pthread_mutex_unlock(&E.lock);
}

void b2m_set_work(uint64_t job_id, const uint8_t input80[80], const uint8_t target_be[32])
{
    struct work w = {.job_id = job_id, .valid = true};
    for (int i = 0; i < 10; ++i) w.m[i] = load64le(input80 + 8 * i);
    w.m[4] = 0;
    for (int i = 0; i < 4; ++i) {
        uint64_t v = 0;
        for (int b = 0; b < 8; ++b) v = (v << 8) | target_be[8 * i + b];
        w.target[i] = v;
    }
    publish(w);
}

void b2m_clear_work(void)
{
    publish((struct work){.valid = false});
}

int b2m_take_solution(uint64_t *job_id, uint8_t nonce8[8])
{
    int found = 0;
    pthread_mutex_lock(&E.lock);
    if (E.nsolutions) {
        struct solution s = E.solutions[--E.nsolutions];
        *job_id = s.job_id;
        for (int b = 0; b < 8; ++b) nonce8[b] = (uint8_t)(s.nonce64 >> (8 * b));
        found = 1;
    }
    pthread_mutex_unlock(&E.lock);
    return found;
}

uint64_t b2m_hashes(void)
{
    uint64_t total = 0;
    for (int i = 0; i < E.nthreads; ++i) total += atomic_load_explicit(&E.counters[i].hashes, memory_order_relaxed);
    return total;
}

int b2m_threads(void) { return E.nthreads; }

void b2m_hash80(const uint8_t input80[80], uint8_t out[32])
{
    // Goes through the precompute + 3-lane path so self-tests exercise the hot code.
    uint64_t m[10], pre[16], word0[3];
    for (int i = 0; i < 10; ++i) m[i] = load64le(input80 + 8 * i);
    blake2b80_precompute(m, pre);
    blake2b80_x3_word0(m, pre, m[4], m[4], m[4], word0);
    b2m_blake2b256(out, input80, 80);
    // Word 0 from the fast path must agree with the reference; corrupt the
    // output otherwise so the self-test fails loudly.
    if (load64le(out) != word0[0] || word0[0] != word0[1] || word0[1] != word0[2]) out[0] ^= 0xff;
}
