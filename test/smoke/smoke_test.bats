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
