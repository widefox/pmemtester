# FAQ test names, --stop-on-error, --threads N Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a FAQ section explaining memtester test patterns, a `--stop-on-error` flag for fast-fail burn-in runs, and a `--threads N` flag to override the auto-detected core count.

**Architecture:** Feature 1 is pure documentation in `FAQ.md`. Features 2 and 3 follow TDD: tests first in existing bats unit test files, then minimal implementation in `lib/`. The main orchestration script `pmemtester` wires the new flags into the existing execution flow. No new library files are created.

**Tech Stack:** Bash, bats-core 1.13.0, bats-support, bats-assert. Run tests with `make test-unit` or `bats test/unit/<file>.bats`.

---

## Background: how tests work

- Tests live in `test/unit/<lib-name>.bats`.
- Each test file sources the library under test via `load_lib <file>.sh` (defined in `test/test_helper/common_setup.bash`).
- External commands are mocked by writing scripts to `$MOCK_DIR` which is prepended to `$PATH` by `setup_mock_dir` / `create_mock` (from `test/test_helper/mock_helpers.bash`).
- `run <function>` captures stdout+stderr and exit code; use `assert_success`, `assert_failure`, `assert_output`, `assert_line`.
- Functions called directly (not via `run`) execute in the current shell — needed when testing side effects on globals like `MEMTESTER_PIDS`.
- `make test-unit` runs all unit tests. `bats test/unit/foo.bats` runs a single file. `bats test/unit/foo.bats -f "pattern"` runs matching tests only.

---

## Feature 1: FAQ — memtester test names

### Task 1: Write the FAQ section

**Files:**
- Modify: `FAQ.md` (append new section)

**Step 1: Add the section**

Open `FAQ.md` and append the following at the end:

```markdown
## What do the memtester test names mean?

memtester runs a fixed sequence of pattern tests. Each test writes a pattern to every tested address and reads it back to detect faults.

| Test name | Pattern written | What it detects |
|-----------|----------------|-----------------|
| Random Value | Random 64-bit words | General data retention faults; reduces aliasing from fixed patterns |
| Compare XOR | XOR of two random values | Single-bit retention; coupling between adjacent bits |
| Compare SUB | Subtraction residue | Arithmetic path faults in memory controllers |
| Compare MUL | Multiplication residue | Same as SUB; exercises different bit patterns |
| Compare DIV | Division residue | Same; ensures full coverage of bit combinations |
| Compare OR | OR accumulation | Stuck-at-0 faults: a bit stuck low will never be set |
| Compare AND | AND accumulation | Stuck-at-1 faults: a bit stuck high will never be cleared |
| Sequential Increment | 0, 1, 2, 3, … | Address decoder faults; row/column aliasing |
| Solid Bits | All 1s then all 0s | Stuck-at faults; DRAM sense amplifier sensitivity |
| Block Sequential | 0x00…0xff rotating block | Coupling faults between cells in the same row |
| Checkerboard | 0xAA…0x55 alternating | Adjacent-cell coupling (checkerboard is the worst case for capacitive coupling) |
| Bit Spread | 0x01, 0x02, 0x04… | Walking-ones: detects a single faulty bit in each position |
| Bit Flip | Complement of Bit Spread | Walking-zeros: complement of walking-ones |
| Walking Ones | Single 1 bit marching | Classic March C− derived test; address decoder + single-bit faults |
| Walking Zeros | Single 0 bit marching | Complement of Walking Ones |

**Fault classes explained:**

- **Stuck-at faults**: A bit is permanently 0 or 1 regardless of what is written. Detected by Solid Bits, Compare OR/AND.
- **Coupling faults**: Writing one cell disturbs a neighbour. Detected by Checkerboard, Block Sequential, XOR/Compare tests.
- **Address decoder faults**: Two distinct addresses refer to the same physical cell, so writing one corrupts the other. Detected by Sequential Increment, Walking Ones/Zeros.
- **Data retention faults**: A cell loses its value over time (DRAM refresh failure). All tests detect this if the write-read gap is long enough; memtester does not add artificial delays, so very slow retention faults may be missed.
- **Transition faults**: A cell that reads correctly in isolation fails after a 0→1 or 1→0 transition. Detected by Bit Flip, Bit Spread.

memtester runs all tests in order for each iteration (`--iterations N` repeats the full sequence N times). A failure in any test on any thread causes pmemtester to report FAIL; the specific failing test and address are logged in the per-thread log (`$LOG_DIR/thread_N.log`).
```

