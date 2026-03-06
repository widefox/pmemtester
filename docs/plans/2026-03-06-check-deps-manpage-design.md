# Design: `--check-deps` flag and manpage

## `--check-deps`

Diagnostic flag that checks all dependencies, prints verbose status with versions/paths/system capabilities, and exits. Requires root (same as running pmemtester itself).

### Output format

```text
pmemtester 0.7 dependency check

Required:
  memtester        /usr/local/bin/memtester    memtester version 4.6.0  [OK]
  lscpu            /usr/bin/lscpu              lscpu from util-linux 2.40  [OK]
  awk              /usr/bin/awk                GNU Awk 5.3.0  [OK]
  find             /usr/bin/find               find (GNU findutils) 4.10  [OK]
  diff             /usr/bin/diff               diff (GNU diffutils) 3.10  [OK]

Optional:
  stressapptest    /usr/local/bin/stressapptest  stressapptest 1.0.11  [OK]
  numactl          /usr/bin/numactl            numactl 2.0.18  [OK]
  taskset          /usr/bin/taskset             taskset from util-linux 2.40  [OK]
  dmesg            /usr/bin/dmesg              dmesg from util-linux 2.40  [OK]
  nproc            /usr/bin/nproc              nproc (GNU coreutils) 9.5  [OK]

System:
  /proc/meminfo    MemTotal: 262144000 kB, MemAvailable: 245760000 kB  [OK]
  EDAC             /sys/devices/system/edac/mc/ (2 memory controllers)  [OK]
  NUMA             2 nodes (node0: 24 cores, node1: 24 cores)  [OK]
  Physical cores   48 cores (2 sockets)  [OK]
  Memory lock      ulimit -l: unlimited  [OK]
```

### Behavior

- Exit 0 if all required deps found, exit 1 if any required dep missing
- Missing items show `[MISSING]` (red via existing color support)
- Present items show `[OK]` (green)
- Optional missing items show `[NOT FOUND]` (yellow/warn)
- Implementation: `check_deps()` function in `lib/cli.sh`
- Called from `main()` after sourcing libs, before `validate_args`

## Manpage

`pmemtester.1` in hand-written troff. Sections: NAME, SYNOPSIS, DESCRIPTION, OPTIONS, EXIT STATUS, EXAMPLES, DEPENDENCIES, FILES, SEE ALSO, AUTHORS. Installed by `make install` to `$(PREFIX)/share/man/man1/`.

## Testing

- Unit tests for `--check-deps` in `test/unit/cli.bats`
- No automated tests for manpage (static troff content)
