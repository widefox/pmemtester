# Design: Multi-node NUMA support (`--numa-node 0,1,2`)

## Summary

Extend `--numa-node` to accept comma-separated node lists. All specified nodes
are tested in parallel. CPU-less nodes (e.g., HBM) automatically borrow CPUs
from a donor node. Per-node results printed as each finishes, then overall
PASS/FAIL.

## Architecture

Multi-node runs spawn one background subshell ("node runner") per node. Each
runner executes the full Phase 1 + Phase 2 pipeline independently. Single-node
runs use the existing code path (no subshells, backwards compatible).

```text
main()
  parse "0,1,2" -> node_list=(0 1 2)
  for each node: resolve CPUs (own cores or borrow from donor)
  EDAC before snapshot (single, system-wide)
  for each node: run_node_test() &    <- parallel background subshells
    Phase 1: run_all_memtesters (numactl --cpunodebind=X --membind=N)
    Phase 2: run_stressapptest  (numactl --cpunodebind=X --membind=N)
    write exit code to node result file
  wait for all node runners
  EDAC after snapshot (single, system-wide)
  print per-node results
  overall PASS/FAIL
```

## CPU borrowing for CPU-less nodes

- Donor = first node in the system with CPUs (via get_node_core_count)
- Memtesters: `numactl --cpunodebind=<donor> --membind=<target>`
- Thread count = donor core count (overridden by --threads)
- Status: "Node 2: borrowing CPUs from node 0 (node 2 has no CPUs)"

## Per-node isolation

Each node runner gets:
- Log subdirectory: `$log_dir/node_N/`
- Its own CPU_LIST, memtester PIDs, wait logic
- Per-node verdict file: `$log_dir/node_N/result`

## CLI

- `--numa-node 0,1,2` — comma-separated, all validated against sysfs
- Single node = current behavior unchanged
- `--threads` applies per-node
- `--pin` applies per-node
- `--stop-on-error` kills all nodes on first error

## EDAC

Single system-wide before/after snapshot. Warning printed for multi-node runs
that errors cannot be attributed to specific nodes.

## Exit codes

- 0: all nodes passed, no EDAC errors
- 1: any node failed or EDAC errors detected
