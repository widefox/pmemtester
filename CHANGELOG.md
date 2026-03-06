# Changelog

## v0.7 (2026-03-06)

### New features

- **`--numa-node N`**: Constrain testing to a specific NUMA node. Wraps each memtester instance and stressapptest with `numactl --cpunodebind=N --membind=N`. Auto-detects the node's physical core count and adjusts thread count accordingly. CPU-less NUMA nodes (e.g., HBM) produce an error with a `numactl --membind=N` workaround suggestion. Requires `numactl` to be installed.
- **`--pin`**: Pin each memtester instance to a specific physical CPU core via `taskset -c <cpu_id>`. Uses `lscpu -b -p=Socket,Core,CPU,Node` to map physical cores to the lowest logical CPU ID per unique (Socket,Core) pair. Stressapptest is wrapped with `taskset -c <csv>` for all pinned CPUs. Eliminates scheduler migration for reproducible results.

### New CLI flags

- `--numa-node N`: Constrain testing to NUMA node N (requires `numactl`)
- `--pin`: Pin each memtester to a specific physical CPU core (uses `taskset`)

### New functions

- `validate_numa_node()` in `system_detect.sh`: Validate NUMA node exists in sysfs and numactl is available
- `get_physical_cpu_list()` in `system_detect.sh`: Map physical cores to lowest logical CPU IDs via lscpu, with optional NUMA node filter
- `get_node_core_count()` in `system_detect.sh`: Count physical cores on a NUMA node

### Flag interactions

| Flags | Effect |
|-------|--------|
| `--numa-node N` | numactl wraps each memtester and stressapptest; core count = node's physical cores |
| `--pin` | taskset wraps each memtester with one CPU per physical core; stressapptest gets taskset with CSV |
| `--numa-node N --pin` | Both: numactl outermost, taskset inner; CPUs filtered to node N |
| `--threads T --numa-node N` | T threads on node N; warns if T > node's core count |
| `--threads T --pin` | T threads pinned to first T physical CPUs |

### Documentation

- Added `--numa-node` and `--pin` flags to README features, usage, and execution flow
- Added "NUMA-Aware Testing" and "CPU Pinning" sections to README
- Updated CLAUDE.md execution flow, dependencies, and source layout descriptions
- Marked TODO items #3 (NUMA Locality) as partially complete and #5 (Thread Pinning) as complete
- Updated test counts and fixtures list

## v0.6 (2026-03-02)

### New features

- **`--stop-on-error`**: Terminate immediately on first error (memtester exit or EDAC UE), killing remaining threads. EDAC UE counters are polled every 10 seconds during Phase 1. Phase 2 (stressapptest) is skipped on early stop.
- **`--threads N`**: Override auto-detected physical core count with an explicit number of memtester instances. Warns if N exceeds logical CPU count.

### New CLI flags

- `--stop-on-error`: Fast-fail on first memtester failure or EDAC UE (default: wait for all threads)
- `--threads N`: Explicit thread count (default: auto-detect physical cores via `lscpu`)

### New functions

- `kill_all_memtesters()` in `parallel.sh`: Send SIGTERM to all tracked memtester PIDs and wait for exit
- `poll_edac_for_ue()` in `edac.sh`: Background EDAC UE polling loop for `--stop-on-error`
- `wait_and_collect()` now accepts optional `stop_on_error` parameter (backwards compatible)

### Documentation

- Added FAQ sections: "When should I use --stop-on-error?" and "When should I use --threads N?"
- Added FAQ section: "What do the memtester test names mean?" with fault class table
- Added `--stop-on-error` and `--threads N` to README features, usage, and execution flow
- Removed completed TODO items #5 (thread override) and #10 (stop on first error)
- Renumbered TODO #6 (thread pinning) to #5

## v0.5 (2026-03-02)

### Documentation

- Added FAQ section: "How do I test HBM or other memory on CPU-less NUMA nodes?" with NVIDIA Grace Blackwell HBM as primary example, numactl workflow, and EDAC considerations
- Added README cross-reference from "Single-socket testing" to CPU-less NUMA node FAQ
- Extended TODO NUMA locality item with multi-node `--numa-node 1,2,3` support for HBM testing
- Added platform support table for memtester and stressapptest architectures
- Added phase-labeled completion estimates for both phases
- Removed TODO #7 (Time Estimation) — implemented in v0.4

## v0.4 (2026-02-26)

### New features

- **Decimal `--percent`**: The `--percent` flag now accepts decimal values from 0.001 to 100 (e.g., `--percent 0.1`). Internally uses a "millipercent" integer strategy (0.1% = 100 millipercent) to keep all arithmetic integer-only. Up to 3 decimal places supported.
- **`--size` flag**: Specify an exact total RAM amount to test with a unit suffix: `--size 256M`, `--size 2G`, `--size 1T`, `--size 1024K`. Supports K (KiB), M (MiB), G (GiB), and T (TiB). The total is divided equally among cores, the same as `--percent`. Mutually exclusive with `--percent`.
- **L3-aware adaptive calibration**: Time estimation now detects L3 cache size via sysfs (with `getconf` fallback) and uses 4x L3 as the calibration size per the STREAM benchmark rule. This ensures calibration measures DRAM bandwidth rather than cache bandwidth, improving estimate accuracy by 5-10x. Calibration size is clamped to `[1, ram_per_core_mb]`. Falls back to 512 MB when L3 detection fails.
- **`--estimate` flag**: Control time estimation calibration: `auto` (default, silently skips on failure), `on` (warns on failure), `off` (skips entirely).

### New CLI flags

- `--percent N`: Now accepts decimal values (0.001-100, was 1-100)
- `--size SIZE`: Explicit test RAM with unit suffix (K, M, G, T); mutually exclusive with `--percent`
- `--estimate MODE`: Time estimate calibration: `auto` (default), `on`, `off`

### New functions

- `decimal_to_millipercent()` in `math_utils.sh`: Convert decimal percent string to integer millipercents
- `percentage_of_milli()` in `math_utils.sh`: Integer percentage using millipercents (`value * millipercent / 100000`)
- `parse_size_to_kb()` in `unit_convert.sh`: Parse size string with K/M/G/T suffix to kB
- `calculate_test_ram_kb_milli()` in `ram_calc.sh`: RAM calculation using millipercents
- `get_l3_cache_kb()` in `system_detect.sh`: Detect total L3 cache size via sysfs or `getconf`
- `estimate_duration()` in `estimate.sh`: Scale calibration time linearly with calibration size ratio
- `run_calibration()` in `estimate.sh`: Run memtester at adaptive calibration size
- `print_phase_estimate()` in `estimate.sh`: Display and log estimated completion time with phase label
- `print_estimate()` in `estimate.sh`: Backward-compatible wrapper (no phase label)

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
