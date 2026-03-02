# Design: FAQ test names, --stop-on-error, --threads N

Date: 2026-03-02
Status: Approved

## Feature 1: FAQ — memtester test names (#11)

Pure documentation. New section in `FAQ.md`: "What do the memtester test names mean?" Lists each pattern test, what memory property it exercises, and what fault class it detects (stuck address, data retention, coupling faults, address decoder faults, etc.). Sources: memtester `tests.c` and established memory testing literature (March algorithms, walking ones/zeros).

No code changes. No tests needed.

## Feature 2: `--stop-on-error` (#10)

### Goal

Terminate the run immediately when any error is detected, rather than waiting for all memtester threads to complete. Two error sources trigger early stop:

1. Any memtester process exits non-zero.
2. Any EDAC UE counter increases during the run (polled every 10 s).

CE-only events do not trigger early stop (consistent with `--allow-ce` semantics). Phase 2 (stressapptest) is skipped on early stop.

### Files changed

**`lib/cli.sh`**
- Add `STOP_ON_ERROR=0` default.
- Add `--stop-on-error` flag (no argument, sets `STOP_ON_ERROR=1`).
- No extra validation needed.
- Add `--stop-on-error` to `usage`.

**`lib/parallel.sh`**
- Add `kill_all_memtesters()`: sends SIGTERM to all PIDs in `MEMTESTER_PIDS[]`, then waits for each to exit. Logs which thread triggered the kill.
- Modify `wait_and_collect` signature: add `stop_on_error` parameter (default 0 for backwards compatibility). After each `wait $pid`, if exit non-zero and `stop_on_error=1`: call `kill_all_memtesters`, set `STOP_ON_ERROR_TRIGGERED=memtester`, return 1 immediately.

**`lib/edac.sh`**
- Add `poll_edac_for_ue()`: background polling function. Takes `<baseline_file> <sentinel_file> <interval_seconds>`. Loops: sleep N, capture counters to temp file, classify; if UE detected, write "ue" to sentinel file and exit. Stops when sentinel file pre-exists with value "stop".

**`pmemtester` (main)**
- Pass `$STOP_ON_ERROR` to `wait_and_collect`.
- If `STOP_ON_ERROR=1` and EDAC supported: start `poll_edac_for_ue` in background before Phase 1. After Phase 1 (`wait_and_collect` returns), write "stop" to sentinel to kill the poll loop. Check sentinel for "ue" and set `edac_early_stop=1` if found.
- Take final EDAC snapshot after killing processes (preserves accurate before/after diff).
- Log which source triggered early stop (memtester exit or EDAC UE).
- Skip Phase 2 if early stop triggered.

### Invariants

- Final EDAC snapshot always taken after all memtester processes are dead.
- `MEMTESTER_FAIL_COUNT` still updated correctly even on early stop.
- Without `--stop-on-error`, behaviour is identical to current.

### New global

`STOP_ON_ERROR_TRIGGERED=""` — set to `"memtester"` or `"edac_ue"` when early stop fires.

## Feature 3: `--threads N` (#5)

### Goal

Allow users to override the auto-detected physical core count with an explicit thread count.

### Files changed

**`lib/cli.sh`**
- Add `THREADS=0` default (0 = auto-detect via `get_core_count`).
- Add `--threads N` flag.
- `validate_args`: validate `N > 0` if set. Warn (not error) if `N > $(nproc 2>/dev/null || echo 0)`.
- Add `--threads` to `usage`.

**`pmemtester` (main)**
- After `core_count="$(get_core_count)"`, if `THREADS > 0`: log override message ("using --threads N (auto-detected: M cores)"), then set `core_count=$THREADS`.
- No changes to `parallel.sh`, `ram_calc.sh`, or `system_detect.sh` — they all accept `num_cores` as a parameter already.

### Validation behaviour

- `--threads 0` → error: must be > 0.
- `--threads 2` on a 64-core machine → silently accepted (useful for single-socket testing on dual-socket).
- `--threads 128` on a 4-core machine → WARNING printed, test proceeds.

## TDD notes

All new functions get unit tests before implementation:

- `kill_all_memtesters`: test that SIGTERM is sent, that it handles empty PID list, that it waits for exit.
- `wait_and_collect` with `stop_on_error=1`: test early exit on first failure, test that surviving PIDs are killed.
- `poll_edac_for_ue`: test that sentinel is written on UE, test that it stops on "stop" sentinel.
- CLI: test `--stop-on-error` sets flag, `--threads N` sets value, validation for both.
- `validate_args`: test `--threads 0` fails, `--threads 4` passes, warning emitted when N > nproc.