**Step 2: Verify it renders correctly**

```bash
# Spot-check: count the table rows
grep -c "^|" FAQ.md
# Expected: at least 17 (header + separator + 15 data rows)
```

**Step 3: Commit**

```bash
git add FAQ.md
git commit -m "docs: add FAQ section explaining memtester test names and fault classes"
```

---

## Feature 2: `--stop-on-error`

### Task 2: CLI flag — tests first

**Files:**
- Modify: `test/unit/cli.bats` (append tests)
- Modify: `lib/cli.sh` (implementation comes after tests)

**Step 1: Write the failing tests**

Append to `test/unit/cli.bats`:

```bash
# --- --stop-on-error flag tests ---

@test "parse_args default STOP_ON_ERROR is 0" {
    parse_args
    [[ "$STOP_ON_ERROR" == "0" ]]
}

@test "parse_args --stop-on-error sets STOP_ON_ERROR to 1" {
    parse_args --stop-on-error
    [[ "$STOP_ON_ERROR" == "1" ]]
}

@test "parse_args --stop-on-error combined with other flags" {
    parse_args --percent 80 --stop-on-error --iterations 3
    [[ "$STOP_ON_ERROR" == "1" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "usage includes --stop-on-error" {
    run usage
    assert_success
    assert_output --partial "--stop-on-error"
}
```

**Step 2: Run tests to confirm they fail**

```bash
bats test/unit/cli.bats -f "stop-on-error"
# Expected: FAIL — "STOP_ON_ERROR: unbound variable" or similar
```

**Step 3: Implement in `lib/cli.sh`**

In the defaults block (around line 16), add:
```bash
# shellcheck disable=SC2034
STOP_ON_ERROR=0
```

In `usage()`, add a line after `--allow-ce`:
```bash
  --stop-on-error     Stop immediately when any error is detected (default: wait for all threads)
```

In `parse_args()`, add a case before `--version`:
```bash
            --stop-on-error) STOP_ON_ERROR=1; shift ;;
```

**Step 4: Run tests to confirm they pass**

```bash
bats test/unit/cli.bats -f "stop-on-error"
# Expected: all 4 PASS
```

**Step 5: Run full cli suite to check for regressions**

```bash
bats test/unit/cli.bats
# Expected: all pass
```

**Step 6: Commit**

```bash
git add lib/cli.sh test/unit/cli.bats
git commit -m "feat: add --stop-on-error CLI flag (tests + implementation)"
```

---

### Task 3: `kill_all_memtesters` — tests first

**Files:**
- Modify: `test/unit/parallel.bats` (append tests)
- Modify: `lib/parallel.sh` (implementation comes after tests)

**Step 1: Write the failing tests**

Append to `test/unit/parallel.bats`:

```bash
# --- kill_all_memtesters tests ---

@test "kill_all_memtesters with empty PID list does nothing" {
    MEMTESTER_PIDS=()
    # Should not fail even with no PIDs
    kill_all_memtesters "$TEST_LOG_DIR"
}

@test "kill_all_memtesters kills running processes" {
    # Start a long-running background process
    sleep 60 &
    local pid=$!
    MEMTESTER_PIDS=("$pid")

    kill_all_memtesters "$TEST_LOG_DIR"

    # Process should be gone
    ! kill -0 "$pid" 2>/dev/null
}

@test "kill_all_memtesters waits for processes to exit" {
    # A process that ignores SIGTERM briefly then exits
    ( trap '' TERM; sleep 1 ) &
    local pid=$!
    MEMTESTER_PIDS=("$pid")

    kill_all_memtesters "$TEST_LOG_DIR"

    # After kill_all_memtesters returns, the PID must not be running
    ! kill -0 "$pid" 2>/dev/null
}
```

**Step 2: Run tests to confirm they fail**

