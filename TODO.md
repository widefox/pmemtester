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

## Architecture Support

pmemtester currently assumes x86 Linux. Validate and test on:

- [ ] ARM64 / AArch64 (server platforms with ECC)
- [ ] PowerPC (IBM POWER systems)
- [ ] RISC-V (SiFive with CCACHE ECC)
- [ ] LoongArch (Loongson 3A5000/3A6000)

Considerations:
- memtester itself is portable C, so the wrapper should work anywhere memtester runs
- EDAC sysfs interface is architecture-independent (`/sys/devices/system/edac/mc/`)
- `/proc/meminfo` and `nproc` are available on all Linux architectures
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
