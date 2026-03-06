# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Repository:** https://github.com/widefox/pmemtester

pmemtester is a parallel wrapper for [memtester](https://pyropus.ca./software/memtester/) written in pure Bash. It runs multiple memtester instances in parallel (one per physical CPU core), divides RAM equally among them, and validates results using both memtester exit codes and Linux EDAC hardware error detection.

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

# Run smoke tests (real binaries, needs memtester installed)
make test-smoke

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

# Run with decimal percent (0.001-100) for quick smoke tests
./pmemtester --percent 0.1

# Run with explicit size (K/M/G/T suffix required; mutually exclusive with --percent)
./pmemtester --size 256M

# Run with stressapptest forced on for 60 seconds
./pmemtester --percent 80 --stressapptest on --stressapptest-seconds 60

# Disable time estimation calibration
./pmemtester --percent 80 --estimate off

# Constrain testing to NUMA node 0 (requires numactl)
./pmemtester --numa-node 0

# Pin each memtester to a specific physical CPU core
./pmemtester --pin

# NUMA + pinning combined
./pmemtester --numa-node 0 --pin
```

## Version Bump Checklist

When bumping the version, update **all** of these locations:

| File | Location | Example |
|------|----------|---------|
| `pmemtester:11` | `pmemtester_version="X.Y"` | Runtime version string |
| `pmemtester:3` | `# Version: X.Y` | Header comment |
| `Makefile:2` | `VERSION := X.Y` | `make dist` / `make install` |
| `README.md` Usage block | `Usage: pmemtester X.Y [OPTIONS]` | Help text example |
| `README.md` tool comparison | `Yes (vX.Y, 20XX)` | Linux Memory Testing Tools table |
| `README.md` Testing section | `N tests (N unit + N integration + N smoke)` | Test count (run `make test` to get current numbers) |
| `CHANGELOG.md` | New `## vX.Y` section at top | Release notes |
| `test/unit/cli.bats` | `pmemtester_version="X.Y"` in `--version` test | Test expectation |

## Architecture

### Source Layout

```tree
/usr/local/bin/                 # Default search path (override with --memtester-dir / --stressapptest-dir)
├── memtester                   # External: required (not bundled)
└── stressapptest               # External: optional (not bundled)

pmemtester                      # Main executable (thin orchestrator)
lib/
├── cli.sh                      # Argument parsing and validation
├── color.sh                    # Coloured terminal output (PASS/FAIL/WARN)
├── edac.sh                     # EDAC message/counter capture and comparison
├── estimate.sh                 # Time estimation (calibration, duration scaling, ETA display)
├── logging.sh                  # Per-thread and master log management
├── math_utils.sh               # Integer arithmetic (ceiling_div, percentage_of, decimal_to_millipercent)
├── memlock.sh                  # Kernel memory lock limit checking and configuration
├── memtester_mgmt.sh           # Find and validate memtester binary
├── parallel.sh                 # Background memtester launch, PID tracking, wait, CPU pinning
├── ram_calc.sh                 # RAM allocation math (percentage, millipercent, per-core division)
├── stressapptest_mgmt.sh       # Find, validate, and run stressapptest binary
├── system_detect.sh            # RAM, core count, NUMA topology, physical CPU mapping
├── timing.sh                   # Timing, status output, phase formatting
└── unit_convert.sh             # kB/MB/bytes conversions, parse_size_to_kb (K/M/G/T)
```

### Main Execution Flow

`parse_args` → `validate_args` → `color_init` → `find_memtester` → (resolve stressapptest) → (if `--size`: `parse_size_to_kb` | else: `decimal_to_millipercent` → `calculate_test_ram_kb_milli`) → `get_core_count` → (if `--numa-node N`: `get_node_core_count`, error on CPU-less nodes) → (if `--threads T`: override core_count, warn if T > node cores) → (if `--pin`: `get_physical_cpu_list` → populate `CPU_LIST`) → `divide_ram_per_core_mb` → `validate_ram_params` → `check_memlock_sufficient` → `init_logs` → (report binary detection, NUMA/pin info) → (adaptive calibration: `get_l3_cache_kb` → `run_calibration` → `estimate_duration` → `print_estimate`) → (EDAC before) → Phase 1: `run_all_memtesters` (with per-thread `taskset`/`numactl` wrapping) → `wait_and_collect` → (EDAC mid: intermediate check) → Phase 2: (conditional `run_stressapptest` with `taskset`/`numactl` wrapping) → (EDAC after: final check spanning both phases) → `aggregate_logs` → PASS/FAIL

### Test Infrastructure

- **Framework**: bats-core 1.13.0 with bats-support and bats-assert (git submodules)
- **Mocking**: PATH-prepend mock scripts for external commands (`memtester`, `lscpu`, `nproc`, `dmesg`, `numactl`, `taskset`); environment variable overrides for files (`PROC_MEMINFO`, `EDAC_BASE`, `MOCK_ULIMIT_L`, `SYS_NODE_BASE`); function overrides for builtins (`_read_ulimit_l`)
- **Fixtures**: `test/fixtures/` contains synthetic `/proc/meminfo` files, EDAC sysfs directory trees, and NUMA sysfs node directories
- **Smoke tests**: `test/smoke/smoke_test.bats` runs against real binaries with `--percent 1`; skips when binaries are absent. Separate `make test-smoke` target keeps them out of the fast mocked suite.
- **Coverage**: kcov 38+ with `--include-path=./lib,./pmemtester` (v35 cannot instrument bash `source`d files inside bats subshells; build from [source](https://github.com/SimonKagstrom/kcov) if distro version is too old)

### Bash Integer Arithmetic

Bash has no floating-point. All arithmetic must use integer math with careful attention to:
- **Division order**: Multiply before dividing to preserve precision (e.g., `ram * percent / 100` not `ram / 100 * percent`)
- **Rounding**: Use `(a + b - 1) / b` for ceiling division when needed
- **Overflow**: Bash integers are 64-bit signed; intermediate products of large values (bytes) can overflow. Work in kB or MB where appropriate
- **Units**: Track units explicitly (bytes vs kB vs MB) and convert at boundaries
- **`(( i++ ))` pitfall**: When `i=0`, the expression evaluates to 0 (falsy) and returns exit code 1 under `set -e`. Use `i=$(( i + 1 ))` instead.
- **Millipercent strategy**: Decimal percent strings (e.g., "0.1", "50.5") are converted to integer millipercents at the CLI boundary (0.1% = 100, 90% = 90000). All downstream arithmetic uses `value * millipercent / 100000`. Up to 3 decimal places supported. Use `10#` prefix when parsing to prevent octal interpretation.

### Safety Constraints

Default settings must never crash the host:
- 90% default applies to *available* RAM, not total
- Validate memory lock limits before attempting to lock
- Handle edge cases (zero cores, insufficient RAM, missing memtester binary)
- EDAC checking is skipped gracefully when sysfs is unavailable

### External Dependencies

- `memtester` binary (not bundled)
- `stressapptest` binary (optional: auto mode silently skips if absent)
- `numactl` (optional: required only when `--numa-node` is used)
- `taskset` (from util-linux; optional: required only when `--pin` is used)
- Linux kernel with EDAC support (optional: gracefully skipped if absent)
- Standard Linux utilities: `lscpu`, `nproc` (fallback), `dmesg`, `awk`, `find`, `diff`
- Test tools: `bats` (1.13.0+), `kcov` (38+), `shellcheck` (0.10.0+)

### Source Quality Policy

References in documentation (FAQ.md, README.md, etc.) must be either **primary sources** (original data, vendor documentation, source code, academic papers) or **quality secondary sources** (peer-reviewed publications, established research blogs like Georg Hager's, official vendor knowledge bases). Avoid forum posts, personal blogs without original data, and other low-reliability sources.
