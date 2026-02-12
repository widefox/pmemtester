# TODO

## EDAC Error Classification

Distinguish between EDAC error types in the pass/fail verdict:

- **CE (Correctable Errors)**: Single-bit ECC errors (ce_count) -- hardware corrected, data intact, but indicates degrading DIMM
- **UE (Uncorrectable Errors)**: Multi-bit errors (ue_count) -- data corruption, critical failure
- **Other errors**: PCI parity errors, cache errors, thermal events

Currently pmemtester treats any EDAC counter change as a failure. A more nuanced approach would:
- Report CE vs UE separately in the log
- Optionally allow CE-only runs to pass with a warning (--allow-ce flag)
- Always fail on UE (uncorrectable = data corruption)

## EDAC Region Correlation

EDAC counters are system-wide -- pmemtester compares counters across all memory controllers before and after the test, with no correlation to the specific memory regions being tested. This means:

- If testing a subset of RAM (e.g., socket 1 via `numactl --membind=1`), an EDAC error triggered by a workload on socket 0 will still cause a FAIL
- There is no way to determine whether an EDAC error occurred in the memory region under test or elsewhere
- On multi-socket systems, this can produce misleading failures when other sockets are under load

Potential improvements:
- Parse EDAC sysfs per-MC/per-csrow counters to identify which memory controller reported the error
- When `numactl --membind=N` is used, only check EDAC counters for the corresponding memory controller(s)
- Add `--edac-mc N` flag to restrict EDAC checking to a specific memory controller
- Log which MC/csrow/channel reported the error change for easier diagnosis

## Architecture Support

pmemtester currently assumes x86 Linux. Validate and test on:

- [ ] ARM64 / AArch64 (server platforms with ECC)
- [ ] PowerPC (IBM POWER systems)
- [ ] RISC-V (SiFive with CCACHE ECC)
- [ ] LoongArch (Loongson 3A5000/3A6000)

Considerations:
- memtester itself is portable C, so the wrapper should work anywhere memtester runs
- EDAC sysfs interface is architecture-independent (`/sys/devices/system/edac/mc/`)
- `/proc/meminfo` and `nproc` are available on all Linux architectures, but `MemAvailable` requires kernel 3.14+ (the default `--ram-type available` will fail on older kernels with "field 'MemAvailable' not found")
- `ulimit -l` memory locking behavior may differ across platforms
- EDAC_GHES (firmware-first) may be the only EDAC path on some ARM64 servers

## NUMA Locality

Document and potentially improve NUMA behaviour:

- pmemtester currently uses `nproc` for thread count and lets the kernel allocate memory freely across NUMA nodes
- Memory allocation is not NUMA-aware -- the kernel's default policy (local allocation) means each thread likely gets memory from its local node, but this is not guaranteed
- For explicit per-node testing, users can wrap pmemtester with `numactl --cpunodebind=N --membind=N` (documented in README)
- Consider adding a `--numa-node N` flag to constrain testing to a specific NUMA node natively
- Consider adding a `--per-node` mode that tests each NUMA node sequentially and reports per-node results

## Heterogeneous Cores

pmemtester currently treats all CPU threads homogeneously:

- On big.LITTLE / hybrid architectures (e.g., Intel P-cores + E-cores, ARM big.LITTLE), all threads get equal RAM allocations regardless of core capability
- This is acceptable for memory testing since memtester is memory-bound not compute-bound -- core performance differences have negligible impact
- Document this assumption and any edge cases (e.g., E-cores with smaller cache may exhibit different memory access patterns)
- Consider whether thread pinning (`taskset`) to specific core types would improve test coverage or reproducibility

## Cores vs Threads

pmemtester uses `nproc` which returns the number of hardware threads (including SMT/HyperThreading), not physical cores:

- On a 16-core/32-thread system, pmemtester launches 32 instances each with 1/32 of the test RAM
- Using every thread rather than every core is unlikely to be faster for memtester (memory-bound workload), but it avoids issues with the kernel scheduler not equally loading all physical cores
- More threads with smaller allocations may actually improve test coverage by exercising more memory controller interleaving patterns
- Document this trade-off and consider an optional `--threads N` override for users who want explicit control

## Time Estimation

Run a short calibration test at the start of every run to estimate completion time:

- Before the main test, run memtester on a small sample (e.g., 0.1% of the requested RAM per thread) with logging disabled
- Measure wall-clock time for the sample, then linearly scale to the full requested amount
- Display the estimate before starting the real test (e.g., "Estimated completion: ~45 minutes")
- memtester runtime scales roughly linearly with RAM size for a given iteration count, so naive scaling should be reasonable
- Run by default (`--no-estimate` to skip), so users always see a time estimate upfront
- The calibration run also serves as a quick sanity check that memtester works before committing to a long run
- Consider caching calibration results per-host (MB/s throughput) to skip the sample on subsequent runs

## v0.2: Coloured Output (Traffic Lights)

Add coloured pass/fail indicators to terminal output:

- **Green**: PASS — all memtester instances passed, no EDAC errors
- **Red**: FAIL — memtester failure or EDAC uncorrectable error (UE)
- **Yellow**: non-fatal fail — EDAC correctable error only (CE, single-bit ECC)

The failure output should specify the source: whether the failure came from EDAC or memtester (currently the verdict is opaque about which subsystem detected the problem).

## Sequential Rolling RAM Test

Investigate testing RAM sequentially in chunks, so the total tested RAM exceeds what can be tested in a single pass:

- Run memtester on chunk 1 (e.g., 25% of RAM), then chunk 2, etc.
- Total coverage exceeds what a single test can address at once (limited by available RAM)
- Useful for machines where you want to test close to 100% of physical RAM but can't lock it all simultaneously
- Consider a `--rolling` or `--sequential` mode
- Need to investigate whether the kernel reallocates the same physical pages across runs or whether this genuinely tests different physical memory

## Single Binary: Port to C and Integrate with memtester

Rewrite pmemtester as a C program that integrates memtester's testing logic directly, producing a single `pmemtester` executable with no external dependency on the `memtester` binary.

Rationale:
- Eliminates the external memtester dependency (currently must be installed separately)
- Single binary is easier to deploy, package, and distribute
- Enables tighter integration: per-thread EDAC correlation, real-time progress reporting, structured output
- Removes Bash overhead and limitations (integer-only arithmetic, process management via PIDs, no native threading)
- memtester is GPL-2.0, same as pmemtester -- licence-compatible for integration

Approach:
- Fork memtester's test routines (`tests.c`) into pmemtester
- Replace memtester's single-threaded `main()` with pthreads-based parallel execution
- Integrate EDAC sysfs reading directly (currently done via shell commands and `diff`)
- Keep the CLI interface compatible (`--percent`, `--ram-type`, `--iterations`, etc.)
- Use `mlock()` directly instead of relying on `ulimit -l` shell workarounds
- Add structured output (JSON/machine-readable) alongside human-readable output

Considerations:
- memtester's test patterns must be preserved exactly to maintain fault coverage
- Memory allocation strategy changes: memtester uses `mmap(MAP_LOCKED)` for a single region; pmemtester would need per-thread allocations
- Cross-platform portability: memtester supports non-Linux systems; pmemtester is Linux-only (EDAC dependency)
- Build system: autotools or meson, with the test suite ported from bats to a C test framework or kept as integration tests

## FAQ

Add more items to [FAQ.md](FAQ.md). Candidate topics:

- NUMA effects on test results
- Interpreting memtester test names (which pattern tests what)
- When to use pmemtester vs MemTest86+ (userspace vs standalone boot)
