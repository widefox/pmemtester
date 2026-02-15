# pmemtester

[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A parallel wrapper for [memtester](https://pyropus.ca./software/memtester/), and the first Linux memory stress tester with ECC error detection. The aim is the quickest way to find bad memory with Linux.

**Repository:** https://github.com/widefox/pmemtester

## Features

- Runs one memtester instance per CPU core to saturate the memory bus on any system
- Optional stressapptest second pass for randomised bus-contention stress testing
- Configurable RAM percentage (default 90% of available)
- RAM measurement basis: available (default), total, or free
- Automatic kernel memory lock (`ulimit -l`) configuration
- Linux EDAC hardware error detection (before/after comparison spanning both passes)
- Optionally allow correctable EDAC errors (`--allow-ce`); only fail on uncorrectable (UE)
- Per-core logging with aggregated master log
- Pass/fail verdict combining memtester, stressapptest, and EDAC results

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
  --percent N              Percentage of RAM to test (1-100, default: 90)
  --ram-type TYPE          RAM measurement: available (default), total, free
  --memtester-dir DIR      Directory containing memtester binary (default: /usr/local/bin)
  --log-dir DIR            Directory for log files (default: /tmp/pmemtester.PID)
  --iterations N           Number of memtester iterations (default: 1)
  --allow-ce               Allow correctable EDAC errors (CE); only fail on uncorrectable (UE)
  --color MODE             Coloured output: auto (default), on, off
  --stressapptest MODE     stressapptest pass: auto (default), on, off
  --stressapptest-seconds N  stressapptest duration (0 = use memtester time, default: 0)
  --stressapptest-dir DIR  Directory containing stressapptest binary (default: /usr/local/bin)
  --version                Show version
  --help                   Show this help message
```

The `--memtester-dir` and `--stressapptest-dir` defaults may differ on distro-packaged installations (see [Installation](#installation)).

## Why EDAC Matters

ECC hardware silently corrects single-bit errors before userspace reads the data. No userspace memory stress test — memtester, stressapptest, stress-ng, or any other — can detect a correctable ECC error on its own. A DIMM can be accumulating correctable errors (possibly an indicator of failure; see [FAQ](FAQ.md#do-correctable-errors-predict-future-uncorrectable-errors)) while every test tool reports PASS.

pmemtester is the first Linux memory stress tester to integrate [EDAC](https://docs.kernel.org/driver-api/edac.html) monitoring. It snapshots hardware error counters before and after the test and fails if any new errors appeared during the run. The `--allow-ce` flag lets you distinguish between correctable errors (log and monitor) and uncorrectable errors (fail immediately), matching modern vendor guidance that treats CEs as a monitoring signal rather than an automatic replacement trigger (see [FAQ](FAQ.md#how-many-correctable-errors-before-replacing-a-dimm)).

Without EDAC integration, the only alternative is to run a stress tool in one terminal and rasdaemon or manual `edac-util` checks in another — and hope you remember to compare before and after.

## Why Parallel?

A single memtester thread cannot saturate a modern memory bus -- one thread typically achieves only 15-25% of peak memory bandwidth. Running one instance per CPU core fills more memory channels simultaneously, reaching ~75-90% of peak bandwidth and giving a **4-7x speedup** per socket. On multi-socket systems, pmemtester's per-core parallelism also keeps memory accesses NUMA-local, adding a further **1.4-2x** benefit over a non-NUMA-aware approach.

See [FAQ.md](FAQ.md#why-does-parallel-memtester-help) for detailed per-platform speedup tables, NUMA penalty measurements, methodology, and [why per-core is better than per-thread](FAQ.md#why-one-memtester-per-core-instead-of-one-per-thread).

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
├── system_detect.sh            # RAM and core count detection
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
│   ├── full_run.bats           # End-to-end tests with mocked commands
│   └── install.bats            # Install target tests (MEMTESTER_DIR/STRESSAPPTEST_DIR patching)
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
[2026-02-10 14:30:01] [INFO] Starting pmemtester: 3584MB x 4 cores
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
[2026-02-10 14:30:01] [INFO] Starting pmemtester: 3072MB x 8 cores
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
[2026-02-10 15:00:01] [INFO] Starting pmemtester: 3584MB x 4 cores
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
[2026-02-10 16:00:01] [INFO] Starting pmemtester: 3584MB x 4 cores
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
    --> get_core_count --> divide_ram_per_core_mb --> check_memlock_sufficient
    --> init_logs --> [EDAC before] --> run_all_memtesters --> wait_and_collect
    --> [EDAC after] --> aggregate_logs --> PASS/FAIL
```

## Testing

194 tests (167 unit + 27 integration).

```bash
make test              # Run all tests (unit + integration)
make test-unit         # Unit tests only
make test-integration  # Integration tests only
make coverage          # Generate kcov coverage report
make lint              # Run shellcheck
```

Test infrastructure: [bats-core](https://github.com/bats-core/bats-core) 1.13.0 with bats-support/bats-assert. Coverage via [kcov](https://simonkagstrom.github.io/kcov/) v38+ (older versions cannot instrument bash `source`d files inside bats subshells; if your distro ships an older version such as Fedora's v35, build from [source](https://github.com/SimonKagstrom/kcov)).

## Installation

```bash
make install           # Install to /usr/local/bin (requires sudo)
make install PREFIX=/opt/pmemtester   # Custom prefix
make uninstall         # Remove installed files
make dist              # Create .tgz distribution archive
```

### Distro packaging

On distributions that package memtester or stressapptest to `/usr/bin`, pass the directory at install time to change the default:

```bash
make install MEMTESTER_DIR=/usr/bin
make install STRESSAPPTEST_DIR=/usr/bin
make install MEMTESTER_DIR=/usr/bin STRESSAPPTEST_DIR=/usr/bin   # both
```

This patches the defaults so `pmemtester --help` shows the correct paths and binaries are found without needing `--memtester-dir` or `--stressapptest-dir`. The runtime flags still override at runtime.

Distributions that package memtester (all install to `/usr/bin/memtester`):

- Fedora
- Debian / Ubuntu
- Arch Linux
- openSUSE
- Gentoo
- Alpine Linux

## Requirements

- **memtester** binary (not bundled) -- [pyropus.ca](https://pyropus.ca./software/memtester/)
- **stressapptest** binary (optional -- auto mode silently skips if absent) -- [github.com/stressapptest](https://github.com/stressapptest/stressapptest)
- Linux kernel 3.14+ (for `MemAvailable` in `/proc/meminfo`; older kernels require `--ram-type free` or `--ram-type total`)
- `lscpu` (from util-linux; falls back to `nproc` from coreutils)
- EDAC support (optional -- gracefully skipped if absent)
- For testing: bats 1.13.0+, kcov 38+ (v35 cannot trace `source`d files in bats; build from [source](https://github.com/SimonKagstrom/kcov) if needed), shellcheck 0.10.0+

## EDAC Compatibility

pmemtester checks Linux [EDAC](https://docs.kernel.org/driver-api/edac.html) (Error Detection and Correction) hardware error counters before and after the memory test when available. **ECC RAM is required** for EDAC to report anything -- on non-ECC systems the EDAC driver detects no ECC capability and does not load, so pmemtester gracefully skips the check.

Nearly all major distros enable `CONFIG_EDAC=y` with hardware drivers as modules, and EDAC is available on most Linux-supported architectures (x86, ARM64, PowerPC, RISC-V, LoongArch). See [FAQ.md](FAQ.md#which-linux-distros-support-edac) for per-distro and per-architecture compatibility tables.

**Known considerations:**
- **EDAC counters are system-wide.** pmemtester compares EDAC counters before and after the test across all memory controllers, not just the memory regions being tested. Since you are always testing a subset of total RAM (e.g. default 90% of available RAM), any EDAC error that occurs during the test — whether from untested memory, other workloads, OS activity, or other NUMA nodes — will cause a FAIL. There is currently no correlation between EDAC errors and the specific memory regions under test.
- On ACPI/APEI systems, the GHES firmware-first driver may take priority over OS-level EDAC drivers
- Real-time kernels and some server vendors (HPE ProLiant) recommend disabling EDAC in favor of firmware-based error reporting (iLO/iDRAC)
- If EDAC sysfs is absent (`/sys/devices/system/edac/mc/` empty or missing), pmemtester skips EDAC checks and reports results based on memtester exit codes alone

## Roadmap

See [TODO.md](TODO.md) for planned improvements including EDAC region correlation, multi-architecture validation, NUMA locality, heterogeneous core handling, and customisable thread count.

## Linux Memory Testing Tools Comparison

| Tool | Environment | Parallel | ECC CE Detection | Active | License |
|------|-------------|----------|-----------------|--------|---------|
| **pmemtester** | Userspace | Yes | **Yes** (EDAC before/after) | Yes (v0.3, 2026) | GPL-2.0 |
| memtester | Userspace | No | No | Yes (v4.7.1, 2024) | GPL-2.0 |
| stressapptest | Userspace | Yes | No | Low (v1.0.11, 2023) | Apache-2.0 |
| stress-ng | Userspace | Yes | No | Yes (monthly releases) | GPL-2.0 |
| DimmReaper | Userspace | Yes | No | Low (2024) | GPL-2.0 |
| ocp-diag-memtester | Userspace (Python) | No | No | Low (2023) | Apache-2.0 |
| mprime/Prime95 | Userspace | Yes | No | Yes | Freeware |

### EDAC Monitoring Utilities

| Tool | Environment | Parallel | ECC CE Detection | Active | License |
|------|-------------|----------|-----------------|--------|---------|
| rasdaemon | Userspace daemon | N/A (monitor) | **Yes** (EDAC tracing) | Yes (v0.8.4, 2025) | GPL-2.0 |
| edac-utils | Userspace | N/A (reporting) | **Yes** (EDAC sysfs) | No (dormant since 2008) | GPL-2.0 |

### Standalone Boot Tools

| Tool | Environment | Parallel | ECC CE Detection | Active | License |
|------|-------------|----------|-----------------|--------|---------|
| MemTest86 (PassMark) | Standalone boot | Yes | **Yes** (direct HW polling; per-DIMM in Pro edition) | Yes (v11.6, 2026) | Proprietary freeware |
| Memtest86+ | Standalone boot | Yes | **Partial** (AMD Ryzen only, manual recompile) | Yes (v8.0, 2024) | GPL-2.0 |

Both tools boot without an OS and run all memory tests at the highest available privilege level. Real mode is only used transiently during legacy BIOS boot (a few instructions before switching modes) and during per-core SMP wakeup; no testing occurs in real mode.

| Tool | Architecture | Testing CPU Mode | Privilege Level |
|------|-------------|-----------------|-----------------|
| MemTest86 (PassMark) | x86-64 | 64-bit long mode | Ring 0 |
| MemTest86 (PassMark) | ARM64 | AArch64 | EL1 or EL2 (firmware-dependent) |
| Memtest86+ | x86-64 (UEFI) | 64-bit long mode | Ring 0 |
| Memtest86+ | x86-64 (legacy BIOS) | Long mode (or 32-bit protected + PAE on 32-bit CPUs) | Ring 0 |
| Memtest86+ | LoongArch64 | 64-bit paging mode | PLV0 |

No userspace memory stress test tool detects ECC correctable errors on its own -- ECC hardware silently corrects single-bit errors before userspace reads the data. pmemtester is the first tool that combines pattern-based stress testing with EDAC error detection. The alternative is to run a stress tool while rasdaemon monitors EDAC counters separately.

### Userspace vs bare-metal testing

memtester and all other userspace tools (stressapptest, stress-ng, pmemtester) run inside the operating system and test virtual addresses. The OS controls which physical RAM pages back those addresses. This means userspace tools cannot test memory occupied by the kernel, drivers, or other processes — if a bad cell happens to hold kernel data, a userspace tester will never touch it. Bare-metal tools like MemTest86 boot without an OS and have direct access to nearly all physical memory, making them the gold standard for hardware validation.

However, userspace testing has a complementary strength: it runs while the full system is active (GPU, network, disk I/O), creating a hotter, electrically noisier environment that can reveal marginal RAM that passes bare-metal tests at idle. memtester also relies on `mlock` to prevent the OS from swapping test patterns to disk — if mlock fails, the test may be exercising swap rather than RAM. pmemtester validates mlock limits before starting (`check_memlock_sufficient`) and its EDAC integration catches hardware errors that userspace reads cannot see, partially compensating for the virtual address limitation.

References: [memtester homepage](https://pyropus.ca./software/memtester/), [MemTest86 technical overview](https://www.memtest86.com/tech_individual-test-descr.html), [Linux mlock(2) man page](https://linux.die.net/man/2/mlock).

### Testing philosophy: microscope, hammer, chaos monkey

Each major userspace tool takes a fundamentally different approach to finding memory problems:

| Tool | Philosophy | Approach | Finds |
|------|-----------|----------|-------|
| **memtester** | Microscope | Sequential deterministic patterns (stuck address, walking ones/zeros, bit flip, checkerboard) — checks every address methodically | Dead cells, stuck bits, coupling faults, address decoder faults |
| **stressapptest** | Hammer | Multi-threaded randomised block copies with CRC verification — floods the memory controller with concurrent traffic | Weak signals, timing margin failures, bus contention errors, power supply instability |
| **stress-ng** | Chaos monkey | Multi-modal stressors (galpat, rowhammer, bit flip, paging storms) — stresses the entire memory subsystem including virtual memory and cache coherency | System-level memory management bugs, page table corruption, kernel interaction failures |

**memtester** is single-threaded and predictable. It creates very little electrical noise, so a DIMM that is "mostly fine" but fails only when hot or when voltage drops slightly may pass. Google developed stressapptest specifically because deterministic tools were passing hardware that failed in production ([Google Open Source Blog](https://opensource.googleblog.com/2009/10/fighting-bad-memories-stressful.html)).

**stressapptest** spawns threads equal to the number of CPU cores, racing them against each other with randomised copies, bit inversions, and disk-to-RAM transfers. This maximises bus contention and creates ground bounce and signal interference, revealing electrically weak RAM. It is widely considered the best userspace tool for finding intermittent stability errors on DDR4/DDR5 systems.

**stress-ng** can mimic memtester's patterns but adds OS-level chaos: forcing paging storms, exercising rowhammer patterns, and thrashing the virtual memory manager. It finds bugs where the memory subsystem interacts poorly with the kernel.

pmemtester wraps memtester's thorough pattern testing with per-core parallelism (closing the bandwidth gap with stressapptest) and EDAC monitoring (detecting hardware errors invisible to all three tools above).

See [FAQ.md](FAQ.md#what-does-pmemtester-test-that-stressapptest-doesnt-and-vice-versa) for detailed algorithmic comparisons.

References: [memtester source: tests.c](https://github.com/jnavila/memtester/blob/master/tests.c), [stressapptest repository](https://github.com/stressapptest/stressapptest), [Google: Fighting Bad Memories](https://opensource.googleblog.com/2009/10/fighting-bad-memories-stressful.html), [stress-ng homepage](https://github.com/ColinIanKing/stress-ng), [stress-ng vm methods](https://wiki.ubuntu.com/Kernel/Reference/stress-ng).

## FAQ

See [FAQ.md](FAQ.md) for frequently asked questions, including algorithmic comparisons of memtester/stressapptest/stress-ng, speed benchmarks, hard vs soft errors, CE thresholds by vendor, CE-to-UE predictive research, and cache behaviour.

## See Also

- [ocp-diag-memtester](https://github.com/opencomputeproject/ocp-diag-memtester) -- OCP diagnostic wrapper for memtester

## License

[GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
