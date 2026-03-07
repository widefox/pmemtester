#!/usr/bin/env bats
# Acceptance tests for pmemtester
# These validate user-facing requirements from the operator's perspective.
# Each test maps to a documented requirement or user story.
# Uses mocked externals — verifies behaviour, not performance.

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    FIXTURE_DIR="${PROJECT_ROOT}/test/fixtures"
    TEST_LOG_DIR="$(mktemp -d)"
    TEST_MEMTESTER_DIR="$(mktemp -d)"

    # Passing memtester mock
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
# Accepts: <size>M <iterations>
echo "memtester version 4.6.0 (64-bit)"
echo "  Loop 1/1:"
echo "  Stuck Address       : ok"
echo "  Random Value        : ok"
echo "  Compare XOR         : ok"
echo "Done."
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    # 2 physical cores
    create_mock lscpu '
case "$*" in
    *Socket,Core,CPU,Node*)
        echo "# Socket,Core,CPU,Node"
        echo "0,0,0,0"
        echo "0,1,1,0"
        ;;
    *)
        echo "# Socket,Core"
        echo "0,0"
        echo "0,1"
        ;;
esac'

    create_mock dmesg 'cat '"${FIXTURE_DIR}/edac_messages_clean.txt"
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    export EDAC_BASE="${TEST_LOG_DIR}/no_edac"
    export MOCK_ULIMIT_L="unlimited"
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_3mb"
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
    [[ -d "${TEST_MEMTESTER_DIR:-}" ]] && rm -rf "$TEST_MEMTESTER_DIR"
}

# ============================================================================
# REQ-001: Parallel execution — one memtester per physical core
# ============================================================================

@test "acceptance: spawns one memtester per physical core" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success

    # Check that 2 thread logs were created (matching 2 mock cores)
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_1.log" ]]
    # No third thread log
    [[ ! -f "${TEST_LOG_DIR}/thread_2.log" ]]
}

# ============================================================================
# REQ-002: RAM divided equally among cores
# ============================================================================

@test "acceptance: each memtester receives equal RAM share" {
    # With 12288000 kB available, 90% = 11059200 kB, /2 cores = 5529600 kB = 5400 MB
    # Make memtester log the size argument it receives
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "memtester invoked with: $1" >&2
echo "Done."
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success

    # Each thread log should show the same size argument
    local size_0 size_1
    size_0="$(grep -o 'invoked with: [0-9]*M' "${TEST_LOG_DIR}/thread_0.log" | head -1)"
    size_1="$(grep -o 'invoked with: [0-9]*M' "${TEST_LOG_DIR}/thread_1.log" | head -1)"
    [[ -n "$size_0" ]]
    [[ "$size_0" == "$size_1" ]]
}

# ============================================================================
# REQ-003: Log files created per thread + master
# ============================================================================

@test "acceptance: creates per-thread and master log files" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success

    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_1.log" ]]
    [[ -f "${TEST_LOG_DIR}/master.log" ]]
}

# ============================================================================
# REQ-004: Master log aggregates thread output
# ============================================================================

@test "acceptance: master log contains aggregated content" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success

    # Master log should not be empty
    [[ -s "${TEST_LOG_DIR}/master.log" ]]
}

# ============================================================================
# REQ-005: PASS verdict when all memtesters succeed
# ============================================================================

@test "acceptance: reports PASS when all memtesters succeed" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
    assert_output --partial "PASS"
}

# ============================================================================
# REQ-006: FAIL verdict when any memtester fails
# ============================================================================

@test "acceptance: reports FAIL when a memtester fails" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "FAIL: Stuck Address" >&2
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_failure
    assert_output --partial "FAIL"
}

# ============================================================================
# REQ-007: Exit code 0 on PASS, non-zero on FAIL
# ============================================================================

@test "acceptance: exit code 0 on PASS" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
}

@test "acceptance: exit code non-zero on FAIL" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_failure
}

# ============================================================================
# REQ-008: --threads overrides auto-detected core count
# ============================================================================

@test "acceptance: --threads overrides core count" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --threads 1 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success

    # Only 1 thread log created
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ ! -f "${TEST_LOG_DIR}/thread_1.log" ]]
}

# ============================================================================
# REQ-009: --stop-on-error terminates on first failure
# ============================================================================