```bash
bats test/unit/parallel.bats -f "kill_all_memtesters"
# Expected: FAIL — "kill_all_memtesters: command not found"
```

**Step 3: Implement `kill_all_memtesters` in `lib/parallel.sh`**

Add after `MEMTESTER_PIDS=()` declaration:

```bash
# STOP_ON_ERROR_TRIGGERED: set to "memtester" or "edac_ue" on early stop
STOP_ON_ERROR_TRIGGERED=""

# kill_all_memtesters: send SIGTERM to all tracked PIDs and wait for exit
# Usage: kill_all_memtesters <log_dir>
kill_all_memtesters() {
    local log_dir="$1"
    local pid
    for pid in "${MEMTESTER_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in "${MEMTESTER_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    log_master "kill_all_memtesters: sent SIGTERM to ${#MEMTESTER_PIDS[@]} process(es)" "$log_dir"
}
```

**Step 4: Run tests to confirm they pass**

```bash
bats test/unit/parallel.bats -f "kill_all_memtesters"
# Expected: all 3 PASS
```

**Step 5: Commit**

```bash
git add lib/parallel.sh test/unit/parallel.bats
git commit -m "feat: add kill_all_memtesters (tests + implementation)"
```

---

### Task 4: `wait_and_collect` stop-on-error — tests first

**Files:**
- Modify: `test/unit/parallel.bats` (append tests)
- Modify: `lib/parallel.sh` (modify `wait_and_collect`)

**Step 1: Write the failing tests**

Append to `test/unit/parallel.bats`:

```bash
# --- wait_and_collect stop_on_error tests ---

@test "wait_and_collect stop_on_error=0 waits for all threads" {
    # All 4 fail — without stop-on-error, wait for all
    create_mock memtester 'sleep 0.1; exit 1'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    ! wait_and_collect "$TEST_LOG_DIR" 0
    [[ "$MEMTESTER_FAIL_COUNT" -eq 4 ]]
}

@test "wait_and_collect stop_on_error=1 stops after first failure" {
    # Thread 0 fails fast; threads 1-3 sleep long
    local flag_file="${TEST_LOG_DIR}/.order"
    echo "0" > "$flag_file"
    create_mock memtester 'n=$(cat '"$flag_file"'); n=$((n+1)); echo "$n" > '"$flag_file"'; if [ "$n" -eq 1 ]; then exit 1; else sleep 30; exit 0; fi'

    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    ! wait_and_collect "$TEST_LOG_DIR" 1
    # Should return quickly (not wait 30s for the sleeping threads)
    [[ "$STOP_ON_ERROR_TRIGGERED" == "memtester" ]]
}

@test "wait_and_collect stop_on_error=1 all pass returns 0" {
    create_mock memtester 'exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 3 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR" 1
    [[ "$STOP_ON_ERROR_TRIGGERED" == "" ]]
}

@test "wait_and_collect no arg defaults to stop_on_error=0" {
    create_mock memtester 'exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 2 "$TEST_LOG_DIR"
    # Should work without second argument (backwards compat)
    wait_and_collect "$TEST_LOG_DIR"
}
```

**Step 2: Run tests to confirm they fail**

```bash
bats test/unit/parallel.bats -f "stop_on_error"
# Expected: FAIL — wait_and_collect doesn't accept a second arg yet
```

**Step 3: Modify `wait_and_collect` in `lib/parallel.sh`**

Replace the existing `wait_and_collect` function:

```bash
# wait_and_collect: wait for all PIDs, return 0 if all pass, 1 if any fail
# Usage: wait_and_collect <log_dir> [stop_on_error]
# stop_on_error=1: kill remaining PIDs and return immediately on first failure
wait_and_collect() {
    local log_dir="$1"
    local stop_on_error="${2:-0}"
    local failed=0
    local i=0
    MEMTESTER_FAIL_COUNT=0
    STOP_ON_ERROR_TRIGGERED=""

    for pid in "${MEMTESTER_PIDS[@]}"; do
        if ! wait "$pid"; then
            log_master "Thread ${i} FAILED" "$log_dir"
            MEMTESTER_FAIL_COUNT=$(( MEMTESTER_FAIL_COUNT + 1 ))
            failed=1
            if [[ "$stop_on_error" -eq 1 ]]; then
                STOP_ON_ERROR_TRIGGERED="memtester"
                kill_all_memtesters "$log_dir"
                return 1
            fi
        fi
        i=$(( i + 1 ))
    done

    if [[ "$failed" -eq 1 ]]; then
        return 1
    fi
    return 0
}
```

