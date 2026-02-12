# pmemtester

[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A parallel wrapper for [memtester](https://pyropus.ca./software/memtester/) -- the first Linux tool that combines memory stress testing with ECC correctable error detection in a single package. No reboot, no separate monitor daemon.

**Repository:** https://github.com/widefox/pmemtester

## Features

- Runs one memtester instance per CPU thread for maximum memory coverage
- Configurable RAM percentage (default 90% of available)
- RAM type selection: available (default), total, or free
- Automatic kernel memory lock (`ulimit -l`) configuration
- Linux EDAC hardware error detection (before/after comparison)
- Per-thread logging with aggregated master log
- Pass/fail verdict combining memtester results and EDAC checks

## Quick Start

```bash
# Install memtester first (not bundled)
# e.g., apt install memtester  OR  build from source

# Install pmemtester
sudo make install

# Run with safe defaults (90% available RAM, 1 iteration)
sudo pmemtester

# Run with custom settings
sudo pmemtester --percent 80 --ram-type total --iterations 3
```

## Usage

```console
$ pmemtester --help
Usage: pmemtester [OPTIONS]

Options:
  --percent N         Percentage of RAM to test (1-100, default: 90)
  --ram-type TYPE     RAM measurement: available (default), total, free
  --memtester-dir DIR Directory containing memtester binary (default: /usr/local/bin)
  --log-dir DIR       Directory for log files (default: /tmp/pmemtester.PID)
  --iterations N      Number of memtester iterations (default: 1)
  --version           Show version
  --help              Show this help message
```

## Why Parallel?

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

## Use Cases

### Maximum RAM coverage

To test as much RAM as possible, use `--percent 95` with available RAM (the default):

```bash
sudo pmemtester --percent 95
```

Using 100% is not safe -- pmemtester itself, the shell, and the OS kernel need some working memory. The `available` RAM type uses `MemAvailable` from `/proc/meminfo` (present since Linux 3.14), which estimates how much memory can be allocated by new applications without causing swapping. The kernel calculates it roughly as `MemFree + Reclaimable Page Cache + Reclaimable Slab - Watermarks`, accounting for memory that is technically in use but can be reclaimed under pressure. So 95% of available is aggressive but leaves enough headroom (~200-500MB on a typical server) for the OS and pmemtester processes to function without triggering the OOM killer.

| Percent | Risk | Use case |
|---------|------|----------|
| 90% (default) | Safe | Routine testing, production-adjacent hosts |
| 95% | Low risk | Thorough pre-deployment validation |
| 98% | Moderate | Dedicated test hosts with minimal services |
| 100% | OOM likely | Not recommended -- OS needs working memory |

### Single-socket testing on a multi-socket server

On a running multi-socket server, you may want to test one NUMA node at a time to maintain partial availability. pmemtester doesn't currently have built-in NUMA support, but you can use `numactl` to constrain it to a single socket:

```bash
# Test socket 0 only (CPUs and memory bound to NUMA node 0)
sudo numactl --cpunodebind=0 --membind=0 pmemtester --percent 90

# Test socket 1 only
sudo numactl --cpunodebind=1 --membind=1 pmemtester --percent 90
```

This binds both the CPU threads and memory allocation to the specified NUMA node, so only that socket's RAM is tested. The other socket remains fully available for workloads.

**Note:** `--percent 90` in this case applies to the available memory on that NUMA node, not the whole system. Check per-node memory with `numactl --hardware`.

## Source Layout

```tree
pmemtester                      # Main executable (thin orchestrator)
Makefile                        # Build, test, install, dist targets
PROMPT.md                       # Original design specification
CLAUDE.md                       # Developer guide for Claude Code
lib/
├── cli.sh                      # Argument parsing and validation
├── math_utils.sh               # Integer arithmetic utilities
├── unit_convert.sh             # kB/MB/bytes conversions
├── system_detect.sh            # RAM and thread count detection
├── memtester_mgmt.sh           # Find and validate memtester binary
├── memlock.sh                  # Kernel memory lock management
├── edac.sh                     # EDAC message/counter monitoring
├── ram_calc.sh                 # RAM allocation calculations
├── parallel.sh                 # Parallel memtester execution
└── logging.sh                  # Per-thread and master logging
test/
├── unit/                       # Unit tests (one .bats per lib)
│   ├── cli.bats
│   ├── math_utils.bats
│   ├── unit_convert.bats
│   ├── system_detect.bats
│   ├── memtester_mgmt.bats
│   ├── memlock.bats
│   ├── edac.bats
│   ├── ram_calc.bats
│   ├── parallel.bats
│   └── logging.bats
├── integration/
│   └── full_run.bats           # End-to-end tests with mocked commands
├── fixtures/                   # Synthetic /proc/meminfo, EDAC sysfs trees
│   ├── proc_meminfo_normal
│   ├── proc_meminfo_low
│   ├── proc_meminfo_no_available
│   ├── edac_counters_zero/
│   ├── edac_counters_nonzero/
│   ├── edac_messages_clean.txt
│   └── edac_messages_errors.txt
└── test_helper/
    ├── common_setup.bash       # Shared test setup
    ├── mock_helpers.bash       # Mock creation utilities
    ├── bats-support/           # Git submodule
    └── bats-assert/            # Git submodule
```

## Example Log Layout

pmemtester creates a log directory at `/tmp/pmemtester.<PID>/` (or `--log-dir`):

```tree
/tmp/pmemtester.12345/
├── master.log                  # Aggregated log with all thread results
├── thread_0.log                # Per-thread memtester output
├── thread_1.log
├── thread_2.log
├── thread_3.log
├── edac_messages_before.txt    # EDAC dmesg snapshot before test
├── edac_messages_after.txt     # EDAC dmesg snapshot after test
├── edac_counters_before.txt    # EDAC sysfs counters before test
└── edac_counters_after.txt     # EDAC sysfs counters after test
```

### master.log contents

```text
[2026-02-10 14:30:01] [INFO] Starting pmemtester: 3584MB x 4 threads
--- Thread 0 ---
[2026-02-10 14:30:01] [INFO] memtester 3584M started (PID 12346)
[2026-02-10 14:35:22] [INFO] memtester 3584M completed (exit 0)
--- Thread 1 ---
[2026-02-10 14:30:01] [INFO] memtester 3584M started (PID 12347)
[2026-02-10 14:35:19] [INFO] memtester 3584M completed (exit 0)
--- Thread 2 ---
[2026-02-10 14:30:01] [INFO] memtester 3584M started (PID 12348)
[2026-02-10 14:35:20] [INFO] memtester 3584M completed (exit 0)
--- Thread 3 ---
[2026-02-10 14:30:01] [INFO] memtester 3584M started (PID 12349)
[2026-02-10 14:35:21] [INFO] memtester 3584M completed (exit 0)
[2026-02-10 14:35:22] [INFO] PASS: All memtesters passed, no EDAC errors
```

## Example Output: PASS

```console
$ sudo pmemtester --percent 80 --iterations 1
PASS
$ echo $?
0
```

With `--log-dir /tmp/memtest-run`:

```console
$ sudo pmemtester --percent 80 --log-dir /tmp/memtest-run
PASS
$ cat /tmp/memtest-run/master.log
[2026-02-10 14:30:01] [INFO] Starting pmemtester: 3072MB x 8 threads
--- Thread 0 ---
[2026-02-10 14:30:01] [INFO] memtester 3072M completed (exit 0)
--- Thread 1 ---
[2026-02-10 14:30:01] [INFO] memtester 3072M completed (exit 0)
...
[2026-02-10 14:38:45] [INFO] PASS: All memtesters passed, no EDAC errors
```

## Example Output: FAIL (memtester error)

When memtester detects a memory error:

```console
$ sudo pmemtester --percent 90
FAIL
$ echo $?
1
$ cat /tmp/pmemtester.54321/master.log
[2026-02-10 15:00:01] [INFO] Starting pmemtester: 3584MB x 4 threads
--- Thread 0 ---
[2026-02-10 15:00:01] [INFO] memtester 3584M completed (exit 0)
--- Thread 1 ---
[2026-02-10 15:00:01] [INFO] memtester 3584M completed (exit 0)
--- Thread 2 ---
[2026-02-10 15:05:12] [ERROR] memtester 3584M FAILED (exit 1)
--- Thread 3 ---
[2026-02-10 15:00:01] [INFO] memtester 3584M completed (exit 0)
[2026-02-10 15:05:12] [INFO] FAIL: memtester_result=1 edac_result=0
```

## Example Output: FAIL (EDAC errors)

When hardware error counters increase during the test:

```console
$ sudo pmemtester --percent 90
FAIL
$ echo $?
1
$ cat /tmp/pmemtester.54322/master.log
[2026-02-10 16:00:01] [INFO] Starting pmemtester: 3584MB x 4 threads
--- Thread 0 ---
[2026-02-10 16:00:01] [INFO] memtester 3584M completed (exit 0)
--- Thread 1 ---
[2026-02-10 16:00:01] [INFO] memtester 3584M completed (exit 0)
--- Thread 2 ---
[2026-02-10 16:00:01] [INFO] memtester 3584M completed (exit 0)
--- Thread 3 ---
[2026-02-10 16:00:01] [INFO] memtester 3584M completed (exit 0)
[2026-02-10 16:05:30] [INFO] FAIL: memtester_result=0 edac_result=1
$ diff /tmp/pmemtester.54322/edac_counters_before.txt /tmp/pmemtester.54322/edac_counters_after.txt
3c3
< mc0/csrow0/ce_count:0
---
> mc0/csrow0/ce_count:3
```

In this case all memtester processes passed, but 3 correctable ECC errors (ce_count) were detected by EDAC hardware monitoring during the run.

## Execution Flow

```workflow
parse_args --> validate_args --> find_memtester --> calculate_test_ram_kb
    --> get_thread_count --> divide_ram_per_thread_mb --> check_memlock_sufficient
    --> init_logs --> [EDAC before] --> run_all_memtesters --> wait_and_collect
    --> [EDAC after] --> aggregate_logs --> PASS/FAIL
```

## Testing

131 tests, 100% code coverage (242/242 lines).

```bash
make test              # Run all tests (unit + integration)
make test-unit         # Unit tests only
make test-integration  # Integration tests only
make coverage          # Generate kcov coverage report
make lint              # Run shellcheck
```

Test infrastructure: [bats-core](https://github.com/bats-core/bats-core) 1.13.0 with bats-support/bats-assert. Coverage via [kcov](https://simonkagstrom.github.io/kcov/).

## Installation

```bash
make install           # Install to /usr/local/bin (requires sudo)
make install PREFIX=/opt/pmemtester   # Custom prefix
make uninstall         # Remove installed files
make dist              # Create .tgz distribution archive
```

## Requirements

- **memtester** binary (not bundled) -- [pyropus.ca](https://pyropus.ca./software/memtester/)
- Linux kernel 3.14+ (for `MemAvailable` in `/proc/meminfo`; older kernels require `--ram-type free` or `--ram-type total`)
- `nproc` (from coreutils)
- EDAC support (optional -- gracefully skipped if absent)
- For testing: bats 1.13.0+, kcov 35+, shellcheck 0.10.0+

## EDAC Compatibility

pmemtester optionally checks Linux [EDAC](https://docs.kernel.org/driver-api/edac.html) (Error Detection and Correction) hardware error counters before and after the memory test. **ECC RAM is required** for EDAC to report anything -- on non-ECC systems the EDAC driver detects no ECC capability and does not load, so pmemtester gracefully skips the check.

Nearly all major distros enable `CONFIG_EDAC=y` with hardware drivers as modules, and EDAC is available on most Linux-supported architectures (x86, ARM64, PowerPC, RISC-V, LoongArch). See [FAQ.md](FAQ.md#which-linux-distros-support-edac) for per-distro and per-architecture compatibility tables.

**Known considerations:**
- **EDAC counters are system-wide.** pmemtester compares EDAC counters before and after the test across all memory controllers, not just the memory regions being tested. Since you are always testing a subset of total RAM (e.g. default 90% of available RAM), any EDAC error that occurs during the test — whether from untested memory, other workloads, OS activity, or other NUMA nodes — will cause a FAIL. There is currently no correlation between EDAC errors and the specific memory regions under test.
- On ACPI/APEI systems, the GHES firmware-first driver may take priority over OS-level EDAC drivers
- Real-time kernels and some server vendors (HPE ProLiant) recommend disabling EDAC in favor of firmware-based error reporting (iLO/iDRAC)
- If EDAC sysfs is absent (`/sys/devices/system/edac/mc/` empty or missing), pmemtester skips EDAC checks and reports results based on memtester exit codes alone

## Roadmap

See [TODO.md](TODO.md) for planned improvements including EDAC error classification (CE vs UE), multi-architecture validation, NUMA locality, heterogeneous core handling, and core vs thread considerations.

## Linux Memory Testing Tools Comparison

| Tool | Environment | Parallel | ECC CE Detection | Active | License |
|------|-------------|----------|-----------------|--------|---------|
| **pmemtester** | Userspace (Bash) | Yes (1 per thread) | **Yes** (EDAC before/after) | Yes (v0.1, 2026) | GPL-2.0 |
| memtester | Userspace | No | No | Yes (v4.7.1, 2024) | GPL-2.0 |
| MemTest86 (PassMark) | Standalone boot | Yes | **Yes** (direct HW polling, per-DIMM) | Yes (v11.6, 2026) | Proprietary freeware |
| Memtest86+ | Standalone boot | Yes | **Partial** (AMD Ryzen only, manual recompile) | Yes (v8.0, 2025) | GPL-2.0 |
| stressapptest | Userspace | Yes | No | Low (v1.0.11, 2023) | Apache-2.0 |
| stress-ng | Userspace | Yes | No | Yes (monthly releases) | GPL-2.0 |
| DimmReaper | Userspace | Yes | No | Low (2024) | GPL-2.0 |
| ocp-diag-memtester | Userspace (Python) | No | No | Low (2023) | Apache-2.0 |
| mprime/Prime95 | Userspace | Yes | No | Yes | Freeware |
| rasdaemon | Userspace daemon | N/A (monitor) | **Yes** (EDAC tracing) | Yes (v0.8.4, 2025) | GPL-2.0 |
| edac-utils | Userspace | N/A (reporting) | **Yes** (EDAC sysfs) | No (dormant since 2008) | GPL-2.0 |

No userspace memory stress test tool detects ECC correctable errors on its own -- ECC hardware silently corrects single-bit errors before userspace reads the data. pmemtester is the first tool that combines pattern-based stress testing with EDAC error detection in a single package. The alternative is to run a stress tool while rasdaemon monitors EDAC counters separately.

## FAQ

See [FAQ.md](FAQ.md) for frequently asked questions, including speed comparisons with stressapptest, testing methodology differences, hard vs soft errors, CE thresholds by vendor, CE-to-UE predictive research, and cache behaviour.

## See Also

- [ocp-diag-memtester](https://github.com/opencomputeproject/ocp-diag-memtester) -- OCP diagnostic wrapper for memtester

## License

[GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
