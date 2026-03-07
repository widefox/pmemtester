# Smoke tests: run pmemtester against real memtester/stressapptest binaries.
# These require real binaries installed and take 10-30s to complete.
# Run with: make test-smoke
#
# Uses L3-aware calibration size (4x L3 cache) to ensure DRAM-bound testing
# on any hardware. The same logic pmemtester uses internally for time estimates.

MEMTESTER_BIN="/usr/local/bin/memtester"
STRESSAPPTEST_BIN="/usr/local/bin/stressapptest"

setup() {
    load '../test_helper/common_setup'
    _common_setup
    TEST_LOG_DIR="$(mktemp -d)"

    # Compute L3-aware smoke test size (same logic as pmemtester calibration)
    source "${PROJECT_ROOT}/lib/system_detect.sh"
    local l3_kb cal_per_core_mb core_count
    if l3_kb="$(get_l3_cache_kb)"; then
        cal_per_core_mb=$(( l3_kb * 4 / 1024 ))
    else
        cal_per_core_mb=512
    fi
    # Floor: at least 12 MB per core (smallest useful DRAM-bound size)
    if [[ "$cal_per_core_mb" -lt 12 ]]; then
        cal_per_core_mb=12
    fi
    core_count="$(get_core_count)"
    # --size is total across all cores
    SMOKE_SIZE="$(( cal_per_core_mb * core_count ))M"
}

teardown() {
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
}

# --- Test 1: memtester-only pass ---

@test "smoke: memtester-only pass" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "Phase 1"
    assert_output --partial "MB"
    assert_output --partial "core"
    # Log files should exist
    [[ -f "${TEST_LOG_DIR}/master.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
}

# --- Test 2: stressapptest-only pass ---

@test "smoke: stressapptest pass" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    [[ -x "$STRESSAPPTEST_BIN" ]] || skip "stressapptest not found at $STRESSAPPTEST_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "Phase 2"
    [[ -f "${TEST_LOG_DIR}/stressapptest.log" ]]
}

# --- Test 3: both phases pass ---

@test "smoke: both phases pass" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    [[ -x "$STRESSAPPTEST_BIN" ]] || skip "stressapptest not found at $STRESSAPPTEST_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "Phase 1"
    assert_output --partial "Phase 2"
    assert_output --partial "PASS"
}

# --- Test 4: memtester receives expected memory arg ---

@test "smoke: memtester receives expected memory arg" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    # Create wrapper that logs args then execs real memtester
    local wrapper_dir
    wrapper_dir="$(mktemp -d)"
    local arg_log="${TEST_LOG_DIR}/memtester_args.txt"

    cat > "${wrapper_dir}/memtester" <<WRAPPER
#!/usr/bin/env bash
echo "\$1" >> "${arg_log}"
exec "$MEMTESTER_BIN" "\$@"
WRAPPER
    chmod +x "${wrapper_dir}/memtester"

    local pmem_output
    pmem_output="$("${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --memtester-dir "$wrapper_dir" \
        --log-dir "$TEST_LOG_DIR" 2>&1)"

    # Extract per-core MB from Phase 1 output: "Phase 1 (memtester) started: 20MB x 2 instances"
    local expected_mb
    [[ "$pmem_output" =~ Phase\ 1.*started:\ ([0-9]+)MB ]]
    expected_mb="${BASH_REMATCH[1]}"
    [[ -n "$expected_mb" ]]

    # Verify arg log was created with entries
    [[ -f "$arg_log" ]]
    local line_count
    line_count=$(wc -l < "$arg_log")
    [[ "$line_count" -ge 1 ]]

    # Each captured arg should match what pmemtester reported
    while IFS= read -r arg; do
        [[ "$arg" == "${expected_mb}M" ]]
    done < "$arg_log"

    rm -rf "$wrapper_dir"
}

# --- Test 5: stressapptest receives expected memory arg ---

@test "smoke: stressapptest receives expected memory arg" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    [[ -x "$STRESSAPPTEST_BIN" ]] || skip "stressapptest not found at $STRESSAPPTEST_BIN"

    # Create wrapper that logs args then execs real stressapptest
    local wrapper_dir
    wrapper_dir="$(mktemp -d)"
    local arg_log="${TEST_LOG_DIR}/sat_args.txt"

    cat > "${wrapper_dir}/stressapptest" <<WRAPPER
#!/usr/bin/env bash
echo "\$*" >> "${arg_log}"
exec "$STRESSAPPTEST_BIN" "\$@"
WRAPPER
    chmod +x "${wrapper_dir}/stressapptest"

    local pmem_output
    pmem_output="$("${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --stressapptest-dir "$wrapper_dir" \
        --log-dir "$TEST_LOG_DIR" 2>&1)"

    # Extract total MB from Phase 2 output: "Phase 2 (stressapptest) started: 38MB, 1s"
    local expected_total_mb
    [[ "$pmem_output" =~ Phase\ 2.*started:\ ([0-9]+)MB ]]
    expected_total_mb="${BASH_REMATCH[1]}"
    [[ -n "$expected_total_mb" ]]

    # Verify -M value in captured args matches what pmemtester reported
    [[ -f "$arg_log" ]]
    grep -q -- "-M ${expected_total_mb}" "$arg_log"

    rm -rf "$wrapper_dir"
}