**Step 4: Run tests to confirm they pass**

```bash
bats test/unit/parallel.bats -f "stop_on_error"
# Expected: all 4 PASS
```

**Step 5: Run full parallel suite for regressions**

```bash
bats test/unit/parallel.bats
# Expected: all pass
```

**Step 6: Commit**

```bash
git add lib/parallel.sh test/unit/parallel.bats
git commit -m "feat: wait_and_collect stop-on-error early exit (tests + implementation)"
```

---

### Task 5: `poll_edac_for_ue` — tests first

**Files:**
- Modify: `test/unit/edac.bats` (append tests)
- Modify: `lib/edac.sh` (append function)

**Step 1: Write the failing tests**

Append to `test/unit/edac.bats`:

```bash
# --- poll_edac_for_ue tests ---

@test "poll_edac_for_ue writes ue to sentinel when UE detected" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"
    local counters_dir="${TEST_DIR}/counters"
    mkdir -p "$counters_dir"

    # Baseline: no errors
    echo "mc0/csrow0/ce_count:0" > "$baseline"
    echo "mc0/csrow0/ue_count:0" >> "$baseline"

    # Override EDAC_BASE so capture_edac_counters reads a fixture with a UE
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ue_only"

    # Run poll in background with 0.1s interval
    poll_edac_for_ue "$baseline" "$sentinel" 0 &
    local poll_pid=$!

    # Give it time to detect
    sleep 0.5
    kill "$poll_pid" 2>/dev/null || true
    wait "$poll_pid" 2>/dev/null || true

    [[ -f "$sentinel" ]]
    [[ "$(cat "$sentinel")" == "ue" ]]
}

@test "poll_edac_for_ue does not write sentinel when only CE" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    echo "mc0/csrow0/ce_count:0" > "$baseline"
    echo "mc0/csrow0/ue_count:0" >> "$baseline"

    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ce_only"

    poll_edac_for_ue "$baseline" "$sentinel" 0 &
    local poll_pid=$!
    sleep 0.3
    kill "$poll_pid" 2>/dev/null || true
    wait "$poll_pid" 2>/dev/null || true

    # Sentinel should not be written (or not contain "ue")
    if [[ -f "$sentinel" ]]; then
        [[ "$(cat "$sentinel")" != "ue" ]]
    fi
}

@test "poll_edac_for_ue stops when sentinel contains stop" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    echo "mc0/csrow0/ue_count:0" > "$baseline"
    # Pre-write stop sentinel
    echo "stop" > "$sentinel"

    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ue_only"

    # Should exit immediately (sentinel already says stop)
    run poll_edac_for_ue "$baseline" "$sentinel" 0
    # It exits; sentinel still contains "stop", not "ue"
    [[ "$(cat "$sentinel")" == "stop" ]]
}

@test "poll_edac_for_ue does nothing when no UE and no stop" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    echo "mc0/csrow0/ce_count:0" > "$baseline"
    echo "mc0/csrow0/ue_count:0" >> "$baseline"

    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    poll_edac_for_ue "$baseline" "$sentinel" 0 &
    local poll_pid=$!
    sleep 0.3
    kill "$poll_pid" 2>/dev/null || true
    wait "$poll_pid" 2>/dev/null || true

    [[ ! -f "$sentinel" ]]
}
```

**Note on fixtures:** The test for "UE detected" needs `test/fixtures/edac_counters_ue_only`. Check if it exists:

```bash
ls test/fixtures/edac_counters_ue_only/ 2>/dev/null || echo "MISSING"
```

If missing, create it:

```bash
mkdir -p test/fixtures/edac_counters_ue_only/mc/mc0/csrow0
echo "0" > test/fixtures/edac_counters_ue_only/mc/mc0/csrow0/ce_count
echo "2" > test/fixtures/edac_counters_ue_only/mc/mc0/csrow0/ue_count
```

