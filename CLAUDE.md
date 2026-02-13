# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Repository:** https://github.com/widefox/pmemtester

pmemtester is a parallel wrapper for [memtester](https://pyropus.ca./software/memtester/) written in pure Bash. It runs multiple memtester instances in parallel (one per CPU thread), divides RAM equally among them, and validates results using both memtester exit codes and Linux EDAC hardware error detection.

## Development Methodology

TDD (Test-Driven Development). Write tests before implementation. Target >85% code coverage.

## Commands

```bash
# Run all tests (unit + integration)
make test

# Run only unit tests
make test-unit

# Run only integration tests
make test-integration

# Run a single test file
bats test/unit/math_utils.bats

# Run a single test by name (regex filter)
bats test/unit/math_utils.bats -f "ceiling_div"

# Lint all source files
make lint

# Generate coverage report (requires kcov)
make coverage
# View at: ./coverage/index.html

# Run pmemtester with defaults
./pmemtester

# Run with options
./pmemtester --percent 80 --ram-type total --memtester-dir /usr/bin --iterations 3
```

## Architecture

### Source Layout

```tree
pmemtester                  # Main executable (thin orchestrator)
lib/
├── math_utils.sh           # Integer arithmetic (ceiling_div, percentage_of, safe_multiply)
├── unit_convert.sh         # kB/MB/bytes conversions
├── system_detect.sh        # RAM and thread count from /proc/meminfo and nproc
├── memtester_mgmt.sh       # Find and validate memtester binary
├── memlock.sh              # Kernel memory lock limit checking and configuration
├── edac.sh                 # EDAC message/counter capture and comparison
├── ram_calc.sh             # RAM allocation math (percentage, per-thread division)
├── parallel.sh             # Background memtester launch, PID tracking, wait
├── logging.sh              # Per-thread and master log management
└── cli.sh                  # Argument parsing and validation
```

### Main Execution Flow

`parse_args` → `validate_args` → `find_memtester` → `calculate_test_ram_kb` → `get_thread_count` → `divide_ram_per_thread_mb` → `check_memlock_sufficient` → `init_logs` → (EDAC before) → `run_all_memtesters` → `wait_and_collect` → (EDAC after) → `aggregate_logs` → PASS/FAIL

### Test Infrastructure

- **Framework**: bats-core 1.13.0 with bats-support and bats-assert (git submodules)
- **Mocking**: PATH-prepend mock scripts for external commands (`memtester`, `nproc`, `dmesg`); environment variable overrides for files (`PROC_MEMINFO`, `EDAC_BASE`, `MOCK_ULIMIT_L`); function overrides for builtins (`_read_ulimit_l`)
- **Fixtures**: `test/fixtures/` contains synthetic `/proc/meminfo` files and EDAC sysfs directory trees
- **Coverage**: kcov 38+ with `--include-path=./lib,./pmemtester` (v35 cannot instrument bash `source`d files inside bats subshells; build from [source](https://github.com/SimonKagstrom/kcov) if distro version is too old)

### Bash Integer Arithmetic

Bash has no floating-point. All arithmetic must use integer math with careful attention to:
- **Division order**: Multiply before dividing to preserve precision (e.g., `ram * percent / 100` not `ram / 100 * percent`)
- **Rounding**: Use `(a + b - 1) / b` for ceiling division when needed
- **Overflow**: Bash integers are 64-bit signed; intermediate products of large values (bytes) can overflow — work in kB or MB where appropriate
- **Units**: Track units explicitly (bytes vs kB vs MB) and convert at boundaries
- **`(( i++ ))` pitfall**: When `i=0`, the expression evaluates to 0 (falsy) and returns exit code 1 under `set -e`. Use `i=$(( i + 1 ))` instead.

### Safety Constraints

Default settings must never crash the host:
- 90% default applies to *available* RAM, not total
- Validate memory lock limits before attempting to lock
- Handle edge cases (zero threads, insufficient RAM, missing memtester binary)
- EDAC checking is skipped gracefully when sysfs is unavailable

### External Dependencies

- `memtester` binary (not bundled)
- Linux kernel with EDAC support (optional — gracefully skipped if absent)
- Standard Linux utilities: `nproc`, `dmesg`, `awk`, `find`, `diff`
- Test tools: `bats` (1.13.0+), `kcov` (38+), `shellcheck` (0.10.0+)
