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

A single memtester thread cannot saturate a modern memory bus. CPU cores have a limited number of outstanding memory requests (Line Fill Buffers), so one thread typically achieves only 15-25% of peak memory bandwidth on a server CPU ([STREAM benchmark data](https://www.karlrupp.net/2015/02/stream-benchmark-results-on-intel-xeon-and-xeon-phi/)). Running multiple instances in parallel fills more memory channels simultaneously and reaches ~80% of peak bandwidth with around 10 threads on current x86 hardware -- roughly a **4-7x speedup** over a single thread on one socket.

On multi-socket systems, pmemtester's per-thread parallelism also keeps memory accesses NUMA-local. A single memtester process testing both sockets would pay a cross-socket bandwidth penalty (see below), while pmemtester's many independent instances naturally access memory local to the core they run on.

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

## Why one memtester per thread instead of one per core?

pmemtester launches one memtester instance per hardware thread (from `nproc`), not per physical core. On a 16-core/32-thread system, that means 32 instances. This is deliberate -- it avoids a scheduler problem that would make per-core launches slower and less predictable.

### The scheduler problem with fewer processes than threads

If you launched 16 processes on 32 logical CPUs, the Linux scheduler would need to distribute them evenly -- but load balancing is periodic, not instantaneous. This applies to both CFS (< 6.6) and the EEVDF scheduler that replaced it in Linux 6.6:

- **Busy balancing** (tick-based): Runs every ~4ms on busy CPUs, checks if a sibling is idle
- **Idle balancing** (pull-based): When a CPU goes idle, it pulls work from a busy CPU
- **Newidle balancing**: Between a task sleeping and the next tick, the CPU can steal work

These balancing mechanisms are part of the kernel's scheduling domain infrastructure, shared by both CFS and EEVDF. EEVDF changes how the scheduler picks which task to run next on a given CPU (using virtual deadlines instead of virtual runtime), but the cross-CPU load balancing that decides *where* tasks run uses the same periodic rebalancing logic. The transient imbalance problem described below is identical under both schedulers.

At any given moment, the scheduler might place two memtester processes on sibling SMT threads of the same physical core while leaving another core entirely idle. Idle balancing fixes this within ~1-4ms, but during that window the two co-scheduled processes share:

- **L1/L2 cache** (contention, more evictions)
- **Memory pipeline** (load/store buffers, fill buffers)
- **TLB entries** (reduced effective TLB for each process)

For a memory-bound workload like memtester, co-scheduling on SMT siblings gives ~40-60% of single-thread throughput per process. Meanwhile the idle core contributes nothing.

### Per-thread default eliminates the problem

With 32 processes on 32 logical CPUs, every run queue has work. There is no idle CPU, no migration question, no transient imbalance. The scheduler places one process per logical CPU and leaves them there. Two sibling SMT threads on the same core each get ~50-60% of the core's memory bandwidth, but both are working, so the core's total memory bandwidth is fully utilised (~95-100%).

### Quantifying the difference

On a 16-core/32-thread system testing 28 GB (90% of 32 GB):

| Default | Processes | RAM/process | Scheduler issue | Effective bandwidth |
|---------|-----------|-------------|-----------------|---------------------|
| Per-thread (current) | 32 | 875 MB | None -- all CPUs busy | ~95-100% of peak |
| Per-core | 16 | 1750 MB | Transient co-scheduling | ~85-95% of peak |

The per-core approach wastes ~5-15% of memory bandwidth during transient imbalances. Over a multi-minute memtester run, these transient periods add up to a measurable slowdown.

### Don't SMT threads share bandwidth anyway?

Two threads on the same core get ~1.0-1.15x the bandwidth of one thread, not 2x. But the advantage of per-thread is not extra bandwidth per core -- it is:

1. **Guaranteed scheduling fairness**: No core sits idle while a sibling is double-loaded
2. **Memory controller interleaving**: 32 smaller allocations (875 MB each) exercise more diverse physical address ranges than 16 larger ones (1750 MB each), potentially hitting more memory controller channels
3. **Simplicity**: `nproc` matches the kernel's view of schedulable entities -- no SMT detection logic needed

### When per-core would be better

Per-core only wins if you pin each process to a specific core with `taskset` (eliminating scheduler indeterminism), the system has no SMT (where `nproc` already gives per-core), or you are testing with extremely small RAM per thread where process overhead dominates.

For explicit control, the planned `--threads N` option (see [TODO.md](TODO.md#cores-vs-threads)) will allow users to override the default.

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

## Why not drop caches before running?

`MemAvailable` in `/proc/meminfo` already accounts for reclaimable page cache and reclaimable slab (dentries/inodes) -- the kernel will evict these as needed when memtester allocates memory. Dropping caches (`echo 3 > /proc/sys/vm/drop_caches`) before running is unnecessary because the kernel reclaims clean cache pages on demand under allocation pressure. `MemAvailable` is deliberately conservative (it subtracts low watermarks and counts only half of reclaimable slab to account for fragmentation), so the actual reclaimable memory is slightly higher than the estimate -- but this works in pmemtester's favour, not against it. The practical outcome is the same whether you drop caches or not. Note that `drop_caches` only releases *clean* pages -- dirty pages (modified but not yet written to disk) are kept. If you did want to maximise free memory manually, you would need to run `sync` first to flush dirty pages to disk, converting them to clean pages that `drop_caches` can then release. But again, the kernel handles all of this automatically under allocation pressure, so neither `sync` nor `drop_caches` is needed before running pmemtester.
