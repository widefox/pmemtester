# FAQ

## How fast is pmemtester compared to stressapptest?

pmemtester parallelises memtester across all CPU threads, reducing wall-clock time proportionally up to memory bandwidth saturation. On a 16-thread system testing 64 GB, pmemtester completes in ~20 minutes (1 loop) versus ~5 hours for a single memtester instance. stressapptest runs for a user-specified duration (typically 60s-2hrs) and reports ~10,000-14,000 MB/s aggregate throughput on a 16-core x86 server. No published head-to-head benchmark exists on identical hardware, and memtester does not report throughput metrics, so direct comparison requires manual timing. Memory bandwidth saturates at 3-5 cores on a typical dual-channel system; adding threads beyond that point causes contention and can regress throughput.

| Tool | Configuration | ~Time for 64 GB |
|------|--------------|-----------------|
| memtester | 1 instance, 64 GB | ~5 hours (1 loop) |
| pmemtester | 16 instances, 4 GB each | ~20 minutes (1 loop) |
| stressapptest | Default (auto-threads) | User-specified duration (typically 60s-2hrs) |

References: [memtester 64 GB timing estimate (GitHub issue #2)](https://github.com/jnavila/memtester/issues/2), [stressapptest x86 benchmark output (benjr.tw)](https://benjr.tw/96776), [Tom's Hardware: multi-thread memory bandwidth scaling](https://forums.tomshardware.com/threads/whats-the-point-of-running-memtest86-with-multiple-cpu-cores.2774165/).

## What does pmemtester test that stressapptest doesn't (and vice versa)?

memtester runs 15 pattern tests per loop with ~2,590 total buffer sweeps per pass, targeting stuck bits and coupling faults with exhaustive patterns (stuck address, walking ones/zeroes, bit flip, checkerboard, etc.). Raw memory throughput is ~8,600 MB/s on a single modern core, but the thoroughness is what makes it slow per-byte-tested. stressapptest uses randomized block copies with CRC verification, targeting memory bus and interface timing issues (signal integrity, timing margins). It moves more data per second but tests fewer distinct bit patterns per memory location. The tools are complementary rather than directly comparable -- they detect different fault types. Additionally, pmemtester integrates EDAC error detection, which neither memtester nor stressapptest does on its own.

| | pmemtester | stressapptest |
|---|---|---|
| **Test method** | 15 deterministic pattern tests (~2,590 sweeps/loop) | Randomized block copies with CRC |
| **Primary focus** | RAM stick defects (cell-level faults) | Memory subsystem under stress (controller, bus) |
| **Targets** | Stuck bits, coupling faults, address decoder faults | Bus/interface timing, signal integrity |
| **Threading** | 1 memtester per CPU thread | 2 threads per CPU (auto) |
| **ECC/EDAC detection** | Yes (before/after comparison) | No |
| **Throughput** | ~8,600 MB/s per core (single-threaded) | ~10,000-14,000 MB/s aggregate (16-core x86) |
| **Duration** | Fixed (per-loop completion) | User-specified (continuous) |
| **Patterns per location** | ~2,590 per loop | Randomized (statistical coverage) |

References: [memtester source: tests.c](https://github.com/jnavila/memtester/blob/master/tests.c), [memtester source: sizes.h](https://github.com/jnavila/memtester/blob/master/sizes.h), [stressapptest repository](https://github.com/stressapptest/stressapptest), [Google Open Source Blog: Fighting Bad Memories](https://opensource.googleblog.com/2009/10/fighting-bad-memories-stressful.html).

## Why not drop caches before running?

`MemAvailable` in `/proc/meminfo` already accounts for reclaimable page cache and reclaimable slab (dentries/inodes) -- the kernel will evict these as needed when memtester allocates memory. Dropping caches (`echo 3 > /proc/sys/vm/drop_caches`) before running is unnecessary because the kernel reclaims clean cache pages on demand under allocation pressure. `MemAvailable` is deliberately conservative (it subtracts low watermarks and counts only half of reclaimable slab to account for fragmentation), so the actual reclaimable memory is slightly higher than the estimate -- but this works in pmemtester's favour, not against it. The practical outcome is the same whether you drop caches or not. Note that `drop_caches` only releases *clean* pages -- dirty pages (modified but not yet written to disk) are kept. If you did want to maximise free memory manually, you would need to run `sync` first to flush dirty pages to disk, converting them to clean pages that `drop_caches` can then release. But again, the kernel handles all of this automatically under allocation pressure, so neither `sync` nor `drop_caches` is needed before running pmemtester.
