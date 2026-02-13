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

    # Mock lscpu to report 2 physical cores (1 socket, 2 cores)
    create_mock lscpu 'echo "# Socket,Core"; echo "0,0"; echo "0,1"'

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

# CE/UE verdict tests

@test "full run CE only with --allow-ce passes with WARNING" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ce"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "3" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --allow-ce
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "WARNING"
}

@test "full run UE with --allow-ce still fails" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ue"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "2" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --allow-ce
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run CE+UE with --allow-ce fails" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ceue"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "5" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
echo "1" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --allow-ce
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run CE only without --allow-ce fails (backward compat)" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ce_noallow"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

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

@test "full run CE only log reports correctable" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ce_log"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "3" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    local log_dir="${TEST_LOG_DIR}/logs_ce"
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir"
    # Check master.log contains CE classification
    [[ -f "${log_dir}/master.log" ]]
    grep -q "ce_only" "${log_dir}/master.log"
}

@test "full run UE only log reports uncorrectable" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ue_log"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "2" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    local log_dir="${TEST_LOG_DIR}/logs_ue"
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir"
    # Check master.log contains UE classification
    [[ -f "${log_dir}/master.log" ]]
    grep -q "ue_only" "${log_dir}/master.log"
}

@test "full run no EDAC changes with --allow-ce clean pass" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --allow-ce
    assert_success
    assert_output --partial "PASS"
    refute_output --partial "WARNING"
}

# Coloured output tests

@test "full run --color on produces ANSI codes in PASS" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color on
    assert_success
    assert_output --partial $'\033[32m'
    assert_output --partial "PASS"
}

@test "full run --color off produces no ANSI codes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color off
    assert_success
    assert_output --partial "PASS"
    refute_output --partial $'\033['
}

@test "full run FAIL shows failure source (memtester)" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "FAIL" >&2
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color off
    assert_failure
    assert_output --partial "FAIL"
    assert_output --partial "memtester"
}

@test "full run EDAC UE shows failure source (EDAC)" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ue_src"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "2" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color off
    assert_failure
    assert_output --partial "FAIL"
    assert_output --partial "EDAC"
}

@test "full run --color on FAIL shows red ANSI" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color on
    assert_failure
    assert_output --partial $'\033[31m'
    assert_output --partial "FAIL"
}

@test "full run log message says cores not threads" {
    local log_dir="${TEST_LOG_DIR}/logs_cores"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir"
    [[ -f "${log_dir}/master.log" ]]
    grep -q "cores" "${log_dir}/master.log"
    ! grep -q "threads" "${log_dir}/master.log"
}

@test "full run nproc fallback when lscpu unavailable" {
    # Replace lscpu mock with one that fails
    create_mock lscpu 'exit 1'
    # Provide nproc mock
    create_mock nproc 'echo "4"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR"
    assert_success
    assert_output --partial "PASS"
}

@test "full run CE with --allow-ce --color on shows yellow WARNING" {
    local edac_fixture="${TEST_LOG_DIR}/edac_ce_warn"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<MOCK
#!/usr/bin/env bash
echo "3" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --allow-ce --color on
    assert_success
    assert_output --partial "PASS"
    assert_output --partial $'\033[33m'
    assert_output --partial "WARNING"
}
