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

    # Default: no stressapptest (auto mode finds nothing, skips)
    export TEST_STRESSAPPTEST_OFF="--stressapptest-dir ${TEST_LOG_DIR}/no_sat_bin"
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
        --percent 90 \
        $TEST_STRESSAPPTEST_OFF
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
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run with EDAC support no changes" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
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
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run missing memtester" {
    rm -f "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
}

@test "full run custom percent" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 50 \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

@test "full run no EDAC support graceful" {
    export EDAC_BASE="${TEST_LOG_DIR}/no_edac_dir"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

@test "full run creates log files" {
    local log_dir="${TEST_LOG_DIR}/testlogs"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
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
        --allow-ce \
        $TEST_STRESSAPPTEST_OFF
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
        --allow-ce \
        $TEST_STRESSAPPTEST_OFF
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
        --allow-ce \
        $TEST_STRESSAPPTEST_OFF
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
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
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
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
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
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
    # Check master.log contains UE classification
    [[ -f "${log_dir}/master.log" ]]
    grep -q "ue_only" "${log_dir}/master.log"
}

@test "full run no EDAC changes with --allow-ce clean pass" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --allow-ce \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
    refute_output --partial "WARNING"
}

# Coloured output tests

@test "full run --color on produces ANSI codes in PASS" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color on \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial $'\033[32m'
    assert_output --partial "PASS"
}

@test "full run --color off produces no ANSI codes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --color off \
        $TEST_STRESSAPPTEST_OFF
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
        --color off \
        $TEST_STRESSAPPTEST_OFF
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
        --color off \
        $TEST_STRESSAPPTEST_OFF
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
        --color on \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
    assert_output --partial $'\033[31m'
    assert_output --partial "FAIL"
}

@test "full run log message says cores not threads" {
    local log_dir="${TEST_LOG_DIR}/logs_cores"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
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
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

# stressapptest integration tests

@test "stressapptest auto mode skips when not found" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest auto \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat"
    assert_success
    assert_output --partial "PASS"
}

@test "stressapptest auto mode runs when found" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest auto \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "PASS"
}

@test "stressapptest auto mode skips after memtester failure" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "should not run"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest auto \
        --stressapptest-dir "$sat_dir"
    assert_failure
    # stressapptest.log should not exist since it was skipped
    [[ ! -f "${TEST_LOG_DIR}/stressapptest.log" ]]
}

@test "stressapptest on mode passes" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "PASS"
}

@test "stressapptest on mode fails when binary missing" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat"
    assert_failure
}

@test "stressapptest on mode still runs after memtester failure" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    assert_failure
    assert_output --partial "FAIL"
    # stressapptest.log should exist because mode=on always runs
    [[ -f "${TEST_LOG_DIR}/stressapptest.log" ]]
}

@test "stressapptest off mode skips entirely" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "should not run"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest off \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "PASS"
    [[ ! -f "${TEST_LOG_DIR}/stressapptest.log" ]]
}

@test "stressapptest failure causes FAIL verdict" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: FAIL" >&2
exit 1
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    assert_failure
    assert_output --partial "FAIL"
    assert_output --partial "stressapptest"
}

@test "stressapptest and memtester both fail reports both in fail_sources" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir" \
        --color off
    assert_failure
    assert_output --partial "memtester"
    assert_output --partial "stressapptest"
}

@test "stressapptest custom seconds used" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<MOCK
#!/usr/bin/env bash
echo "args: \$*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_secs"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --stressapptest on \
        --stressapptest-seconds 42 \
        --stressapptest-dir "$sat_dir"
    grep -q -- "-s 42" "${log_dir}/stressapptest.log"
}

@test "stressapptest default seconds uses elapsed time (clamped to min 1)" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<MOCK
#!/usr/bin/env bash
echo "args: \$*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_elapsed"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --stressapptest on \
        --stressapptest-seconds 0 \
        --stressapptest-dir "$sat_dir"
    # Elapsed time for mock is ~0, clamped to 1
    grep -q -- "-s 1" "${log_dir}/stressapptest.log"
}

@test "stressapptest log file created" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_satlog"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    [[ -f "${log_dir}/stressapptest.log" ]]
}

