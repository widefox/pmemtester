# TODO

## 1. EDAC Region Correlation

EDAC counters are system-wide -- pmemtester compares counters across all memory controllers before and after the test, with no correlation to the specific memory regions being tested. This means:

- If testing a subset of RAM (e.g., socket 1 via `numactl --membind=1`), an EDAC error triggered by a workload on socket 0 will still cause a FAIL
- There is no way to determine whether an EDAC error occurred in the memory region under test or elsewhere
- On multi-socket systems, this can produce misleading failures when other sockets are under load

Potential improvements:
- Parse EDAC sysfs per-MC/per-csrow counters to identify which memory controller reported the error
- When `numactl --membind=N` is used, only check EDAC counters for the corresponding memory controller(s)
- Add `--edac-mc N` flag to restrict EDAC checking to a specific memory controller
- Log which MC/csrow/channel reported the error change for easier diagnosis

## 2. Architecture Support

pmemtester uses portable Linux interfaces and should run on any architecture where memtester compiles, but has only been tested on x86. Validate and test on:

- [ ] ARM64 / AArch64 (server platforms with ECC)
- [ ] PowerPC (IBM POWER systems)
- [ ] RISC-V (SiFive with CCACHE ECC)
- [ ] LoongArch (Loongson 3A5000/3A6000)

Considerations:
- memtester itself is portable C, so the wrapper should work anywhere memtester runs
- EDAC sysfs interface is architecture-independent (`/sys/devices/system/edac/mc/`)
- `/proc/meminfo`, `lscpu`, and `nproc` are available on all Linux architectures, but `MemAvailable` requires kernel 3.14+ (the default `--ram-type available` will fail on older kernels with "field 'MemAvailable' not found")
- `ulimit -l` memory locking behavior may differ across platforms
- EDAC_GHES (firmware-first) may be the only EDAC path on some ARM64 servers

## 3. NUMA Locality

Document and potentially improve NUMA behaviour:

- pmemtester currently uses `lscpu` for core count and lets the kernel allocate memory freely across NUMA nodes
- Memory allocation is not NUMA-aware -- the kernel's default policy (local allocation) means each process likely gets memory from its local node, but this is not guaranteed
- For explicit per-node testing, users can wrap pmemtester with `numactl --cpunodebind=N --membind=N` (documented in README)
- Consider adding a `--numa-node N` flag to constrain testing to a specific NUMA node natively
- Consider adding a `--per-node` mode that tests each NUMA node sequentially and reports per-node results

## 4. Heterogeneous Cores

pmemtester currently treats all CPU threads homogeneously:

- On big.LITTLE / hybrid architectures (e.g., Intel P-cores + E-cores, ARM big.LITTLE), all threads get equal RAM allocations regardless of core capability
- This is acceptable for memory testing since memtester is memory-bound not compute-bound -- core performance differences have negligible impact
- Document this assumption and any edge cases (e.g., E-cores with smaller cache may exhibit different memory access patterns)
- Consider whether thread pinning (`taskset`) to specific core types would improve test coverage or reproducibility

## 5. Thread Override