# --- Test 6: log files contain expected content ---

@test "smoke: log files contain expected content" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"

    # master.log should have start and finish entries
    [[ -f "${TEST_LOG_DIR}/master.log" ]]
    grep -q "pmemtester started" "${TEST_LOG_DIR}/master.log"
    grep -q "PASS" "${TEST_LOG_DIR}/master.log"

    # Thread logs should exist for each core
    local core_count
    core_count="$(get_core_count)"

    local i
    for (( i = 0; i < core_count; i++ )); do
        [[ -f "${TEST_LOG_DIR}/thread_${i}.log" ]]
        # Thread log should have content (memtester output)
        [[ -s "${TEST_LOG_DIR}/thread_${i}.log" ]]
    done
}

# --- Test 7: --percent code path end-to-end ---

@test "smoke: --percent 1 both phases pass" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    [[ -x "$STRESSAPPTEST_BIN" ]] || skip "stressapptest not found at $STRESSAPPTEST_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --percent 1 \
        --iterations 1 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "Phase 1"
    assert_output --partial "Phase 2"
    assert_output --partial "PASS"
}

# --- Test 8: --version ---

@test "smoke: --version prints version and exits" {
    run "${PROJECT_ROOT}/pmemtester" --version
    assert_success
    assert_output --partial "pmemtester"
    # Should contain a version number (digit.digit pattern)
    [[ "$output" =~ [0-9]+\.[0-9]+ ]]
}

# --- Test 9: --help ---

@test "smoke: --help prints usage and exits" {
    run "${PROJECT_ROOT}/pmemtester" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--percent"
    assert_output --partial "--size"
    assert_output --partial "--numa-node"
    assert_output --partial "--pin"
    assert_output --partial "--show-physical"
    assert_output --partial "--check-deps"
}

# --- Test 10: --check-deps ---

@test "smoke: --check-deps shows all sections and exits" {
    run "${PROJECT_ROOT}/pmemtester" --check-deps
    # Exit code depends on whether memtester is installed
    assert_output --partial "dependency check"
    assert_output --partial "Required:"
    assert_output --partial "Optional:"
    assert_output --partial "System:"
    assert_output --partial "memtester"
    assert_output --partial "lscpu"
    assert_output --partial "/proc/meminfo"
    assert_output --partial "Physical cores"
    assert_output --partial "Memory lock"
    assert_output --partial "pagemap"
}

# --- Test 11: --check-deps exits 0 when memtester is present ---

@test "smoke: --check-deps exits 0 when memtester installed" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" --check-deps
    assert_success
    assert_output --partial "All required dependencies found"
}

# --- Test 12: invalid flag ---

@test "smoke: unknown flag prints error and exits non-zero" {
    run "${PROJECT_ROOT}/pmemtester" --nonexistent-flag
    assert_failure
    assert_output --partial "ERROR"
    assert_output --partial "unknown option"
}

# --- Test 13: --percent and --size mutual exclusion ---

@test "smoke: --percent and --size mutually exclusive" {
    run "${PROJECT_ROOT}/pmemtester" --percent 50 --size 256M
    assert_failure
    assert_output --partial "mutually exclusive"
}

# --- Test 14: --estimate off skips calibration ---

@test "smoke: --estimate off skips calibration" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --estimate off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    # Should NOT have calibration output
    refute_output --partial "Estimated completion"
    # calibration.log should not exist
    [[ ! -f "${TEST_LOG_DIR}/calibration.log" ]]
}

# --- Test 15: --color off suppresses ANSI codes ---

@test "smoke: --color off produces no ANSI escape codes" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --color off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    # No ANSI escape sequences (ESC [ = \x1b\x5b = \033[)
    refute_output --partial $'\033['
}

# --- Test 16: --color on forces ANSI codes ---

@test "smoke: --color on forces ANSI escape codes in PASS" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --color on \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    # Should contain ANSI escape sequence for green
    [[ "$output" == *$'\033['* ]]
}

# --- Test 17: --threads 1 uses exactly one thread ---

@test "smoke: --threads 1 runs single memtester instance" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --threads 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    # Should report 1 instance
    assert_output --partial "1 instance"
    # Only thread_0.log should exist
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ ! -f "${TEST_LOG_DIR}/thread_1.log" ]]
}

# --- Test 18: --threads 2 uses exactly two threads ---

