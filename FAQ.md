# FAQ

## Speed and timing

pmemtester runs in two phases:

1. **Phase 1 — memtester (deterministic patterns):** Runs one memtester instance per physical core in parallel, dividing RAM equally. Wall-clock time scales inversely with core count up to memory bandwidth saturation (~3-5 cores on dual-channel, ~10+ cores on server platforms). On an AMD EPYC system (1 socket, 48 cores / 96 threads, 256 GB, 8 channels), pmemtester runs 48 instances of 4800 MB each, completing Phase 1 in ~2 hours (1 loop). A single memtester instance testing the same 225 GB would take roughly 4-5x longer (~8-10 hours vs ~2 hours), limited by memory bandwidth saturation rather than core count — see [Why does parallel memtester help?](#why-does-parallel-memtester-help).

2. **Phase 2 — stressapptest (randomised stress):** Runs stressapptest with the same total memory and thread count as Phase 1. By default (`--stressapptest-seconds 0`), the duration matches Phase 1's wall-clock time, so this phase takes approximately the same time. Use `--stressapptest off` to skip this phase entirely, or `--stressapptest-seconds N` to set an explicit duration.

The Phase 1 memtester run determines the stressapptest duration: if memtester takes 2 hours, stressapptest also runs for 2 hours (unless overridden). Total run time approximately doubles compared to memtester alone.

| Tool | Configuration | Phase 1 (memtester) | Phase 2 (stressapptest) | Total |
|------|--------------|---------------------|------------------------|-------|
| memtester | 1 instance, 225 GB | ~8-10 hours (1 loop) | — | ~8-10 hours |
| pmemtester (`--stressapptest off`) | 48 instances, 4800 MB each | ~2 hours (1 loop) | skipped | ~2 hours |
| pmemtester (default) | 48 instances + stressapptest | ~2 hours (1 loop) | ~2 hours | ~4 hours |
| pmemtester (`--stressapptest-seconds 3600`) | 48 instances + stressapptest | ~2 hours (1 loop) | 60 min | ~3 hours |

Example system: AMD EPYC (1 socket, 48 cores / 96 threads, 256 GB DDR5, 8 channels). pmemtester uses physical cores only (not SMT threads) — see [why per-core](#why-one-memtester-per-core-instead-of-one-per-thread).

Aggregate memory bandwidth saturates at ~10+ cores on an 8-channel server platform. Beyond saturation, additional threads share the same total bandwidth — throughput typically plateaus, and SMT threads can cause significant regression under memory-bound workloads. No published head-to-head benchmark exists on identical hardware, and memtester does not report throughput metrics, so direct comparison requires manual timing.

References: [memtester 64 GB timing estimate (GitHub issue #2)](https://github.com/jnavila/memtester/issues/2).

## What does pmemtester test that stressapptest doesn't (and vice versa)?

memtester runs 15 pattern tests per loop with ~2,590 total buffer sweeps per pass, targeting stuck bits and coupling faults with exhaustive patterns (stuck address, walking ones/zeroes, bit flip, checkerboard, etc.). Single-core throughput is limited by the CPU's L1D miss concurrency (Line Fill Buffers), which caps a single thread at ~8-10 GB/s on Intel Xeon server parts or ~15-20 GB/s on desktop/AMD parts with effective prefetching ([McCalpin 2025](https://sites.utexas.edu/jdm4372/2025/02/17/single-core-memory-bandwidth-latency-bandwidth-and-concurrency/)). memtester's non-sequential write-read-compare patterns get minimal prefetcher benefit, so throughput sits near the lower end of this range. stressapptest uses randomized block copies with CRC verification, targeting memory bus and interface timing issues (signal integrity, timing margins). It moves more data per second but tests fewer distinct bit patterns per memory location. The tools are complementary rather than directly comparable -- they detect different fault types. Additionally, pmemtester integrates EDAC error detection, which neither memtester nor stressapptest does on its own.

| | pmemtester | stressapptest |
|---|---|---|
| **Test method** | 15 deterministic pattern tests (~2,590 sweeps/loop) | Randomized block copies with CRC |
| **Primary focus** | RAM stick defects (cell-level faults) | Memory subsystem under stress (controller, bus) |
| **Targets** | Stuck bits, coupling faults, address decoder faults | Bus/interface timing, signal integrity |
| **Threading** | 1 memtester per core | 2 threads per CPU (auto) |
| **ECC/EDAC detection** | Yes (before/between/after comparison) | No |
| **Throughput** | ~8-10 GB/s per core on Xeon; ~15-20 GB/s on desktop/AMD | Hardware-dependent (stressapptest reports MB/s in output) |
| **Duration** | Fixed (per-loop completion) | User-specified (continuous) |
| **Patterns per location** | ~2,590 per loop | Randomized (statistical coverage) |

References: [memtester source: tests.c](https://github.com/jnavila/memtester/blob/master/tests.c), [memtester source: sizes.h](https://github.com/jnavila/memtester/blob/master/sizes.h), [stressapptest repository](https://github.com/stressapptest/stressapptest), [Google Open Source Blog: Fighting Bad Memories](https://opensource.googleblog.com/2009/10/fighting-bad-memories-stressful.html), [McCalpin: Single-core memory bandwidth (2025)](https://sites.utexas.edu/jdm4372/2025/02/17/single-core-memory-bandwidth-latency-bandwidth-and-concurrency/).

## How do memtester, stressapptest, and stress-ng find errors differently?

Each tool uses a fundamentally different algorithm, targeting different failure modes.

### memtester: sequential deterministic patterns ("microscope")

memtester allocates a buffer, locks it into RAM with `mlock`, and runs 15 pattern tests sequentially on that region. Each test writes a known pattern, reads it back, and compares:

- **Stuck Address**: Writes the address itself to each location, then verifies. Catches shorted address lines (writing to address A accidentally writes to address B).
- **Walking Ones / Walking Zeros**: Writes `00000001`, `00000010`, `00000100`, ... through each bit position. Catches individual dead capacitors (stuck-at-0 or stuck-at-1 faults).
- **Bit Flip**: Writes a value, reads back, flips all bits, writes, reads back. Catches coupling faults where adjacent cells influence each other.
- **Checkerboard / Bit Spread / Block Move**: Pattern variations that exercise different physical cell adjacency relationships.

Total: ~2,590 buffer sweeps per loop. Throughput is bounded by single-core memory bandwidth (~8-10 GB/s on Intel Xeon without prefetcher benefit, ~15-20 GB/s on desktop/AMD parts; [McCalpin 2025](https://sites.utexas.edu/jdm4372/2025/02/17/single-core-memory-bandwidth-latency-bandwidth-and-concurrency/)). memtester's non-sequential access patterns get minimal prefetching, so expect the lower end.

**Strength**: Exhaustive per-location pattern coverage. Finds hard faults (permanently damaged silicon) reliably.

**Weakness**: Single-threaded and predictable. Creates very little electrical noise or bus contention. A DIMM that is electrically marginal (fails only when hot or under voltage stress) may pass.

### stressapptest: randomised bandwidth saturation ("hammer")

Developed by Google specifically because deterministic tools were passing hardware that failed in production. The algorithm is designed to maximise memory bus contention:

- Spawns threads equal to the number of CPU cores
- **Randomised Copy**: Thread A copies a large chunk from address X to address Y
- **Invert**: Thread B reads from address Z, flips all bits, writes back
- **Disk-to-RAM**: Thread C writes data to disk and reads it back into RAM (stresses the DMA bus)
- Verification via CRC comparison after each operation

The threads race against each other, forcing the memory controller to rapidly switch between reading, writing, and refreshing different rows. This creates ground bounce and signal interference at the electrical level.

**Strength**: Maximises bus contention. Reveals electrically weak RAM that passes pattern-based tests. Widely considered the best userspace tool for DDR4/DDR5 intermittent stability errors.

**Weakness**: Statistical coverage per location — does not verify every bit pattern at every address. May miss hard faults that require specific patterns to detect.

### stress-ng: multi-modal OS stressor ("chaos monkey")

A configurable multi-modal stressor. Its `--vm` methods can mimic memtester patterns but add OS-level chaos:

- **galpat** (Galloping Pattern): A neighbour-sensitive variant where each cell is verified while all other cells hold different values. Catches coupling faults that depend on the state of surrounding cells.
- **rowhammer**: Specifically targets the rowhammer vulnerability by repeatedly accessing adjacent rows to induce bit flips in victim rows. Tests the DRAM's resistance to disturbance errors.
- **flip**: Bit inversion patterns similar to memtester but with configurable aggression.
- **Paging storms**: Forces the OS to swap memory in and out of disk, testing the RAM's ability to handle OS-level thrashing and page table management under extreme pressure.

**Strength**: Finds bugs where the memory subsystem interacts poorly with the kernel (page table corruptions, TLB shootdown races, cache coherency failures). Tests the full stack, not just RAM cells.

**Weakness**: Less focused than memtester (may not achieve the same per-location pattern depth) and less bandwidth-intensive than stressapptest (may not reveal marginal electrical issues).

### Effectiveness by failure scenario

| Scenario | memtester | stressapptest | stress-ng | pmemtester |
|----------|-----------|---------------|-----------|------------|
| **Dead capacitor (hard fault)** | Excellent — identifies the exact address | Good — may miss if random patterns don't hit the cell | Good — depends on stressor used | Excellent — memtester patterns + EDAC confirms hardware error |
| **Overheating RAM** | Poor — generates very little heat or bus load | Excellent — saturates bandwidth, stresses thermal envelope | Very good — significant heat under multi-worker load | Very good — parallel memtester + stressapptest second pass |
| **Bad memory controller** | Poor — sequential single-threaded load is too light | Excellent — this is its primary design goal | Good — high concurrent load stresses controller | Very good — parallel load + stressapptest randomised stress |
| **Power supply / VRM instability** | Poor — low current draw | Excellent — large current transients reveal weak PSUs | Good — high sustained load | Good — parallel load + stressapptest draws significant current |
| **Rowhammer vulnerability** | No | No | Yes — has specific rowhammer stressors | No (memtester does not target rowhammer) |

### Feature comparison

| Feature | memtester | stressapptest | stress-ng | pmemtester |
|---------|-----------|---------------|-----------|------------|
| Concurrency | Single-threaded | Multi-threaded (1 per core) | Massively parallel (N workers) | 1 memtester per core |
| Memory locking | `mlock` (may fail silently) | `mlock` on large allocations | `mlock`, `mmap`, `memfd`, etc. | `mlock` with pre-validation (`check_memlock_sufficient`) |
| DMA / bus stress | None — pure CPU-to-RAM | High — disk/network threads stress the bus | Variable — can stress I/O and RAM simultaneously | Optional — stressapptest second pass adds bus stress |
| ECC/EDAC detection | No | No | No | Yes — EDAC counter comparison (before/between/after phases) |
| Pattern depth per location | ~2,590 sweeps/loop | Statistical (CRC-verified) | Configurable | ~2,590 sweeps/loop |
| Bus saturation | ~15-25% of peak ([Rupp 2015](https://www.karlrupp.net/2015/02/stream-benchmark-results-on-intel-xeon-and-xeon-phi/)) | ~75-85% of peak | Variable | ~75-90% of peak ([McCalpin 2023](https://sites.utexas.edu/jdm4372/2023/04/25/the-evolution-of-single-core-bandwidth-in-multicore-processors/)) |
| Verification | Immediate after each write | Asynchronous CRC checksum | Immediate or checksum | Immediate after each write |
| CLI complexity | Simple: `memtester 10G` | Moderate: `stressapptest -W -s 60 -M 10000` | Complex: `stress-ng --vm 4 --vm-bytes 90%` | Simple: `pmemtester --percent 90` |

### Where pmemtester fits

pmemtester wraps memtester's thorough 15-pattern testing with per-core parallelism (closing the bandwidth gap with stressapptest) and EDAC hardware error monitoring (detecting errors invisible to all three tools). pmemtester also runs an optional stressapptest second pass after memtester completes (enabled by default in `auto` mode when the binary is present), combining both testing approaches in a single tool. It is a "microscope with bus saturation" — deterministic patterns at near-peak memory bandwidth, randomised stress testing, plus hardware error detection.

References: [memtester source: tests.c](https://github.com/jnavila/memtester/blob/master/tests.c), [stressapptest source](https://github.com/stressapptest/stressapptest), [Google: Fighting Bad Memories](https://opensource.googleblog.com/2009/10/fighting-bad-memories-stressful.html), [stress-ng vm stressors](https://wiki.ubuntu.com/Kernel/Reference/stress-ng), [stress-ng source: stress-vm.c](https://github.com/ColinIanKing/stress-ng/blob/master/stress-vm.c), [Kim et al., "Flipping Bits in Memory Without Accessing Them" (ISCA 2014, rowhammer)](https://users.ece.cmu.edu/~yoMDL/papers/kim-isca14.pdf).

## Which tool should I use?

**Diagnosing a suspected bad DIMM (random crashes, BSODs, kernel panics):**
Boot into [Memtest86+](https://www.memtest.org/) from USB. Bare-metal testing has direct physical memory access and is the gold standard for hardware validation. No userspace tool can fully substitute because the OS reserves memory that userspace cannot test. If you must stay in the OS, use memtester (or pmemtester for parallelism + EDAC) — it is the most methodical at verifying individual cells.

**Validating overclocking, new RAM timings, or cooling:**
Use pmemtester. It runs memtester's 15-pattern cell testing followed by a stressapptest pass for bus-contention and thermal stress, with EDAC monitoring throughout. A single `./pmemtester --stressapptest-seconds 3600` covers both pattern validation and stability testing. Standalone stressapptest is no longer the recommended approach since pmemtester includes it as Phase 2, adds EDAC error detection (invisible to stressapptest alone), and tests each cell deterministically first.

**Server burn-in or production deployment validation:**
Use pmemtester. It combines memtester's thorough cell-level testing with parallel bandwidth saturation, an optional stressapptest second pass for bus-contention stress testing, and EDAC monitoring. The `--allow-ce` flag lets you distinguish between correctable errors (monitor and track) and uncorrectable errors (fail immediately). By default (`--stressapptest auto`), pmemtester runs stressapptest automatically after memtester if the binary is found, using the same duration and total memory as the memtester pass.

**Kernel development, OOM testing, swap stability:**
Use stress-ng. It stresses the entire virtual memory stack — OOM killer behaviour, swap partition stability, page table management, cache coherency. Its rowhammer stressors are also the only userspace way to test DRAM disturbance error susceptibility.

**Fleet-scale memory health monitoring (datacentres):**
Use rasdaemon for continuous EDAC monitoring, with periodic pmemtester runs during maintenance windows. pmemtester's CE/UE classification and `--allow-ce` flag align with modern vendor guidance (see [CE thresholds](#how-many-correctable-errors-before-replacing-a-dimm)) that distinguishes correctable from uncorrectable errors rather than treating all EDAC events as failures.

References: [Memtest86+ homepage](https://www.memtest.org/), [stressapptest repository](https://github.com/stressapptest/stressapptest), [stress-ng repository](https://github.com/ColinIanKing/stress-ng), [rasdaemon repository](https://github.com/mchehab/rasdaemon).

## What are hard errors vs soft errors?

**Hard errors** (permanent faults) are physical defects in DRAM: failed cells, stuck bits, broken row/column decoders. They are reproducible -- the same address fails consistently on re-read. They require DIMM replacement or Post Package Repair (PPR) to resolve.

**Soft errors** (transient faults) are one-time bit flips caused by cosmic ray neutrons, alpha particles from packaging materials, or electrical noise. They are not reproducible -- a re-read returns the correct value. They do not indicate physical damage.

Large-scale field studies have found that **hard errors dominate** in practice, contrary to earlier assumptions. Schroeder et al. (2009) at Google found "strong evidence that memory errors are dominated by hard errors." Sridharan and Liberty (2012) confirmed that "DRAM failures are dominated by permanent, rather than transient, faults" and that "large multi-bit faults, such as faults that affect an entire DRAM row or column, constitute over 40% of all DRAM faults."

Standard ECC (SECDED) corrects any single-bit error and detects double-bit errors. For soft errors, ECC corrects the flip transparently. For hard errors, ECC repeatedly corrects the same location, generating a stream of correctable error (CE) reports. Chipkill/SDDC (Single Device Data Correction) can correct all errors from a single failed DRAM chip -- Schroeder et al. found it reduces uncorrectable error rates by 38x; Sridharan and Liberty found a 42x reduction.

Both hard and soft errors appear as CEs in EDAC. Recurring CEs at the same physical address strongly indicate a hard fault. A soft error typically produces a single CE and does not recur.

References: [Schroeder et al., "DRAM Errors in the Wild" (SIGMETRICS 2009)](https://www.cs.toronto.edu/~bianca/papers/sigmetrics09.pdf), [Sridharan and Liberty, "A Study of DRAM Failures in the Field" (SC 2012)](https://dl.acm.org/doi/abs/10.5555/2388996.2389100), [Linux Kernel EDAC documentation](https://docs.kernel.org/driver-api/edac.html).

## How many correctable errors before replacing a DIMM?

There is no universal answer. Vendor thresholds vary widely, and the industry trend is toward tolerating CEs rather than replacing DIMMs on CE count alone.

| Vendor | CE Threshold | Time Period | Action |
|--------|-------------|-------------|--------|
| Intel | 10 (default) | Per DIMM per 24 hours | Monitor if below; investigate if above |
| Oracle/Sun | 24 | Per DIMM per 24 hours | Replace DIMM; fault LED lit |
| HPE | Proprietary | Not published | Reseat, update ROM, replace if persists |
| Dell | Disabled by default (since March 2022) | N/A | Rely on PPR self-heal; replace only if self-heal fails |
| Cisco | Removed (since UCS 2.27/3.1) | N/A | No replacement for CE-only DIMMs |

**Intel's threshold of 10** comes from the "Memory Replacement Guideline and Advanced Memory Test for DSG Server Systems" document. Intel acknowledges this default "was useful for older systems on DDR3 memory, with less than 8 GB of total memory" and recommends tuning it upward for modern DDR4 systems with large memory configurations.

**Dell** disabled CE logging by default in March 2022, stating: "Within the global server industry, there is an increasingly accepted understanding that some correctable errors per DIMM are unavoidable." Dell relies on DDR4 Post Package Repair (PPR) to permanently replace bad rows with spare rows via electrical fusing.

**Cisco** removed CE thresholds entirely, stating: "Given extensive research that correctable errors are not correlated with uncorrectable errors, and that correctable errors do not degrade system performance."

For pmemtester, any non-zero EDAC CE count during a test is worth reporting, but a small count is not necessarily cause for immediate replacement. The rate, pattern (same address vs scattered), and whether it recurs on retest all matter.

References: [Intel Memory Replacement Guideline (PDF)](https://www.intel.com/content/dam/support/us/en/documents/server-products/memory-replacement-guideline-and-amt-guide-for-dsg-server-systems.pdf), [Intel ECC Memory Errors (article 000094930)](https://www.intel.com/content/www/us/en/support/articles/000094930/server-products.html), [Dell: Managing CE Threshold Events](https://www.dell.com/support/kbdoc/en-us/000194574/14g-intel-and-15g-intel-amd-poweredge-servers-ddr4-memory-managing-correctable-error-threshold-events), [Cisco: Managing Correctable Memory Errors (PDF)](https://www.cisco.com/c/dam/en/us/support/docs/servers-unified-computing/ucs-b-series-blade-servers/ManagingCorrectableMemoryErrorsFinalJuly142020.pdf), [Oracle/Sun DIMM Troubleshooting](https://docs.oracle.com/cd/E19121-01/sf.x4440/820-3067-14/dimms.html).

## Do correctable errors predict future uncorrectable errors?

The evidence is mixed.

**Google/Toronto (Schroeder et al., 2009)**: The landmark study found that the probability of an uncorrectable error increases by **27x to 400x** (varying by platform) in a month where correctable errors are also present. More than 8% of DIMMs experienced at least one CE per year. About one-third of all machines saw at least one CE per year. 20% of machines with errors accounted for more than 90% of all observed errors. Error rates increased with DIMM age, spiking between 10 and 18 months.

**Facebook/CMU (Meza et al., 2015)**: Found correctable error rates were 20x higher than uncorrectable error rates. Newer DRAM technologies showed up to 1.8x higher failure rates than previous generations. Page offlining reduced memory error rates by 67%.

**LANL/Cielo (Levy et al., 2018)**: A contrarian finding from a 5-year study of an HPC supercomputer: "Contrary to popular belief, **correctable DRAM faults are not predictive of future uncorrectable DRAM faults**." The system exhibited no aging effects and uncorrectable errors showed no increase over its lifetime.

**ByteDance (Li et al., SC 2022)**: Found that the specific error-bit pattern matters more than the raw CE count. On contemporary Intel platforms, weakened ECC (compared to traditional chipkill) cannot tolerate some error-bit patterns from a single chip. Their "risky CE" indicator -- based on whether the CE falls outside ECC guaranteed coverage -- showed consistently high sensitivity and specificity for predicting future UEs.

The consensus: CEs are a meaningful signal at fleet scale, but not all CEs are equally predictive. Recurring CEs at the same address indicate a hard fault. CEs whose bit patterns approach ECC correction limits are the most dangerous. A small number of isolated CEs during an intensive memory test may be benign.

References: [Schroeder et al., "DRAM Errors in the Wild" (2009)](https://cacm.acm.org/research/dram-errors-in-the-wild/), [Meza et al., "Revisiting Memory Errors" (DSN 2015)](https://users.ece.cmu.edu/~omutlu/pub/memory-errors-at-facebook_dsn15.pdf), [Levy et al., "Lessons Learned from Cielo" (SC 2018)](https://ieeexplore.ieee.org/document/8665809/), [Li et al., "From Correctable to Uncorrectable" (SC 2022)](https://dl.acm.org/doi/abs/10.5555/3571885.3571986), [Sridharan et al., "Memory Errors in Modern Systems" (ASPLOS 2015)](https://pages.cs.wisc.edu/~remzi/Classes/739/Fall2015/Papers/memoryerrors-asplos15.pdf).

## Why does parallel memtester help?

A single memtester thread cannot saturate a modern memory bus. CPU cores have a limited number of outstanding memory requests (Line Fill Buffers), so one thread typically achieves only 15-25% of peak memory bandwidth on a server CPU ([Rupp 2015](https://www.karlrupp.net/2015/02/stream-benchmark-results-on-intel-xeon-and-xeon-phi/), [McCalpin 2025](https://sites.utexas.edu/jdm4372/2025/02/17/single-core-memory-bandwidth-latency-bandwidth-and-concurrency/)). Running multiple instances in parallel fills more memory channels simultaneously and reaches 75-90% of peak bandwidth with around 10 threads on current x86 hardware ([McCalpin 2023](https://sites.utexas.edu/jdm4372/2023/04/25/the-evolution-of-single-core-bandwidth-in-multicore-processors/), [Hager 2018](https://blogs.fau.de/hager/archives/8263)) -- roughly a **4-7x speedup** over a single thread on one socket.

On multi-socket systems, pmemtester's per-core parallelism also keeps memory accesses NUMA-local. A single memtester process testing both sockets would pay a cross-socket bandwidth penalty (see below), while pmemtester's many independent instances naturally access memory local to the core they run on.

| System | Channels | Speedup vs 1 thread |
|--------|----------|---------------------|
| Desktop (dual-channel DDR5) | 2 | ~2x |
| Workstation (quad-channel DDR5) | 4 | ~3-4x |

### Current server platforms (2025-2026)

| Platform | Ch/socket | Sockets | Total ch | Speedup vs 1 thread |
|----------|-----------|---------|----------|----------------------|
| AmpereOne (ARM, 1S) | 8 | 1 | 8 | ~4-5x |
| AmpereOne M (ARM, 1S) | 12 | 1 | 12 | ~4-6x |
| Intel Xeon 6900P (Granite Rapids, 1S) | 12 | 1 | 12 | ~4-6x |
| AMD EPYC 9005 Turin (1S) | 12 | 1 | 12 | ~4-6x |
| Intel Xeon 6700P (Granite Rapids, 2S) | 8 | 2 | 16 | ~8-10x |
| AMD EPYC 9005 Turin (2S) | 12 | 2 | 24 | ~8-12x |
| Intel Xeon 6900P (Granite Rapids, 2S) | 12 | 2 | 24 | ~8-12x |
| Intel Xeon 6700P (Granite Rapids, 4S) | 8 | 4 | 32 | ~16-20x |
| IBM POWER10 (SCM, 4S per node) | 16 | 4 | 64 | ~16-24x |
| Intel Xeon 6700P (Granite Rapids, 8S) | 8 | 8 | 64 | ~25-40x |
| IBM POWER11 (SCM, 4S per node) | 32 | 4 | 128 | ~16-28x |
| IBM POWER10 (4-node, 16S) | 16 | 16 | 256 | ~40-80x |
| IBM POWER11 (4-node, 16S) | 32 | 16 | 512 | ~50-100x |

**How the speedup estimates work:**

Within a single socket, the speedup is limited by how much bandwidth one thread can use versus the socket's peak. STREAM benchmarks consistently show one thread achieves ~15-25% of peak socket bandwidth on current x86 and ARM server CPUs, so saturating one socket gives ~4-7x. Multi-socket configurations multiply this by the number of sockets, but with diminishing returns from interconnect overhead, memory controller contention, and OS scheduling -- real-world multi-socket STREAM scaling is typically 85-95% efficient per additional socket at 2S, declining to ~60-80% at 8S+ and ~50-65% at 16S.

Beyond ~1-2 threads per memory channel, additional threads provide no further bandwidth benefit. The number of channels determines the ceiling; the number of threads needed to reach it is much smaller.

### Cross-socket bandwidth penalty (NUMA)

On multi-socket systems, accessing memory attached to a remote socket incurs a significant bandwidth and latency penalty. pmemtester avoids this because each instance runs on a local core and allocates local memory, but a single-threaded memory tester spanning both sockets would pay the full penalty:

| Metric | Modern 2S systems | Older 2S systems |
|--------|-------------------|------------------|
| Latency penalty | ~30-50% higher for remote | up to 2-7x higher |
| Read bandwidth penalty | ~50-70% reduction | ~67-84% reduction |
| Write bandwidth penalty | ~15-30% reduction | varies |

Measured examples:
- Intel Xeon E5 (Haswell, 2S): remote reads dropped to **16-33%** of local bandwidth; remote writes retained ~83% ([Intel Community](https://community.intel.com/t5/Software-Tuning-Performance/Memory-bandwidth-on-a-NUMA-system/td-p/1095836))
- AMD EPYC 9005 (Turin): intra-socket cross-CCD penalty is low (~20-30ns) due to the centralised IO die design; cross-socket penalty follows the ~30-50% range ([Chips and Cheese](https://chipsandcheese.com/p/amds-epyc-9355p-inside-a-32-core))
- Intel Xeon 6900P (Granite Rapids): intra-socket cross-die latency can reach ~180ns in HEX mode due to distributed memory controllers across 3 compute tiles ([Phoronix](https://www.phoronix.com/review/xeon-6980p-snc3-hex))
- Under heavy contention (many cores competing for one node's memory), remote latencies can reach 4x normal (~1200 vs ~300 cycles) ([ACM Queue](https://queue.acm.org/detail.cfm?id=2852078))

This is why pmemtester's parallel design matters most on multi-socket systems: the aggregate NUMA locality benefit is equivalent to a **1.4-2x** additional speedup compared to a non-NUMA-aware single-process approach.

**Platform notes:**
- AMD EPYC 9005 maxes out at 2 sockets. AMD relies on high core counts (up to 192 cores/socket) instead of 4S+ configurations.
- Intel Xeon 6900P (12-channel, high-end) is 2S max. The Xeon 6700P (8-channel) scales to 4S/8S on the smaller LGA 4710 platform.
- AmpereOne is single-socket only, compensating with up to 192 ARM cores per socket.
- IBM POWER10 uses 16 OMI (Open Memory Interface) channels per SCM chip. The E1080 scales to 4 nodes of 4 sockets each (16S total, 256 channels).
- IBM POWER11 doubles to 32 DDR5 ports per chip via OMI. The E1180 scales to 16 sockets across 4 nodes (512 channels total).
- POWER systems use OMI (a serialised memory interface) rather than direct DDR channels, providing equivalent or higher bandwidth in less die area.

## Why one memtester per core instead of one per thread?

pmemtester launches one memtester instance per physical CPU core (via `lscpu`), not per hardware thread. On a 16-core/32-thread system, that means 16 instances. This is deliberate -- SMT threads share the same core's memory pipeline and adding them causes measurable bandwidth regression for memory-bound workloads.

### SMT bandwidth regression

Georg Hager measured STREAM Copy bandwidth scaling on a dual-socket AMD EPYC 7451 (48 physical cores, 96 hardware threads). The results show clear regression when SMT threads are added beyond the physical core count:

- **48 physical cores**: ~241 GB/s aggregate STREAM Copy bandwidth
- **96 hardware threads** (all SMT siblings active): ~79 GB/s -- a **3x degradation**

This is not an anomaly. On memory-bound workloads, SMT siblings compete for the same core's Line Fill Buffers, load/store queues, and TLB entries. Each sibling gets less effective bandwidth than a single thread on the same core would. The total bandwidth per core *decreases* -- the system moves less data with 96 threads than with 48.

The effect is architecture-dependent but consistently negative for memory-intensive workloads:

| Architecture | Cores | SMT threads | STREAM bandwidth regression |
|---|---|---|---|
| AMD EPYC 7451 (2S) | 48 | 96 | ~3x (241 → 79 GB/s) |
| Intel Xeon (typical 2S) | varies | 2x cores | ~10-30% regression |

Reference: [Georg Hager: How STREAM bandwidth scales with core count](https://blogs.fau.de/hager/archives/8263)

### Why per-core is optimal for memtester

memtester is purely memory-bound -- it writes patterns, reads them back, and compares. It has no compute bottleneck that SMT could help with. Running one instance per physical core:

1. **Maximises bandwidth**: Each core's full memory pipeline serves one memtester process without SMT contention
2. **Avoids regression**: No wasted bandwidth from SMT siblings competing for the same resources
3. **Larger allocations per process**: 16 processes × 1750 MB exercises the same total RAM as 32 × 875 MB, but with fewer process management overheads and more contiguous memory access patterns

### Core detection

pmemtester uses `lscpu -b -p=Socket,Core` to enumerate unique physical cores across all sockets. This correctly handles:

- **SMT deduplication**: On a 16-core/32-thread system, lscpu lists 32 lines but only 16 unique Socket,Core pairs
- **Multi-socket systems**: Each socket's cores are counted separately (socket 0 core 0 ≠ socket 1 core 0)
- **Online-only CPUs**: The `-b` flag filters to online CPUs only, handling hotplug correctly

If `lscpu` is unavailable (minimal containers, embedded systems), pmemtester falls back to `nproc`, which returns hardware threads. This is a conservative fallback -- more processes than needed, but functional.

## Which Linux distros support EDAC?

Nearly all major distros enable `CONFIG_EDAC=y` (built-in) with hardware drivers as loadable modules:

| Distro | EDAC Enabled | Notes |
|--------|-------------|-------|
| RHEL 8/9/10 | Yes | Full support |
| Rocky / AlmaLinux 9 | Yes | Mirrors RHEL |
| Fedora | Yes | Full driver set |
| Ubuntu 22.04/24.04 | Yes | Cloud kernels may differ |
| Debian 12 | Yes | Cloud kernel disables EDAC |
| SLES / openSUSE | Yes | Full server-grade support |
| Arch Linux | Yes | Loads even on desktop hardware |
| Gentoo | Manual | User must enable in kernel config |

## Which CPU architectures support EDAC?

EDAC is available on most Linux-supported architectures, though driver coverage varies:

| Architecture | EDAC Support | Drivers |
|---|---|---|
| x86 / x86_64 | Yes | ~25 drivers: Intel (440BX through Ice Lake+), AMD (K8 through Zen 6) |
| ARM64 / AArch64 | Yes | ThunderX, X-Gene, BlueField, Qualcomm LLCC, DMC-520, Cortex-A72 |
| ARM (32-bit) | Yes | Calxeda, Altera SOCFPGA, Armada XP, Aspeed BMC, TI |
| PowerPC | Yes | IBM CPC925, Cell BE, PA Semi, Freescale MPC85xx |
| RISC-V | Yes | SiFive CCACHE only |
| LoongArch | Yes | Loongson 3A5000/3A6000 family |
| MIPS | Partial | Cavium Octeon only |
| s390 | No | Uses hypervisor/firmware RAS instead |

The `EDAC_GHES` firmware-first driver (ACPI/APEI) works on any architecture with UEFI firmware support, providing a uniform EDAC sysfs interface regardless of the specific memory controller.

## How do standalone boot tools (MemTest86, Memtest86+) detect ECC errors?

Standalone boot tools run at the highest CPU privilege level (Ring 0 on x86, EL1/EL2 on ARM64, PLV0 on LoongArch) and poll hardware registers directly — no OS or EDAC driver is involved.

### MemTest86 (PassMark)

MemTest86 uses four different register access mechanisms depending on the chipset:

1. **MCA (Machine Check Architecture) MSRs** — reads MCi_STATUS, MCi_ADDR, and MCi_MISC registers via `rdmsr`. Bit 61 (UC) of MCi_STATUS distinguishes correctable from uncorrectable errors.
2. **IMC PCI registers** — chipset-specific Integrated Memory Controller registers that record DRAM address details (rank, bank, row, column).
3. **Sideband registers** — used on Intel Atom SoCs via an internal bus.
4. **AMD SMN (System Management Network)** — used on AMD Ryzen/EPYC to access Unified Memory Controller ECC registers.

Each chipset family requires specific polling code. PassMark has added support incrementally across dozens of Intel and AMD chipsets (Sandy Bridge through Arrow Lake/Lunar Lake; AMD FX through Zen 5). **ARM64 has no ECC support** — PassMark stated they have not seen ARM platforms with ECC RAM for testing.

**Free vs Pro edition:**

| Feature | Free | Pro |
|---------|------|-----|
| ECC mode/capability detection | Yes | Yes |
| ECC error polling (CE + UE counts) | Yes | Yes |
| Faulty DIMM identification (per-DIMM address decoding) | No | Yes |
| ECC error injection | No | Yes |

Per-DIMM identification requires reversing the memory controller's address interleaving configuration to map a physical address to a specific channel, slot, rank, bank, row, and column. On AMD this is documented in the Processor Programming Reference; on Intel the address decoding scheme is often proprietary.

### Memtest86+

Memtest86+ polls AMD UMC (Unified Memory Controller) MCA MSR banks and AMD SMN registers. The implementation is in `system/imc/x86/amd_zen.c` in the source tree. It reads UMC MCA Status MSRs to detect errors, distinguishes CE from UE via dedicated status bits, reads the error address from UMC MCA Address MSRs, and reads error counts from SMN registers.

**Current limitations:**

- **AMD Ryzen only.** Supported families: Zen (Family 17h), Zen 3 Vermeer, Zen 3+ Rembrandt, Zen 4 Raphael, Zen 5 Granite Ridge. There is zero Intel ECC polling code in the codebase — the Intel IMC files handle memory timings only.
- **Disabled by default.** `enable_ecc_polling` is `false` in `app/config.c` and there is no command-line flag to enable it — you must edit the source and recompile. [PR #566](https://github.com/memtest86plus/memtest86plus/pull/566) (open, not yet merged) would add a runtime toggle.
- **No LoongArch or other architecture ECC support.**

### How hardware distinguishes CE from UE

The memory controller's SECDED (Single Error Correct, Double Error Detect) logic generates a syndrome when reading ECC-protected data. A non-zero syndrome that maps to a single correctable bit triggers a CE flag; a syndrome indicating an error beyond correction capability triggers a UE flag. The standalone tools simply read these hardware-populated status bits — they do not implement ECC decoding themselves.

References: [MemTest86 ECC technical details](https://www.memtest86.com/ecc.htm), [MemTest86 edition comparison](https://www.memtest86.com/compare.html), [Memtest86+ GitHub: ECC discussion #92](https://github.com/memtest86plus/memtest86plus/discussions/92), [Memtest86+ GitHub: enabling ECC in v7 discussion #436](https://github.com/memtest86plus/memtest86plus/discussions/436), [Memtest86+ GitHub: ECC polling option PR #566](https://github.com/memtest86plus/memtest86plus/pull/566).

## How do I evacuate a socket for dedicated memory testing?

On a multi-socket server you may want to test one socket's RAM while keeping the other socket running production workloads. This requires moving both process execution and memory pages off the target socket before running pmemtester on it.

### 1. Identify your topology

```bash
# Show socket/core/NUMA layout
lscpu | grep -e "Socket(s)" -e "Core(s) per socket" -e "NUMA node"

# Show per-node memory and CPU assignments
numactl --hardware
```

This tells you which logical cores and memory belong to each NUMA node (typically node 0 = socket 0, node 1 = socket 1).

### 2. Move processes off the target socket

Use `taskset` to change CPU affinity for running user processes. Moving kernel threads is restricted and generally unnecessary — focus on user-space processes.

```bash
# Move all user processes from socket 0 (cores 0-15) to socket 1 (cores 16-31)
# Adjust core ranges to match your topology from step 1
for pid in $(ps -e -o pid=); do
    taskset -pc 16-31 "$pid" 2>/dev/null
done
```

For services managed by systemd, set `CPUAffinity=` in the unit file or use `systemctl set-property`:

```bash
systemctl set-property myservice.service CPUAffinity=16-31
```

### 3. Migrate memory pages

Moving process execution is only half the job. If a process runs on socket 1 but its pages remain in socket 0's RAM, those pages occupy the memory you want to test and incur a cross-socket NUMA penalty.

```bash
# Migrate all pages of PID 1234 from node 0 to node 1
migratepages 1234 0 1
```

Not all pages can be migrated (kernel pages, huge pages in use, mlocked pages). Check `/proc/<pid>/numa_maps` to verify migration.

### 4. Run pmemtester on the evacuated socket

```bash
# Test socket 0's RAM using socket 0's cores
sudo numactl --cpunodebind=0 --membind=0 pmemtester --percent 90
```

The `--percent 90` applies to available memory on that NUMA node, not the whole system. Because you evacuated most processes, more of the node's RAM will be available for testing.

### 5. Persistent isolation with cgroups

For repeated testing or to prevent processes from migrating back, use cpuset cgroups to fence off an entire socket:

```bash
# cgroups v2 (modern distros)
mkdir /sys/fs/cgroup/socket0_test
echo "+cpuset" > /sys/fs/cgroup/socket0_test/cgroup.subtree_control
echo "0-15" > /sys/fs/cgroup/socket0_test/cpuset.cpus
echo "0" > /sys/fs/cgroup/socket0_test/cpuset.mems

# Move pmemtester into the cgroup
echo $$ > /sys/fs/cgroup/socket0_test/cgroup.procs
sudo numactl --membind=0 pmemtester --percent 90
```

On older systems using cgroups v1, the path is `/sys/fs/cgroup/cpuset/` and processes are assigned via the `tasks` file.

### Limitations

- **Kernel memory cannot be evacuated.** Kernel slab caches, page tables, and DMA buffers on the target node remain untestable from userspace. This is a fundamental limitation of all userspace memory testing (see [userspace vs bare-metal](#userspace-vs-bare-metal-testing) in the README).
- **`migratepages` is best-effort.** Pages that are mlocked, in active I/O, or backed by huge pages may not migrate. Verify with `numastat -p <pid>`.
- **EDAC counters are system-wide.** Even with socket isolation, pmemtester's EDAC check sees errors from both sockets. An EDAC error on the non-tested socket during the run will cause a false FAIL.

References: [numactl(8)](https://linux.die.net/man/8/numactl), [migratepages(8)](https://linux.die.net/man/8/migratepages), [cgroups v2 cpuset (kernel.org)](https://docs.kernel.org/admin-guide/cgroup-v2.html#cpuset-interface-files), [taskset(1)](https://linux.die.net/man/1/taskset).

## Why not drop caches before running?

`MemAvailable` in `/proc/meminfo` already accounts for reclaimable page cache and reclaimable slab (dentries/inodes) -- the kernel will evict these as needed when memtester allocates memory. Dropping caches (`echo 3 > /proc/sys/vm/drop_caches`) before running is unnecessary because the kernel reclaims clean cache pages on demand under allocation pressure. `MemAvailable` is deliberately conservative (it subtracts low watermarks and counts only half of reclaimable slab to account for fragmentation), so the actual reclaimable memory is slightly higher than the estimate -- but this works in pmemtester's favour, not against it. The practical outcome is the same whether you drop caches or not. Note that `drop_caches` only releases *clean* pages -- dirty pages (modified but not yet written to disk) are kept. If you did want to maximise free memory manually, you would need to run `sync` first to flush dirty pages to disk, converting them to clean pages that `drop_caches` can then release. But again, the kernel handles all of this automatically under allocation pressure, so neither `sync` nor `drop_caches` is needed before running pmemtester.

## What happens when Linux encounters an ECC uncorrectable error?

An uncorrectable error (UE) means the memory controller detected corruption it cannot fix. Unlike a correctable error (CE), where ECC silently repairs the data, a UE means the data is lost. What the kernel does depends on how the error was detected and what the corrupted memory was being used for.

### How the hardware reports UEs

The CPU classifies uncorrectable errors into three categories (Intel terminology; AMD is broadly similar):

| Type | Meaning | Signal | Severity |
|------|---------|--------|----------|
| **SRAR** (Action Required) | CPU consumed or is about to consume corrupted data | Machine Check Exception (#MC) | Highest — recovery mandatory before execution can resume |
| **SRAO** (Action Optional) | Corruption detected but not consumed (e.g., patrol scrub) | #MC or CMCI | Medium — processor state is valid, page can be retired proactively |
| **UCNA** (No Action) | Corruption detected in background, not consumed | CMCI (not #MC) | Lowest — informational, page can be poisoned preventively |

The distinction matters because a patrol scrub UE (SRAO/UCNA) is detected *before* any process reads the bad data, giving the kernel a chance to retire the page transparently. A consumed UE (SRAR) means a process already has or is about to use corrupted data.

### The kernel's decision tree

When the MCE handler runs, it classifies the error via `mce_severity()` and routes to one of these outcomes:

**Kernel panic** — when any of these are true:
- Processor Context Corrupt (PCC) bit is set in MCA status — the CPU's own state is unreliable
- No Restart IP available while in kernel mode — the kernel cannot resume
- `CONFIG_MEMORY_FAILURE` is not enabled — the kernel has no recovery mechanism
- The corrupted page belongs to a kernel slab object, page table, or other internal data structure that cannot be recovered

**Page poisoned and retired** — when `CONFIG_MEMORY_FAILURE` is enabled (all major distros enable this by default) and the page type is recoverable. The kernel:
1. Sets the `PG_hwpoison` flag on the page, permanently excluding it from future allocation
2. Unmaps the page from all processes that had it mapped
3. Executes a page-type-specific handler (see recovery table below)

**Process signalled** — affected processes receive `SIGBUS`:
- `BUS_MCEERR_AR` (Action Required): synchronous, delivered to the thread that consumed the corrupted data. Means "you used bad data, handle this now or die."
- `BUS_MCEERR_AO` (Action Optional): asynchronous, delivered to processes that have the page mapped but haven't consumed it yet. Only sent to processes that opted into early notification via `prctl(PR_MCE_KILL_EARLY)` or the `vm.memory_failure_early_kill` sysctl.

### Recovery by page type

| Page type | What happens | Data lost? |
|-----------|-------------|------------|
| **Clean file-backed** (page cache) | Kernel drops the page and re-reads from disk on next access | No |
| **Dirty file-backed** (page cache) | Page truncated; `fsync()`/`write()` returns `-EIO` to notify application | Yes — unflushed writes are lost |
| **Anonymous** (heap, stack) | Page unmapped; process gets SIGBUS on next access (or immediately if early-kill) | Yes — no backing store |
| **Clean swap cache** | Removed from swap cache; swap slot still has valid data | No |
| **Dirty swap cache** | Dirty bit cleared; process killed lazily on swap-in | Yes |
| **HugeTLB** | Entire huge page unmapped from all processes | Yes (for mapped data) |
| **THP** (Transparent Huge Page) | Split to 4K pages first, then only the poisoned page is retired | Only the affected 4K region |
| **KSM** (merged page) | All processes sharing the merged page are signalled; page unmerged | Yes |
| **Kernel internal** (slab, page tables) | Not recoverable — kernel panic | N/A |

### Patrol scrub vs consumed errors

Patrol scrub (background memory scrubbing by the memory controller) can detect UEs proactively — before any process reads the bad data. These are reported as SRAO or UCNA, and the kernel can poison the page and unmap it transparently. No process needs to be killed if the page is a clean file-backed page or if no process has accessed it yet. This is the best-case scenario for a UE.

A consumed UE (SRAR) means a process already tried to use the corrupted data. The kernel must signal the process immediately. For anonymous pages (heap/stack), the data is unrecoverable and the process must handle SIGBUS or be killed.

### Early kill vs late kill

The kernel supports two policies for notifying processes about poisoned pages they have mapped but haven't consumed yet:

- **Late kill** (default): No signal until the process actually accesses the poisoned page. At that point it gets `BUS_MCEERR_AR`. This minimises unnecessary process kills — the process may never touch that page again.
- **Early kill**: `BUS_MCEERR_AO` is sent immediately to all processes mapping the page. Enable per-process with `prctl(PR_MCE_KILL_EARLY)` or system-wide with `sysctl vm.memory_failure_early_kill=1`.

### Can applications survive a UE?

In theory, yes — a process can install a `SIGBUS` handler and use `siglongjmp()` to recover. In practice, almost no applications do this. The one major exception is **QEMU/KVM**, which intercepts `BUS_MCEERR_AR`/`BUS_MCEERR_AO` and injects a virtual MCE into the guest VM, letting the guest OS handle the error. No major database (PostgreSQL, MySQL, Oracle) or JVM implements MCE-aware SIGBUS recovery — a hardware UE in their memory crashes the process.

### The tolerant sysctl

The `tolerant` sysctl (`/sys/devices/system/edac/mc/mc*/tolerant` or the x86 MCE `tolerant` parameter) controls panic policy:

| Value | Behaviour |
|-------|-----------|
| 0 | Always panic on any uncorrected error |
| 1 | Attempt recovery; panic if not possible (default) |
| 2 | Log and continue when possible (permissive) |
| 3 | Never panic, log only (dangerous — risks silent corruption) |

### Monitoring tools

**mcelog** is deprecated. It relied on `CONFIG_X86_MCELOG_LEGACY`, deprecated since Linux 4.12 (2017), and does not support modern AMD processors. Use **rasdaemon**, which reads the modern EDAC tracing subsystem and records events to the systemd journal and optionally SQLite. Query with `ras-mc-ctl --error-count` or `ras-mc-ctl --summary`.

### What this means for pmemtester

pmemtester monitors EDAC counters (`/sys/devices/system/edac/mc/`) before, between, and after test phases — reporting intermediate results immediately after the memtester phase completes. If a UE occurs during a pmemtester run:

1. The kernel's MCE handler fires and may kill one or more memtester processes (SRAR) or poison the page proactively (SRAO/UCNA)
2. pmemtester detects the killed process via its non-zero exit code
3. pmemtester's EDAC after-snapshot shows increased UE counters compared to the before-snapshot
4. Both signals contribute to a FAIL verdict

The EDAC check catches errors that memtester's own exit code might miss — for example, if a UE occurs in memory not currently under test, or if a patrol scrub detects a UE that was poisoned and retired without killing any memtester process.

References: [HWPoison kernel documentation](https://docs.kernel.org/mm/hwpoison.html), [HWPOISON (LWN.net, Andi Kleen, 2009)](https://lwn.net/Articles/348886/), [Machine check recovery when kernel accesses poison (LWN.net, 2015)](https://lwn.net/Articles/671301/), [mm/memory-failure.c (kernel source)](https://github.com/torvalds/linux/blob/master/mm/memory-failure.c), [arch/x86/kernel/cpu/mce/core.c (kernel source)](https://github.com/torvalds/linux/blob/master/arch/x86/kernel/cpu/mce/core.c), [rasdaemon repository](https://github.com/mchehab/rasdaemon).