@test "acceptance: --stop-on-error exits on first memtester failure" {
    # Create a memtester that always fails
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
sleep 0.2
echo "FAIL" >&2
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --stop-on-error \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_failure
    assert_output --partial "FAIL"
}

# ============================================================================
# REQ-010: --allow-ce passes when only CE errors exist
# ============================================================================

@test "acceptance: --allow-ce passes with correctable errors only" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ce_only"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --allow-ce \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
}

# ============================================================================
# REQ-011: EDAC UE causes FAIL even with --allow-ce
# EDAC comparison is snapshot-based (before vs after). To simulate a UE
# appearing during the test, we create a dynamic EDAC fixture that increments
# ue_count between reads by using a memtester mock that bumps the counter.
# ============================================================================

@test "acceptance: UE errors cause FAIL even with --allow-ce" {
    local dynamic_edac="${TEST_LOG_DIR}/dynamic_edac/mc/mc0/csrow0"
    mkdir -p "$dynamic_edac"
    echo "0" > "$dynamic_edac/ce_count"
    echo "0" > "$dynamic_edac/ue_count"
    export EDAC_BASE="${TEST_LOG_DIR}/dynamic_edac"

    # Memtester mock that bumps UE counter mid-test
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "2" > "${dynamic_edac}/ue_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --allow-ce \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_failure
}

# ============================================================================
# REQ-012: --version shows version and exits
# ============================================================================

@test "acceptance: --version prints version and exits cleanly" {
    run "${PROJECT_ROOT}/pmemtester" --version
    assert_success
    assert_output --partial "pmemtester"
    # Should contain a version number (digit.digit pattern)
    [[ "$output" =~ [0-9]+\.[0-9]+ ]]
}

# ============================================================================
# REQ-013: --help shows usage and exits
# ============================================================================

@test "acceptance: --help prints usage and exits cleanly" {
    run "${PROJECT_ROOT}/pmemtester" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--percent"
    assert_output --partial "--size"
    assert_output --partial "--threads"
}

# ============================================================================
# REQ-014: --check-deps shows dependency report
# ============================================================================

@test "acceptance: --check-deps shows system diagnostics" {
    run "${PROJECT_ROOT}/pmemtester" \
        --check-deps \
        --memtester-dir "$TEST_MEMTESTER_DIR"
    # May pass or fail depending on whether memtester is found
    assert_output --partial "dependency check"
    assert_output --partial "Required:"
    assert_output --partial "Optional:"
    assert_output --partial "System:"
}

# ============================================================================
# REQ-015: --size accepts K, M, G, T suffixes
# ============================================================================

@test "acceptance: --size 2048K runs successfully" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 2048K \
        --threads 1 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
}

# ============================================================================
# REQ-016: --color off disables colour codes
# ============================================================================

@test "acceptance: --color off produces no ANSI escape codes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --color off \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
    # No ANSI escape sequences in output
    refute_output --partial $'\033['
}

# ============================================================================
# REQ-017: --estimate off skips calibration
# ============================================================================

@test "acceptance: --estimate off skips calibration step" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
    refute_output --partial "Calibrating"
}

# ============================================================================
# REQ-018: Graceful handling when EDAC is unavailable
# ============================================================================

@test "acceptance: runs successfully without EDAC sysfs" {
    export EDAC_BASE="${TEST_LOG_DIR}/nonexistent_edac"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
    assert_output --partial "PASS"
}

# ============================================================================
# REQ-019: Decimal --percent (0.001 - 100) works end-to-end
# ============================================================================

@test "acceptance: --percent 0.1 runs successfully" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 0.1 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success
}

# ============================================================================
# REQ-020: Invalid arguments produce clear error messages
# ============================================================================

@test "acceptance: invalid --percent shows error" {
    run "${PROJECT_ROOT}/pmemtester" --percent abc
    assert_failure
    assert_output --partial "ERROR"
}

@test "acceptance: invalid --ram-type shows error" {
    run "${PROJECT_ROOT}/pmemtester" --ram-type bogus
    assert_failure
    assert_output --partial "ERROR"
}

@test "acceptance: unknown flag shows error" {
    run "${PROJECT_ROOT}/pmemtester" --nonexistent
    assert_failure
    assert_output --partial "unknown option"
}
