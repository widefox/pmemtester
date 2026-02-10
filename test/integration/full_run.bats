setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    FIXTURE_DIR="${PROJECT_ROOT}/test/fixtures"
    TEST_LOG_DIR="$(mktemp -d)"
    TEST_MEMTESTER_DIR="$(mktemp -d)"

    # Create a working memtester mock
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    # Mock nproc to 2 threads
    create_mock nproc 'echo "2"'

    # Mock dmesg with clean EDAC output
    create_mock dmesg 'cat '"${FIXTURE_DIR}/edac_messages_clean.txt"

    # Use normal meminfo fixture
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"

    # No EDAC sysfs by default (EDAC disabled)
    export EDAC_BASE="${TEST_LOG_DIR}/no_edac"

    # Mock ulimit to be unlimited
    export MOCK_ULIMIT_L="unlimited"
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
    [[ -d "${TEST_MEMTESTER_DIR:-}" ]] && rm -rf "$TEST_MEMTESTER_DIR"
}

@test "full run all pass (no EDAC)" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90
    assert_success
    assert_output --partial "PASS"
}

@test "full run memtester fails" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "FAIL" >&2
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR"
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run with EDAC support no changes" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

@test "full run EDAC counter change" {
    local edac_fixture="${TEST_LOG_DIR}/edac_fixture"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    # Memtester that increments EDAC counter mid-run
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "3" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR"
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run missing memtester" {
    rm -f "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR"
    assert_failure
}

@test "full run custom percent" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 50
    assert_success
    assert_output --partial "PASS"
}

@test "full run no EDAC support graceful" {
    export EDAC_BASE="${TEST_LOG_DIR}/no_edac_dir"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

@test "full run creates log files" {
    local log_dir="${TEST_LOG_DIR}/testlogs"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir"
    [[ -f "${log_dir}/master.log" ]]
    [[ -f "${log_dir}/thread_0.log" ]]
    [[ -f "${log_dir}/thread_1.log" ]]
}
