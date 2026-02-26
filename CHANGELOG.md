# Changelog

## v0.4 (2026-02-26)

### New features

- **Decimal `--percent`**: The `--percent` flag now accepts decimal values from 0.001 to 100 (e.g., `--percent 0.1`). Internally uses a "millipercent" integer strategy (0.1% = 100 millipercent) to keep all arithmetic integer-only. Up to 3 decimal places supported.
- **`--size` flag**: Specify an exact total RAM amount to test with a unit suffix: `--size 256M`, `--size 2G`, `--size 1T`, `--size 1024K`. Supports K (KiB), M (MiB), G (GiB), and T (TiB). The total is divided equally among cores, the same as `--percent`. Mutually exclusive with `--percent`.

### New CLI flags

- `--percent N`: Now accepts decimal values (0.001-100, was 1-100)
- `--size SIZE`: Explicit test RAM with unit suffix (K, M, G, T); mutually exclusive with `--percent`

### New functions

- `decimal_to_millipercent()` in `math_utils.sh`: Convert decimal percent string to integer millipercents
- `percentage_of_milli()` in `math_utils.sh`: Integer percentage using millipercents (`value * millipercent / 100000`)
- `parse_size_to_kb()` in `unit_convert.sh`: Parse size string with K/M/G/T suffix to kB
- `calculate_test_ram_kb_milli()` in `ram_calc.sh`: RAM calculation using millipercents

### Refactoring

- `validate_ram_params()` reduced from 3 args to 2 (percent validation moved to `validate_args`)

### Documentation

- Added decimal `--percent` and `--size` flag documentation to README.md, CLAUDE.md
- Updated distro packaging docs to current 2026 releases (RHEL 10, Rocky/Alma 10, Debian 13, SLES 16, Fedora 43)
- Added binary unit explanations (KiB/MiB/GiB/TiB) to help text and README

## v0.3 (2026-02-16)

### New features

- **Decimal `--percent`**: The `--percent` flag now accepts decimal values from 0.001 to 100 (e.g., `--percent 0.1`). Internally uses a "millipercent" integer strategy (0.1% = 100 millipercent) to keep all arithmetic integer-only. Up to 3 decimal places supported.
- **`--size` flag**: Specify an exact total RAM amount to test with a unit suffix: `--size 256M`, `--size 2G`, `--size 1T`, `--size 1024K`. Supports K, M, G, and T (terabytes). The total is divided equally among cores, the same as `--percent`. Mutually exclusive with `--percent`.
- **stressapptest second pass**: Phase 2 runs stressapptest after memtester for randomised bus-contention stress testing. Modes: `auto` (default, runs if binary found and Phase 1 passed), `on` (mandatory), `off` (disabled). Duration defaults to matching the memtester phase wall-clock time (`--stressapptest-seconds 0`).
- **Intermediate EDAC check**: EDAC counters are now compared after Phase 1 (memtester) and printed immediately, giving early hardware error visibility before the stressapptest pass begins. The final verdict still spans both phases.
- **Phase timing output**: Wall-clock timestamps and durations printed at each phase boundary. Phase 2 displays an ETA based on the configured or measured duration.
- **Binary detection messages**: Reports at startup whether memtester and stressapptest binaries were found, with paths.

### New CLI flags

- `--percent N`: Now accepts decimal values (0.001-100, was 1-100)
- `--size SIZE`: Explicit test RAM with unit suffix (K, M, G, T); mutually exclusive with `--percent`
- `--stressapptest MODE`: Control stressapptest pass: `auto` (default), `on`, `off`
- `--stressapptest-seconds N`: Explicit stressapptest duration in seconds (0 = match memtester time)
- `--stressapptest-dir DIR`: Directory containing stressapptest binary (default: `/usr/local/bin`)

### New source files

- `lib/stressapptest_mgmt.sh`: Find, validate, and run stressapptest binary
- `lib/timing.sh`: Timing, status output, phase formatting

### New functions

- `decimal_to_millipercent()` in `math_utils.sh`: Convert decimal percent string to integer millipercents
- `percentage_of_milli()` in `math_utils.sh`: Integer percentage using millipercents (`value * millipercent / 100000`)
- `parse_size_to_kb()` in `unit_convert.sh`: Parse size string with K/M/G suffix to kB
- `calculate_test_ram_kb_milli()` in `ram_calc.sh`: RAM calculation using millipercents

### Refactoring

- `validate_ram_params()` reduced from 3 args to 2 (percent validation moved to `validate_args`)

### Documentation

- Added decimal `--percent` and `--size` flag documentation to README.md, CLAUDE.md
- Added "Decimal percentages" and "Explicit test size" use case sections
- Updated execution flow diagrams to reflect `--size` / millipercent conditional path
- Added millipercent strategy to Bash Integer Arithmetic section in CLAUDE.md
- Added testing philosophy section (probe + hammer + observe)
- Added stressapptest second pass documentation with modes, duration, memory, EDAC, and verdict sections
- Added duration estimation use case (1% timing run)
- Added stressapptest FAIL example output
- Added FAQ throughput estimates section
- Expanded Linux memory testing tools comparison table

### Fixes

- Fixed nonexistent stressapptest `--mem_threads` flag (replaced with auto-detection)
- Fixed README help text to match actual `--help` output
- Fixed Makefile dist target to include FAQ.md and TODO.md
- Fixed CLAUDE.md execution flow (missing `validate_ram_params`)

## v0.2 (2026)

### New features

- **Per-core parallelism**: Switched from per-thread to per-core parallelism using `lscpu` physical core detection, avoiding SMT bandwidth regression
- **EDAC CE/UE classification**: Distinguishes correctable (CE) and uncorrectable (UE) errors
- **`--allow-ce` flag**: Allow correctable EDAC errors; only fail on uncorrectable
- **Coloured output**: PASS/FAIL/WARN with colour (auto/on/off via `--color`)
- **Install-time `MEMTESTER_DIR`**: `make install MEMTESTER_DIR=/usr/bin` patches the default search path for distro packaging

### Documentation

- Added FAQ.md with speed benchmarks, methodology comparisons, and vendor CE thresholds
- Added per-platform speedup tables grounded in STREAM benchmark data
- Added NUMA penalty measurements
- Added "Why EDAC Matters" section
- Added per-thread vs per-core FAQ with CFS/EEVDF scheduler analysis
- Added Linux memory testing tools comparison table
- Added source quality policy to CLAUDE.md

## v0.1 (2026)

Initial release.

- Parallel memtester execution (one instance per CPU core)
- Configurable RAM percentage and measurement basis (available/total/free)
- Automatic kernel memory lock configuration
- EDAC hardware error detection (before/after comparison)
- Per-core logging with aggregated master log
- 100% code coverage (242 lines)