**Step 2: Run tests to confirm they fail**

```bash
bats test/unit/edac.bats -f "poll_edac_for_ue"
# Expected: FAIL — "poll_edac_for_ue: command not found"
```

**Step 3: Implement `poll_edac_for_ue` in `lib/edac.sh`**

Append to `lib/edac.sh`:

```bash
# poll_edac_for_ue: background EDAC UE polling loop for --stop-on-error
# Writes "ue" to sentinel_file if a UE counter increase is detected.
# Exits immediately if sentinel_file already contains "stop".
# Usage: poll_edac_for_ue <baseline_file> <sentinel_file> <interval_seconds>
poll_edac_for_ue() {
    local baseline_file="$1" sentinel_file="$2" interval="$3"

    while true; do
        # Stop if sentinel says so
        if [[ -f "$sentinel_file" ]] && [[ "$(cat "$sentinel_file")" == "stop" ]]; then
            return 0
        fi

        [[ "$interval" -gt 0 ]] && sleep "$interval"

        local tmp
        tmp="$(mktemp)"
        capture_edac_counters > "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }

        local classification
        classification="$(classify_edac_counters "$baseline_file" "$tmp" 2>/dev/null)" || true
        rm -f "$tmp"

        case "$classification" in
            ue_only|ce_and_ue)
                echo "ue" > "$sentinel_file"
                return 0
                ;;
        esac
    done
}
```

**Step 4: Run tests to confirm they pass**

```bash
bats test/unit/edac.bats -f "poll_edac_for_ue"
# Expected: all 4 PASS
```

**Step 5: Run full edac suite for regressions**

```bash
bats test/unit/edac.bats
# Expected: all pass
```

**Step 6: Commit**

```bash
git add lib/edac.sh test/unit/edac.bats
git commit -m "feat: add poll_edac_for_ue for --stop-on-error EDAC polling (tests + implementation)"
```

---

### Task 6: Wire `--stop-on-error` into `pmemtester` main

**Files:**
- Modify: `pmemtester`

No new unit tests needed here — the integration is covered by `test/unit/full_run.bats` style tests if they exist, otherwise the existing smoke test will exercise it.

**Step 1: Locate the Phase 1 block in `pmemtester`**

The relevant section (around line 118–125):
```bash
    # Phase 1: memtester
    print_status "Phase 1 (memtester) started: ..." "$log_dir"
    local phase1_start=$SECONDS
    run_all_memtesters ...
    local memtester_result=0
    wait_and_collect "$log_dir" || memtester_result=1
```

**Step 2: Apply the changes**

Replace the Phase 1 block and add EDAC poll setup/teardown. The full replacement of lines 117–134 (`# Phase 1:` through the intermediate EDAC check block):