@test "smoke: --threads 2 runs two memtester instances" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --threads 2 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "2 instances"
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_1.log" ]]
}

# --- Test 19: decimal percent ---

@test "smoke: --percent 0.1 passes (decimal percent)" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --percent 0.1 \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "Phase 1"
}

# --- Test 20: --size with K suffix ---

@test "smoke: --size with K suffix" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    # Use a small K value (need at least 1MB per core after division)
    source "${PROJECT_ROOT}/lib/system_detect.sh"
    local cores
    cores="$(get_core_count)"
    # At least 2MB per core in KiB
    local total_k=$(( cores * 2048 ))

    run "${PROJECT_ROOT}/pmemtester" \
        --size "${total_k}K" \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

# --- Test 21: --size with G suffix ---

@test "smoke: --size with G suffix" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    # Use 1G only if enough RAM, otherwise skip
    # This tests the G suffix parsing path end-to-end
    source "${PROJECT_ROOT}/lib/system_detect.sh"
    local avail_kb
    avail_kb="$(get_available_ram_kb)"
    [[ "$avail_kb" -ge 2097152 ]] || skip "Less than 2G available RAM"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "1G" \
        --iterations 1 \
        --threads 1 \
        --stressapptest off \
        --estimate off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

# --- Test 22: --stop-on-error with passing tests ---

@test "smoke: --stop-on-error with passing test completes normally" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stop-on-error \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

# --- Test 23: --allow-ce with no EDAC still passes ---

@test "smoke: --allow-ce passes when no EDAC errors" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --allow-ce \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

# --- Test 24: --pin passes ---

@test "smoke: --pin runs with CPU pinning" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    command -v taskset > /dev/null 2>&1 || skip "taskset not found"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --pin \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "CPU pinning"
}

# --- Test 25: --show-physical graceful behavior ---

@test "smoke: --show-physical works or warns gracefully" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --show-physical \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    # Either shows physical mapping or warns about permissions
    if [[ -r /proc/self/pagemap ]]; then
        assert_output --partial "Physical Address Mapping"
    else
        assert_output --partial "pagemap not readable"
    fi
}

# --- Test 26: combined flags ---

@test "smoke: combined flags --threads 1 --estimate off --color off" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --threads 1 \
        --estimate off \
        --color off \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    refute_output --partial $'\033['
    [[ ! -f "${TEST_LOG_DIR}/calibration.log" ]]
}

# --- Test 27: --pin with --threads 1 ---

@test "smoke: --pin --threads 1 pins single thread" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    command -v taskset > /dev/null 2>&1 || skip "taskset not found"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --pin \
        --threads 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "CPU pinning"
}

# --- Test 28: --pin with stressapptest ---

@test "smoke: --pin with stressapptest wraps both phases" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    [[ -x "$STRESSAPPTEST_BIN" ]] || skip "stressapptest not found at $STRESSAPPTEST_BIN"
    command -v taskset > /dev/null 2>&1 || skip "taskset not found"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --pin \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "Phase 1"
    assert_output --partial "Phase 2"
    assert_output --partial "PASS"
}

# --- Test 29: --stop-on-error with stressapptest ---

@test "smoke: --stop-on-error with both phases passing" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"
    [[ -x "$STRESSAPPTEST_BIN" ]] || skip "stressapptest not found at $STRESSAPPTEST_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stop-on-error \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "Phase 1"
    assert_output --partial "Phase 2"
    assert_output --partial "PASS"
}

# --- Test 30: master.log contains timing information ---

@test "smoke: master.log contains timing and phase info" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"

    [[ -f "${TEST_LOG_DIR}/master.log" ]]
    # Should contain start message, Phase 1 markers, and verdict
    grep -q "pmemtester started" "${TEST_LOG_DIR}/master.log"
    grep -q "Phase 1" "${TEST_LOG_DIR}/master.log"
    grep -q "PASS" "${TEST_LOG_DIR}/master.log"
    # Should contain timing (duration output)
    grep -q "Total" "${TEST_LOG_DIR}/master.log"
}

# --- Test 31: --stressapptest off produces no stressapptest.log ---

@test "smoke: --stressapptest off creates no stressapptest.log" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    "${PROJECT_ROOT}/pmemtester" \
        --size "$SMOKE_SIZE" \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"

    [[ ! -f "${TEST_LOG_DIR}/stressapptest.log" ]]
}

# --- Test 32: --ram-type total ---

@test "smoke: --ram-type total passes" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --percent 1 \
        --ram-type total \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

# --- Test 33: --ram-type free ---

@test "smoke: --ram-type free passes" {
    [[ -x "$MEMTESTER_BIN" ]] || skip "memtester not found at $MEMTESTER_BIN"

    run "${PROJECT_ROOT}/pmemtester" \
        --percent 1 \
        --ram-type free \
        --iterations 1 \
        --stressapptest off \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}