pmemtester uses `lscpu -b -p=Socket,Core` to detect physical cores (with `nproc` fallback), launching one memtester per physical core. This avoids SMT bandwidth regression measured at up to 3x on memory-bound workloads (see [FAQ.md](FAQ.md#why-one-memtester-per-core-instead-of-one-per-thread)).

- Consider adding a `--threads N` override for users who want explicit control over the number of memtester instances
- This would allow testing with fewer processes (e.g., single-socket on a dual-socket system) or more (e.g., matching hardware threads for scheduler saturation experiments)

## 6. Thread Pinning

Pin each memtester instance to a specific physical core with `taskset` or `sched_setaffinity`:

- Eliminates scheduler migration entirely -- each memtester stays on its assigned core for the full run
- Guarantees NUMA-local memory access (combined with `numactl --membind` or `mbind`)
- Makes results reproducible across runs (same core-to-memory mapping every time)
- Enables per-core performance comparison (identify a weak core or memory channel)
- Could use `lscpu -b -p=Socket,Core,CPU` to map physical cores to logical CPU IDs for pinning
- Consider a `--pin` flag to enable pinning (off by default to avoid surprising users)

## 7. Time Estimation

Run a short calibration test at the start of every run to estimate completion time:

- Before the main test, run memtester on a small sample (e.g., 0.1% of the requested RAM per thread) with logging disabled
- Measure wall-clock time for the sample, then linearly scale to the full requested amount
- Display the estimate before starting the real test (e.g., "Estimated completion: ~45 minutes")
- memtester runtime scales roughly linearly with RAM size for a given iteration count, so naive scaling should be reasonable
- Run by default (`--no-estimate` to skip), so users always see a time estimate upfront
- The calibration run also serves as a quick sanity check that memtester works before committing to a long run
- Consider caching calibration results per-host (MB/s throughput) to skip the sample on subsequent runs

## 8. Sequential Rolling RAM Test

**Out of scope.** Physical memory addressing requires kernel-level cooperation (`move_pages()`, custom module walking `page_struct`). Userspace `mmap`/`malloc` + `mlock` provides no control over which physical frames are allocated, so freeing and reallocating cannot guarantee coverage of different physical memory.

## 9. Single Binary: Port to C and Integrate with memtester

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

## 10. Optional stressapptest Second Pass

Run stressapptest automatically after the memtester pass to combine deterministic pattern testing with randomised bus-contention stress testing in a single invocation.

Rationale:
- memtester finds stuck bits and coupling faults via deterministic patterns but generates little electrical noise
- stressapptest finds timing margin failures and bus contention errors via randomised multi-threaded traffic (see README "Testing philosophy" section)
- Running both back-to-back covers complementary failure modes without requiring the user to invoke two separate tools
- EDAC monitoring spans both passes, catching hardware errors triggered by either workload

Behaviour:
- On by default: runs automatically if `stressapptest` is found in `/usr/local/bin` (or the directory specified by a future `--stressapptest-dir` flag)
- Disabled explicitly with `--no-stressapptest`
- Forced on with `--stressapptest` (fails with an error if the binary is not found, rather than silently skipping)
- Explicit duration with `--stressapptest=SECONDS`; default duration is the wall-clock time the memtester pass took (timed internally)
- stressapptest uses the same RAM amount and core count as the memtester pass
- EDAC before/after comparison spans both passes (single before snapshot, single after snapshot)
- stressapptest exit code is incorporated into the final PASS/FAIL verdict
- Per-pass results are reported separately in the master log (memtester result, stressapptest result, EDAC result)

Considerations:
- stressapptest must be installed separately (not bundled); silently skipped if not found in the default case, but errors out if `--stressapptest` was explicitly requested
- stressapptest allocates its own memory independently -- the total memory pressure is sequential, not additive, since memtester finishes first
- stressapptest's `--mem_threads` and `-M` (memory size in MB) flags map naturally to pmemtester's core count and per-core RAM allocation
- The `--seconds` flag controls stressapptest duration directly
- Log stressapptest stdout/stderr to a dedicated log file in the log directory (e.g., `stressapptest.log`)

## 11. Stop on First Error

Add a `--stop-on-error` flag that terminates the run immediately when any error is detected, rather than waiting for all memtester instances to complete.

Rationale:
- On large multi-socket systems a full run can take hours; if the first core reports a failure after 10 minutes there is no point waiting for the remaining cores
- EDAC uncorrectable errors (UE) indicate serious hardware faults -- continuing to stress faulty memory risks data corruption or kernel panic
- Useful in automated pipelines (CI, burn-in scripts) where a fast fail verdict is more valuable than a complete report

Behaviour:
- Off by default (current behaviour: wait for all threads, then report)
- When enabled, monitor two error sources during the run:
  1. **memtester exit**: any memtester process exits non-zero → kill remaining memtester processes and proceed to verdict
  2. **EDAC polling**: periodically poll EDAC counters (e.g., every 5-10 seconds) during the run; if any counter increases → kill all memtester processes and proceed to verdict
- Take a final EDAC snapshot after killing processes so the before/after diff is accurate
- Report which error source triggered the early stop in the master log
- If the stressapptest second pass is enabled, skip it on early stop (memory is already known bad)

Considerations:
- EDAC polling interval is a tradeoff: too frequent adds overhead, too infrequent delays detection. A reasonable default is every 10 seconds, potentially configurable with `--edac-poll-interval`
- memtester processes are independent background jobs; killing them requires sending SIGTERM to each tracked PID and waiting for cleanup
- Correctable errors (CE) with `--allow-ce` should not trigger early stop -- only UE or memtester failure should
- The polling loop must not interfere with memtester performance; a simple shell `sleep`/`diff` loop on EDAC sysfs counters should have negligible overhead

## 12. FAQ: Interpreting memtester test names

Add an [FAQ.md](FAQ.md) entry explaining which pattern tests what (stuck address, walking ones/zeros, checkerboard, etc.) and what class of fault each one detects.