```bash
    # Phase 1: memtester
    print_status "Phase 1 (memtester) started: ${ram_per_core_mb}MB x ${core_count} instances" "$log_dir"
    local phase1_start=$SECONDS

    # EDAC polling for --stop-on-error
    local edac_sentinel="${log_dir}/edac_poll_sentinel"
    local edac_poll_pid=""
    if [[ "$STOP_ON_ERROR" -eq 1 ]] && [[ "$edac_supported" -eq 1 ]]; then
        poll_edac_for_ue "${log_dir}/edac_counters_before.txt" "$edac_sentinel" 10 &
        edac_poll_pid=$!
    fi

    run_all_memtesters "$memtester_path" "$size_arg" "$ITERATIONS" "$core_count" "$log_dir"
    local memtester_result=0
    wait_and_collect "$log_dir" "$STOP_ON_ERROR" || memtester_result=1

    # Stop EDAC poll loop
    if [[ -n "$edac_poll_pid" ]]; then
        echo "stop" > "$edac_sentinel"
        wait "$edac_poll_pid" 2>/dev/null || true
    fi

    # Check if EDAC poll triggered early stop
    local edac_early_stop=0
    if [[ -f "$edac_sentinel" ]] && [[ "$(cat "$edac_sentinel")" == "ue" ]]; then
        edac_early_stop=1
        STOP_ON_ERROR_TRIGGERED="edac_ue"
        log_master "Early stop triggered by EDAC UE detected during Phase 1" "$log_dir"
        # Kill any remaining memtester processes
        kill_all_memtesters "$log_dir"
    fi

    local phase1_elapsed=$(( SECONDS - phase1_start ))
    print_status "Phase 1 (memtester) finished: $(format_phase_result "$core_count" "$MEMTESTER_FAIL_COUNT") ($(format_duration "$phase1_elapsed"))" "$log_dir"

    # Log early stop trigger if applicable
    if [[ -n "$STOP_ON_ERROR_TRIGGERED" ]]; then
        print_status "Early stop triggered by: ${STOP_ON_ERROR_TRIGGERED}" "$log_dir"
    fi

    # Intermediate EDAC check (informational)
    local edac_mid_class="none"
    if [[ "$edac_supported" -eq 1 ]]; then
        capture_edac_messages > "${log_dir}/edac_messages_mid.txt"
        capture_edac_counters > "${log_dir}/edac_counters_mid.txt"
        edac_mid_class="$(classify_edac_counters "${log_dir}/edac_counters_before.txt" "${log_dir}/edac_counters_mid.txt" 2>/dev/null)" || true
        print_status "EDAC after Phase 1: $(format_edac_summary "$edac_mid_class")" "$log_dir"
    fi
```

Then, in the Phase 2 block (around line 136), add an early stop skip condition:

```bash
    # Phase 2: conditional stressapptest
    local stressapptest_result=0
    local early_stop=$(( edac_early_stop || (STOP_ON_ERROR == 1 && memtester_result != 0) ))
    if [[ "$run_stressapptest_pass" -eq 1 ]] && [[ "$early_stop" -eq 0 ]]; then
```

And close the `if` block where it was before (the existing `fi` at the end of the Phase 2 block stays).

**Step 3: Run the full unit suite**

```bash
make test-unit
# Expected: all pass
```

**Step 4: Commit**

```bash
git add pmemtester
git commit -m "feat: wire --stop-on-error into main execution flow"
```

---

## Feature 3: `--threads N`

### Task 7: CLI flag — tests first

**Files:**
- Modify: `test/unit/cli.bats` (append tests)
- Modify: `lib/cli.sh` (implementation after tests)

**Step 1: Write the failing tests**

Append to `test/unit/cli.bats`:

```bash
# --- --threads flag tests ---

@test "parse_args default THREADS is 0" {
    parse_args
    [[ "$THREADS" == "0" ]]
}

@test "parse_args --threads 4 sets THREADS" {
    parse_args --threads 4
    [[ "$THREADS" == "4" ]]
}

@test "parse_args --threads 1 sets THREADS" {
    parse_args --threads 1
    [[ "$THREADS" == "1" ]]
}

@test "parse_args --threads combined with other flags" {
    parse_args --percent 80 --threads 2 --iterations 3
    [[ "$THREADS" == "2" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "validate_args --threads 0 fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto \
    STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 \
    ESTIMATE_MODE=auto STOP_ON_ERROR=0 THREADS=0
    # THREADS=0 is the default (auto-detect), not an explicit user 0
    # validate_args only rejects THREADS set explicitly to <= 0
    # The implementation will check THREADS_SET flag or just THREADS > 0
    # Test: explicit bad value
    THREADS=-1
    run validate_args
    assert_failure
    assert_output --partial "threads"
}

@test "validate_args --threads 4 passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto \
    STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 \
    ESTIMATE_MODE=auto STOP_ON_ERROR=0 THREADS=4
    run validate_args
    assert_success
}

@test "validate_args --threads warns if greater than nproc" {
    # Create a mock nproc that returns 2
    setup_mock_dir
    create_mock nproc 'echo 2'
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto \
    STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 \
    ESTIMATE_MODE=auto STOP_ON_ERROR=0 THREADS=8
    run validate_args
    assert_success
    assert_output --partial "WARNING"
    teardown_mock_dir
}

@test "usage includes --threads" {
    run usage
    assert_success
    assert_output --partial "--threads"
}
```

