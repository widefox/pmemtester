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

## 3. NUMA Locality (complete)

Implemented in v0.7:

- [x] `--numa-node N` flag constrains testing to a specific NUMA node via `numactl --cpunodebind=N --membind=N`
- [x] Auto-detects node core count and adjusts thread count accordingly
- [x] CPU-less NUMA nodes (e.g., HBM) error with a message suggesting manual `numactl --membind=N` workaround
- [x] Integrates with `--threads` (warns if T > node cores) and `--pin` (filters CPUs to node)
- [x] Wraps both memtester instances and stressapptest
- [x] Multi-node support: `--numa-node 0,1,2` tests multiple nodes in parallel
- [x] Per-node results printed individually, followed by overall verdict
- [x] CPU-less nodes automatically borrow CPUs from a donor node
- [x] EDAC captured as single snapshot with warning that attribution to individual nodes is not possible

## 4. Heterogeneous Cores

pmemtester currently treats all CPU threads homogeneously:

- On big.LITTLE / hybrid architectures (e.g., Intel P-cores + E-cores, ARM big.LITTLE), all threads get equal RAM allocations regardless of core capability
- This is acceptable for memory testing since memtester is memory-bound not compute-bound -- core performance differences have negligible impact
- Document this assumption and any edge cases (e.g., E-cores with smaller cache may exhibit different memory access patterns)
- Consider whether thread pinning (`taskset`) to specific core types would improve test coverage or reproducibility

## 5. Thread Pinning (complete)

Implemented in v0.7:

- [x] `--pin` flag pins each memtester to a specific physical CPU core via `taskset -c <cpu_id>`
- [x] Uses `lscpu -b -p=Socket,Core,CPU,Node` to map physical cores to lowest logical CPU ID
- [x] Eliminates scheduler migration -- each memtester stays on its assigned core
- [x] Makes results reproducible across runs (same core-to-memory mapping)
- [x] Combines with `--numa-node N` to filter CPUs to a specific node
- [x] Stressapptest also wrapped with `taskset -c <csv>` for full pinning

## 7. Sequential Rolling RAM Test

**Out of scope.** Physical memory addressing requires kernel-level cooperation (`move_pages()`, custom module walking `page_struct`). Userspace `mmap`/`malloc` + `mlock` provides no control over which physical frames are allocated, so freeing and reallocating cannot guarantee coverage of different physical memory.

memtester's `-p` flag (physical address mode via `/dev/mem`) was evaluated as an alternative for sweeping physical RAM. **Not feasible:**

- `CONFIG_STRICT_DEVMEM=y` (default on all major distributions since ~2008) blocks `/dev/mem` access to System RAM above 1 MB; below 1 MB reads return zeros and writes are silently discarded
- `CONFIG_IO_STRICT_DEVMEM=y` further restricts even I/O memory regions claimed by active drivers
- Even with protections disabled (`iomem=relaxed` boot parameter or kernel rebuild), writing test patterns to in-use physical addresses (kernel code, page tables, slab allocator, DMA buffers, other processes) would crash the system immediately
- The `-p` flag was designed for testing memory-mapped I/O devices (PCI BARs, FPGA registers), not general-purpose RAM testing
- Kernel memory offlining (`echo offline > /sys/devices/system/memory/memoryN/state`) is theoretically possible but fragile -- the kernel refuses to offline sections containing unmovable pages

For exhaustive physical RAM testing, use a standalone boot-time tester (MemTest86, MemTest86+) where the tool has exclusive access to the full physical address space before the OS loads.

## 8. Virtual-to-Physical Address Translation for DIMM-Level Failure Correlation (complete)

Implemented in v0.8 (pending release):

- [x] `--show-physical` flag captures `/proc/PID/pagemap` snapshots during Phase 1 for each memtester thread
- [x] Translates virtual pages to physical page frame numbers (PFN) via sampled pagemap reading
- [x] Reports physical address range per thread in the test output
- [x] Correlates EDAC error addresses from dmesg with thread physical address ranges
- [x] `format_edac_dimm_topology()` lists MC/csrow/channel structure with DIMM labels
- [x] Permission-gated: gracefully warns and continues when pagemap is not readable (requires root or CAP_SYS_ADMIN)
- [x] `check_deps` shows pagemap readability and `od` availability
- [x] New `lib/pagemap.sh` with 10 functions; 3 new functions added to `lib/edac.sh`

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
