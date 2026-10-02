// Native BLAKE2b search engine for Bitcoin Knots header-v2 work.
//
// Work is the 80-byte input of the last BLAKE2b stage of the header-v2 block
// hash ("profile 0", as used by Knots' own miner and by DATUM's Stratum):
//
//   bytes  0..31  prevblock_hidden (fixed per job)
//   bytes 32..39  nNonce | nonce2    <- searched by the engine
//   bytes 40..47  time_offset | nonce3 (fixed per job)
//   bytes 48..79  blake2b_1 / work root (fixed per job)
//
// Each thread searches its own nonce2 range, so threads never overlap.

#ifndef B2M_ENGINE_H
#define B2M_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Starts `nthreads` hashing threads (idle until work is set).
/// `low_priority` runs them at utility QoS so the Mac stays responsive.
int b2m_start(int nthreads, int low_priority);

/// Stops and joins all threads. Safe to call when not running.
void b2m_stop(void);

/// Sets new work. `target_be` is the 256-bit target, big-endian.
/// Threads switch to it within a few milliseconds.
void b2m_set_work(uint64_t job_id, const uint8_t input80[80], const uint8_t target_be[32]);

/// Removes the current work; threads idle until new work arrives.
void b2m_clear_work(void);

/// Pops one solution (fully verified against the target). Returns 1 if one was available.
/// `nonce8` receives bytes 32..39 of the solved input.
int b2m_take_solution(uint64_t *job_id, uint8_t nonce8[8]);

/// Total hashes computed since start.
uint64_t b2m_hashes(void);

/// Number of running threads.
int b2m_threads(void);

/// General BLAKE2b-256 (unkeyed), for reference hashing.
void b2m_blake2b256(uint8_t out[32], const uint8_t *in, size_t len);

/// Single hash of an 80-byte input through the optimized path, for self-tests.
void b2m_hash80(const uint8_t input80[80], uint8_t out[32]);

#ifdef __cplusplus
}
#endif

#endif