**Note on `validate_args` and `THREADS=0`:** `THREADS=0` means "auto-detect" (user did not specify `--threads`). Only reject negative values or explicitly set-to-zero-with-flag. The simplest approach: add a `THREADS_SET=0` flag similar to `PERCENT_SET`, and only validate when `THREADS_SET=1`. Update the tests and implementation accordingly — or simply check `THREADS < 0` only. The tests above use `THREADS=-1` as the "bad" case; `THREADS=0` is the valid default.

**Step 2: Run tests to confirm they fail**

```bash
bats test/unit/cli.bats -f "threads"
# Expected: FAIL
```

**Step 3: Implement in `lib/cli.sh`**

Add to defaults block:
```bash
# shellcheck disable=SC2034
THREADS=0
```

Add to `usage()`:
```bash
  --threads N         Number of memtester instances to run (default: auto-detect physical cores)
```

Add to `parse_args()`:
```bash
            --threads)    THREADS="$2"; shift 2 ;;
```

Add to `validate_args()` (before the final `return 0`):
```bash
    if [[ "$THREADS" -lt 0 ]] 2>/dev/null; then
        echo "ERROR: --threads must be >= 0 (got ${THREADS})" >&2
        return 1
    fi
    if [[ "$THREADS" -gt 0 ]]; then
        local logical_cpus
        logical_cpus="$(nproc 2>/dev/null || echo 0)"
        if [[ "$logical_cpus" -gt 0 ]] && [[ "$THREADS" -gt "$logical_cpus" ]]; then
            echo "WARNING: --threads ${THREADS} exceeds logical CPU count (${logical_cpus})" >&2
        fi
    fi
```

**Step 4: Run tests to confirm they pass**

```bash
bats test/unit/cli.bats -f "threads"
# Expected: all pass
```

**Step 5: Run full cli suite for regressions**

```bash
bats test/unit/cli.bats
# Expected: all pass
```

**Step 6: Commit**

```bash
git add lib/cli.sh test/unit/cli.bats
git commit -m "feat: add --threads N CLI flag (tests + implementation)"
```

---

### Task 8: Wire `--threads` into `pmemtester` main

**Files:**
- Modify: `pmemtester`

**Step 1: Find the core_count line (around line 55)**

```bash
    core_count="$(get_core_count)"
```

**Step 2: Add thread override after that line**

```bash
    core_count="$(get_core_count)"
    if [[ "$THREADS" -gt 0 ]]; then
        print_status "Thread override: using --threads ${THREADS} (auto-detected: ${core_count} cores)" "$log_dir"
        core_count="$THREADS"
    fi
```

Wait — `log_dir` is not yet set at line 55. Move the message to after `init_logs`, or use a plain `echo`. Check the actual order in `pmemtester`: `core_count` is computed before `init_logs`. Use a local variable to hold the message and print it after `init_logs`:

```bash
    core_count="$(get_core_count)"
    local threads_override_msg=""
    if [[ "$THREADS" -gt 0 ]]; then
        threads_override_msg="Thread override: using --threads ${THREADS} (auto-detected: ${core_count} cores)"
        core_count="$THREADS"
    fi
```

Then after `init_logs "$log_dir" "$core_count"`, add:

```bash
    if [[ -n "$threads_override_msg" ]]; then
        print_status "$threads_override_msg" "$log_dir"
    fi
```

**Step 3: Run the full unit suite**

```bash
make test-unit
# Expected: all pass
```

**Step 4: Run a smoke test if memtester is installed**

```bash
make test-smoke
# Expected: passes or skips (if memtester not installed)
```

**Step 5: Commit**

```bash
git add pmemtester
git commit -m "feat: wire --threads N override into main execution flow"
```

---

## Final: full test run and version bump

**Step 1: Run all tests**

```bash
make test
# Expected: all pass
```

**Step 2: Run lint**

```bash
make lint
# Expected: no shellcheck errors
```

**Step 3: Bump version**

In `pmemtester`, change `pmemtester_version="0.5"` to `pmemtester_version="0.6"`.

**Step 4: Commit version bump**

```bash
git add pmemtester
git commit -m "Bump version to 0.6"
```
