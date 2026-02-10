# pmemtester

A parallel wrapper for [memtester](https://pyropus.ca./software/memtester/) -- the quickest way to stress-test RAM on Linux. Safe to run on any host with default settings.

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

```text
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

## License

GPLv2
