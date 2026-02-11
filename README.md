# pmemtester

[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A parallel wrapper for [memtester](https://pyropus.ca./software/memtester/) -- the quickest way to stress-test RAM on Linux. Safe to run on any host with default settings.

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

A single memtester thread cannot saturate a modern memory bus. CPU cores have a limited number of outstanding memory requests (Line Fill Buffers), so one thread typically achieves only 10-25% of peak memory bandwidth on a server CPU. Running multiple instances in parallel fills more memory channels simultaneously and, on multi-socket systems, keeps all memory accesses NUMA-local (avoiding the 30-50% bandwidth penalty of cross-socket access).

| System | Channels | Expected Speedup |
|--------|----------|------------------|
| Desktop (dual-channel DDR5) | 2 | ~2-3x |
| Workstation (quad-channel DDR5) | 4 | ~4-6x |
| 1-socket server (8-channel DDR4/5) | 8 | ~6-10x |
| 2-socket server (16 channels total) | 16 | ~8-16x |

The speedup is roughly proportional to the number of memory channels, since that determines how much bandwidth is available beyond what one thread can use. On dual-socket servers the NUMA locality benefit compounds with the channel parallelism -- a single process testing both sockets pays a ~30-50% bandwidth penalty on the remote socket's memory, while per-socket instances avoid this entirely. Beyond ~1-2 threads per memory channel, additional threads provide no further bandwidth benefit.

## Use Cases

### Maximum RAM coverage

To test as much RAM as possible, use `--percent 95` with available RAM (the default):

```bash
sudo pmemtester --percent 95
```

Using 100% is not safe -- pmemtester itself, the shell, and the OS kernel need some working memory. The `available` RAM type (from `/proc/meminfo` `MemAvailable`) already excludes memory used by the kernel and page cache, so 95% of available is aggressive but leaves enough headroom (~200-500MB on a typical server) for the OS and pmemtester processes to function without triggering the OOM killer.

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
- Linux kernel with `/proc/meminfo` and `nproc`
- EDAC support (optional -- gracefully skipped if absent)
- For testing: bats 1.13.0+, kcov 35+, shellcheck 0.10.0+

## EDAC Compatibility

pmemtester optionally checks Linux [EDAC](https://docs.kernel.org/driver-api/edac.html) (Error Detection and Correction) hardware error counters before and after the memory test. **ECC RAM is required** for EDAC to report anything -- on non-ECC systems the EDAC driver detects no ECC capability and does not load, so pmemtester gracefully skips the check.

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

### Architecture Support

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

**Known considerations:**
- **EDAC counters are system-wide.** pmemtester compares EDAC counters before and after the test across all memory controllers, not just the region being tested. If you are testing a subset of RAM (e.g., socket 1 via `numactl --membind=1`), an EDAC error triggered by a workload on socket 0 will still cause a FAIL. There is currently no correlation between EDAC errors and the specific memory regions under test.
- On ACPI/APEI systems, the GHES firmware-first driver may take priority over OS-level EDAC drivers
- Real-time kernels and some server vendors (HPE ProLiant) recommend disabling EDAC in favor of firmware-based error reporting (iLO/iDRAC)
- If EDAC sysfs is absent (`/sys/devices/system/edac/mc/` empty or missing), pmemtester skips EDAC checks and reports results based on memtester exit codes alone

## Roadmap

See [TODO.md](TODO.md) for planned improvements including EDAC error classification (CE vs UE), multi-architecture validation, NUMA locality, heterogeneous core handling, and core vs thread considerations.

## License

[GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
