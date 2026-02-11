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