@test "stressapptest master log records results" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_satmaster"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    grep -q "stressapptest" "${log_dir}/master.log"
    grep -q "PASSED" "${log_dir}/master.log"
}

@test "stressapptest EDAC spans both passes" {
    local edac_fixture="${TEST_LOG_DIR}/edac_sat"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    # stressapptest increments UE counter
    cat > "${sat_dir}/stressapptest" <<MOCK
#!/usr/bin/env bash
echo "1" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    # EDAC UE detected during stressapptest → FAIL
    assert_failure
    assert_output --partial "EDAC"
}

@test "stressapptest pass log says cores not threads" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_satcores"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    grep -q "stressapptest" "${log_dir}/master.log"
}

# Timing and intermediate EDAC output tests (Cycles 8-19)

@test "full run prints start message with timing" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "pmemtester started"
    # Should mention MB and cores
    assert_output --partial "MB"
    assert_output --partial "core"
}

@test "full run prints Phase 1 start" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "Phase 1"
    assert_output --partial "started"
}

@test "full run prints Phase 1 finished with result and duration" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "Phase 1"
    assert_output --partial "finished"
    assert_output --partial "passed"
    # Duration pattern: Ns or Nm Ns
    [[ "$output" =~ [0-9]+s ]]
}

@test "full run prints Phase 1 failure count" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "FAIL" >&2
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
    assert_output --partial "FAILED"
    # Should show "N of M instances FAILED" in Phase 1 finish line
    assert_output --partial "instances FAILED"
}

@test "full run prints intermediate EDAC result" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "EDAC after Phase 1"
    assert_output --partial "no errors"
}

@test "full run intermediate EDAC shows CE detected" {
    local edac_fixture="${TEST_LOG_DIR}/edac_mid_ce"
    mkdir -p "${edac_fixture}/mc/mc0/csrow0"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ce_count"
    echo "0" > "${edac_fixture}/mc/mc0/csrow0/ue_count"
    export EDAC_BASE="$edac_fixture"

    # Memtester that increments CE counter during run
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
        $TEST_STRESSAPPTEST_OFF
    assert_output --partial "correctable errors"
}

@test "full run prints Phase 2 start with ETA" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "Phase 2"
    assert_output --partial "started"
    assert_output --partial "ETA"
}

@test "full run prints Phase 2 finished with duration" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "Phase 2"
    assert_output --partial "finished"
    [[ "$output" =~ [0-9]+s ]]
}

@test "full run prints total duration" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "Total duration"
}

@test "full run no Phase 2 still prints total duration" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest off
    assert_success
    assert_output --partial "Total duration"
    refute_output --partial "Phase 2"
}

@test "full run Phase 2 with explicit seconds shows ETA" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<MOCK
#!/usr/bin/env bash
echo "args: \$*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-seconds 42 \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "ETA"
}

@test "full run intermediate EDAC creates mid snapshot files" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    local log_dir="${TEST_LOG_DIR}/logs_mid"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
    [[ -f "${log_dir}/edac_counters_mid.txt" ]]
    [[ -f "${log_dir}/edac_messages_mid.txt" ]]
}

# Binary detection info messages

@test "full run prints memtester found message" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "memtester found"
    assert_output --partial "$TEST_MEMTESTER_DIR/memtester"
}

@test "full run prints stressapptest found message when present" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest on \
        --stressapptest-dir "$sat_dir"
    assert_success
    assert_output --partial "stressapptest found"
    assert_output --partial "$sat_dir/stressapptest"
}

@test "full run prints stressapptest not found in auto mode" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest auto \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat"
    assert_success
    assert_output --partial "stressapptest not found"
}

@test "full run stressapptest off prints no detection message" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --stressapptest off
    assert_success
    refute_output --partial "stressapptest found"
    refute_output --partial "stressapptest not found"
}

@test "full run detection messages appear in master.log" {
    local log_dir="${TEST_LOG_DIR}/logs_detect"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
    [[ -f "${log_dir}/master.log" ]]
    grep -q "memtester found" "${log_dir}/master.log"
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
        --allow-ce --color on \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
    assert_output --partial $'\033[33m'
    assert_output --partial "WARNING"
}
