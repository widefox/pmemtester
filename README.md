# pmemtester

[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A parallel wrapper for [memtester](https://pyropus.ca./software/memtester/) -- the first Linux tool that combines memory stress testing with ECC correctable error detection in a single package. No reboot, no separate monitor daemon.

**Repository:** https://github.com/widefox/pmemtester

## Features

- Runs one memtester instance per CPU thread to saturate the memory bus on any system
- Extra threads may help the memory controller interleave across banks and cover OS scheduling gaps
- Configurable RAM percentage (default 90% of available)
- RAM measurement basis: available (default), total, or free
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
  --allow-ce          Allow correctable EDAC errors (CE); only fail on uncorrectable (UE)
  --color MODE        Coloured output: auto (default), on, off
  --version           Show version
  --help              Show this help message
```

The `--memtester-dir` default may differ on distro-packaged installations (see [Installation](#installation)).

## Why Parallel?

A single memtester thread cannot saturate a modern memory bus -- one thread typically achieves only 15-25% of peak memory bandwidth. Running one instance per CPU thread fills more memory channels simultaneously, reaching ~80% of peak bandwidth and giving a **4-7x speedup** per socket. On multi-socket systems, pmemtester's per-thread parallelism also keeps memory accesses NUMA-local, adding a further **1.4-2x** benefit over a non-NUMA-aware approach.

See [FAQ.md](FAQ.md#why-does-parallel-memtester-help) for detailed per-platform speedup tables, NUMA penalty measurements, methodology, and [why per-thread is better than per-core](FAQ.md#why-one-memtester-per-thread-instead-of-one-per-core).

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
│   ├── full_run.bats           # End-to-end tests with mocked commands
│   └── install.bats            # Install target tests (MEMTESTER_DIR patching)
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

189 tests (164 unit + 25 integration).

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

On distributions that package memtester to `/usr/bin`, pass `MEMTESTER_DIR` at install time to change the default:

```bash
make install MEMTESTER_DIR=/usr/bin
```

This patches the default so `pmemtester --help` shows `(default: /usr/bin)` and memtester is found without needing `--memtester-dir`. The `--memtester-dir` flag still overrides at runtime.

Distributions that package memtester (all install to `/usr/bin/memtester`):

- Fedora
- Debian / Ubuntu
- Arch Linux
- openSUSE
- Gentoo
- Alpine Linux

## Requirements

- **memtester** binary (not bundled) -- [pyropus.ca](https://pyropus.ca./software/memtester/)
- Linux kernel 3.14+ (for `MemAvailable` in `/proc/meminfo`; older kernels require `--ram-type free` or `--ram-type total`)
- `nproc` (from coreutils)
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
