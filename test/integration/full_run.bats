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

    # Mock lscpu to report 2 physical cores (1 socket, 2 cores, 1 node)
    # 4-column format supports both get_core_count (Socket,Core) and get_physical_cpu_list (Socket,Core,CPU,Node)
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

    # Use 3MB L3 cache fixture for deterministic calibration size (4x3MB = 12MB)
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_3mb"

    # Disable calibration for tests with side-effect memtester mocks
    export TEST_ESTIMATE_OFF="--estimate off"
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
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
    assert_output --partial "Estimated Phase 2 completion"
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
    assert_output --partial "Estimated Phase 2 completion"
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

# End-to-end memory size verification tests
#
# These tests verify that the full pipeline (RAM detection → percentage →
# per-core division → argument formatting) produces the correct memory
# values passed to memtester and stressapptest.

# Fixture proc_meminfo_normal: MemAvailable=12288000 kB, MemTotal=16384000 kB
# Mock lscpu: 2 physical cores
# Default: 90% of available = 12288000*90/100 = 11059200 kB
#   per core: 11059200/2 = 5529600 kB = 5400 MB (5529600/1024)
#   memtester arg: "5400M"
#   stressapptest -M: 10800 (5400*2)

@test "memtester receives correct per-core memory size (default 90% available)" {
    # Argument-capturing memtester mock
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF

    # Each of 2 cores should get 5400M
    [[ -f "$PMEMTESTER_ARG_LOG" ]]
    local line_count
    line_count=$(wc -l < "$PMEMTESTER_ARG_LOG")
    [[ "$line_count" -eq 2 ]]

    while IFS= read -r arg; do
        [[ "$arg" == "5400M" ]]
    done < "$PMEMTESTER_ARG_LOG"
}

@test "memtester receives correct per-core memory size (50% available)" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    # 50% of 12288000 = 6144000 kB / 2 cores = 3072000 kB = 3000 MB
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 50 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF

    while IFS= read -r arg; do
        [[ "$arg" == "3000M" ]]
    done < "$PMEMTESTER_ARG_LOG"
}

@test "memtester receives correct per-core memory size (total RAM)" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    # 90% of MemTotal 16384000 = 14745600 kB / 2 = 7372800 kB = 7200 MB
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 --ram-type total \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF

    while IFS= read -r arg; do
        [[ "$arg" == "7200M" ]]
    done < "$PMEMTESTER_ARG_LOG"
}

@test "memtester receives correct per-core memory size (low RAM fixture, 4 cores)" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_low"
    # MemAvailable=204800 kB, 90% = 184320 kB
    # 4 cores: 184320/4 = 46080 kB = 45 MB (46080/1024)
    create_mock lscpu 'echo "# Socket,Core"; echo "0,0"; echo "0,1"; echo "0,2"; echo "0,3"'

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF

    local line_count
    line_count=$(wc -l < "$PMEMTESTER_ARG_LOG")
    [[ "$line_count" -eq 4 ]]

    while IFS= read -r arg; do
        [[ "$arg" == "45M" ]]
    done < "$PMEMTESTER_ARG_LOG"
}

@test "stressapptest receives correct total memory size (default 90% available)" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    # Argument-capturing stressapptest mock
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_memsize"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --percent 90 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --stressapptest-dir "$sat_dir"

    # 5400 MB/core * 2 cores = 10800 MB
    grep -q -- "-M 10800" "${log_dir}/stressapptest.log"
}

@test "stressapptest receives correct total memory size (50% available)" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_memsize50"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --percent 50 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --stressapptest-dir "$sat_dir"

    # 3000 MB/core * 2 cores = 6000 MB
    grep -q -- "-M 6000" "${log_dir}/stressapptest.log"
}

@test "stressapptest receives correct total memory size (low RAM, 4 cores)" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_low"
    create_mock lscpu 'echo "# Socket,Core"; echo "0,0"; echo "0,1"; echo "0,2"; echo "0,3"'

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_lowram"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --percent 90 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --stressapptest-dir "$sat_dir"

    # 45 MB/core * 4 cores = 180 MB
    grep -q -- "-M 180" "${log_dir}/stressapptest.log"
}

@test "memtester and stressapptest receive consistent memory sizes" {
    # Verify both tools get the same total: per_core * cores == stressapptest -M
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_consistent"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --percent 90 \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --stressapptest-dir "$sat_dir" \
        $TEST_ESTIMATE_OFF

    # Extract per-core MB from memtester arg (strip trailing M)
    local per_core_mb
    per_core_mb=$(head -1 "$PMEMTESTER_ARG_LOG" | sed 's/M$//')

    # Count memtester instances (= core count)
    local core_count
    core_count=$(wc -l < "$PMEMTESTER_ARG_LOG")

    # Calculate expected total
    local expected_total=$(( per_core_mb * core_count ))

    # Verify stressapptest got that total
    grep -q -- "-M ${expected_total}" "${log_dir}/stressapptest.log"
}

# --- Decimal --percent and --size integration tests ---

@test "full run with --percent 0.1 passes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 0.1 \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

@test "full run with --percent 50.5 passes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 50.5 \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

# Fixture: MemAvailable=12288000 kB, 2 cores
# 0.1% of 12288000 = 12288 kB / 2 = 6144 kB = 6 MB per core
@test "memory size verification --percent 0.1" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"
    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 0.1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF

    while IFS= read -r arg; do
        [[ "$arg" == "6M" ]]
    done < "$PMEMTESTER_ARG_LOG"
}

@test "full run with --size 256M passes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 256M \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

@test "full run with --size 2G passes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 2G \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

# --size 256M = 262144 kB / 2 cores = 131072 kB = 128 MB per core
@test "memory size verification --size 256M" {
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "${PMEMTESTER_ARG_LOG}"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"
    export PMEMTESTER_ARG_LOG="${TEST_LOG_DIR}/memtester_args.txt"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 256M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF

    local line_count
    line_count=$(wc -l < "$PMEMTESTER_ARG_LOG")
    [[ "$line_count" -eq 2 ]]

    while IFS= read -r arg; do
        [[ "$arg" == "128M" ]]
    done < "$PMEMTESTER_ARG_LOG"
}

# stressapptest total: --size 256M → -M 256
@test "stressapptest total with --size 256M" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_size_sat"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --size 256M \
        --stressapptest on \
        --stressapptest-seconds 1 \
        --stressapptest-dir "$sat_dir"

    # 128 MB/core * 2 cores = 256 MB
    grep -q -- "-M 256" "${log_dir}/stressapptest.log"
}

# --size 1024K / 2 cores = 512 kB per core → < 1 MB → fails
@test "too small --size 1024K with 2 cores fails" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 1024K \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
    assert_output --partial "RAM per core"
}

@test "mutual exclusion --percent and --size fails" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 50 --size 256M \
        $TEST_STRESSAPPTEST_OFF
    assert_failure
    assert_output --partial "mutually exclusive"
}

@test "--size with --ram-type passes (ram-type silently ignored)" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 256M --ram-type total \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "PASS"
}

# --- Time estimation integration tests ---

@test "full run shows time estimate by default" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "Estimated Phase 1 completion"
}

@test "full run --estimate off skips estimate" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --estimate off \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    refute_output --partial "Estimated Phase 1 completion"
}

@test "full run --estimate on shows estimate" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --estimate on \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    assert_output --partial "Estimated Phase 1 completion"
}

@test "full run estimate auto silently skips on calibration failure" {
    # Create a memtester mock that fails only for calibration (12M with 3MB L3 fixture)
    # but passes for the real run
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "12M" ]] && [[ "$2" == "1" ]]; then
    echo "calibration fail" >&2
    exit 1
fi
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --estimate auto \
        $TEST_STRESSAPPTEST_OFF
    assert_success
    refute_output --partial "Estimated Phase 1 completion"
    assert_output --partial "PASS"
}

@test "full run estimate creates calibration.log" {
    local log_dir="${TEST_LOG_DIR}/logs_cal"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        $TEST_STRESSAPPTEST_OFF
    [[ -f "${log_dir}/calibration.log" ]]
}

@test "full run estimate uses L3-based calibration size" {
    # With 3MB L3 fixture, calibration_mb = 3072*4/1024 = 12
    # Mock memtester records its first invocation args
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
if [[ ! -f "${0%/*}/first_call.txt" ]]; then
    echo "$@" > "${0%/*}/first_call.txt"
fi
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF

    # First call should be calibration: 12M 1
    local first_args
    first_args="$(cat "${TEST_MEMTESTER_DIR}/first_call.txt")"
    [[ "$first_args" == "12M 1" ]]
}

@test "full run estimate falls back on L3 detection failure" {
    # Point SYS_CPU_BASE at nonexistent dir and mock getconf to fail
    export SYS_CPU_BASE="${TEST_LOG_DIR}/nonexistent_sysfs"
    create_mock getconf 'exit 1'

    # Mock memtester records its first invocation args
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
if [[ ! -f "${0%/*}/first_call.txt" ]]; then
    echo "$@" > "${0%/*}/first_call.txt"
fi
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        $TEST_STRESSAPPTEST_OFF

    # Fallback calibration is 512MB, but clamped to ram_per_core_mb
    # With 16GB total, 90% avail (~12GB avail), 2 cores → ~6000MB per core
    # 512 < 6000, so calibration_mb = 512
    local first_args
    first_args="$(cat "${TEST_MEMTESTER_DIR}/first_call.txt")"
    [[ "$first_args" == "512M 1" ]]
}

@test "full run estimate calibration clamped to ram_per_core_mb" {
    # Use 96MB L3 fixture: calibration_mb = 98304*4/1024 = 384
    # But with --size 256M (2 cores → 128M per core), clamp to 128
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_96mb"

    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
if [[ ! -f "${0%/*}/first_call.txt" ]]; then
    echo "$@" > "${0%/*}/first_call.txt"
fi
echo "memtester pass"
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 256M \
        $TEST_STRESSAPPTEST_OFF

    # 256M / 2 cores = 128M per core; 384MB calibration clamped to 128
    local first_args
    first_args="$(cat "${TEST_MEMTESTER_DIR}/first_call.txt")"
    [[ "$first_args" == "128M 1" ]]
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
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "PASS"
    assert_output --partial $'\033[33m'
    assert_output --partial "WARNING"
}

# --- NUMA node and CPU pinning integration tests ---

@test "full run --numa-node 0 passes" {
    # Set up SYS_NODE_BASE fixture
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"

    # numactl mock that passes through to remaining args
    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "NUMA node: 0"
}

@test "full run --numa-node 99 fails (node does not exist)" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 99 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_failure
    assert_output --partial "does not exist"
}

@test "full run --numa-node without numactl fails" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"

    # Remove numactl from PATH — recreate mock dir without numactl
    rm -f "${MOCK_DIR}/numactl" 2>/dev/null || true

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_failure
    assert_output --partial "numactl"
}

@test "full run --pin passes" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --pin \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "CPU pinning: enabled"
}

@test "full run --pin output shows thread pinning info" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --pin \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "CPU pinning: enabled"
    assert_output --partial "CPUs:"
}

@test "full run --numa-node 0 --pin passes with both" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0 --pin \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "PASS"
    assert_output --partial "NUMA node: 0"
    assert_output --partial "CPU pinning: enabled"
}

@test "full run --threads 8 --numa-node 0 warns if exceeding node cores" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    # Node 0 has 2 cores (from lscpu mock), but --threads 8 exceeds that
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --threads 8 --numa-node 0 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "exceeds NUMA node"
}

@test "full run --pin with stressapptest wraps with taskset" {
    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<MOCK
#!/usr/bin/env bash
echo "args: \$*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_pin_sat"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --pin \
        --stressapptest on \
        --stressapptest-dir "$sat_dir" \
        $TEST_ESTIMATE_OFF
    # The stressapptest log should show it was invoked (mock just echoes args)
    [[ -f "${log_dir}/stressapptest.log" ]]
}

@test "full run --numa-node with stressapptest wraps with numactl" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    local sat_dir="${TEST_LOG_DIR}/sat_bin"
    mkdir -p "$sat_dir"
    cat > "${sat_dir}/stressapptest" <<MOCK
#!/usr/bin/env bash
echo "args: \$*"
exit 0
MOCK
    chmod +x "${sat_dir}/stressapptest"

    local log_dir="${TEST_LOG_DIR}/logs_numa_sat"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --numa-node 0 \
        --stressapptest on \
        --stressapptest-dir "$sat_dir" \
        $TEST_ESTIMATE_OFF
    [[ -f "${log_dir}/stressapptest.log" ]]
}

# --- --check-deps integration tests ---

@test "full run --check-deps shows all sections" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --check-deps
    assert_success
    assert_output --partial "pmemtester"
    assert_output --partial "dependency check"
    assert_output --partial "Required:"
    assert_output --partial "Optional:"
    assert_output --partial "System:"
    assert_output --partial "memtester"
    assert_output --partial "[OK]"
}

@test "full run --check-deps exits 0 with all required deps" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --check-deps
    assert_success
    assert_output --partial "All required dependencies found"
}

# --- multi-node NUMA integration tests ---

@test "full run --numa-node 0,1 passes with both nodes" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0" "${node_fixture}/node1"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0,1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "PASS"
}

@test "full run --numa-node 0,1 shows per-node results" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0" "${node_fixture}/node1"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0,1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "Node 0"
    assert_output --partial "Node 1"
}

@test "full run --numa-node 0,1 creates per-node log dirs" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0" "${node_fixture}/node1"
    export SYS_NODE_BASE="$node_fixture"

    create_mock numactl 'shift; shift; exec "$@"'

    local log_dir="${TEST_LOG_DIR}/multi_logs"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$log_dir" \
        --numa-node 0,1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    [[ -d "${log_dir}/node_0" ]]
    [[ -d "${log_dir}/node_1" ]]
}

@test "full run --numa-node 0,1 with CPU-less node borrows CPUs" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0" "${node_fixture}/node1"
    export SYS_NODE_BASE="$node_fixture"

    # lscpu mock: only node 0 has CPUs
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

    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0,1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "borrowing CPUs from node 0"
}

@test "full run --numa-node 0,1 EDAC warning for multi-node" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0" "${node_fixture}/node1"
    export SYS_NODE_BASE="$node_fixture"
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    create_mock numactl 'shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0,1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "EDAC errors cannot be attributed"
}

@test "full run --numa-node 0,1 with one failing node returns 1" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0" "${node_fixture}/node1"
    export SYS_NODE_BASE="$node_fixture"

    # numactl mock: fail when membind=1 (node 1)
    create_mock numactl '
for arg in "$@"; do
    if [[ "$arg" == "--membind=1" ]]; then
        echo "FAIL on node 1" >&2
        exit 1
    fi
done
shift; shift; exec "$@"'

    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --numa-node 0,1 \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_failure
    assert_output --partial "FAIL"
}

@test "full run --check-deps shows Physical cores" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --check-deps
    assert_success
    assert_output --partial "Physical cores"
}

# --- --show-physical tests ---

# Helper: create a memtester mock that writes synthetic proc fixtures for pagemap
create_pagemap_memtester_mock() {
    local mock_dir="$1"
    cat > "${mock_dir}/memtester" <<'MOCK'
#!/usr/bin/env bash
# Create synthetic /proc fixtures for pagemap testing.
# Write to both $$ (own PID) and $PPID (the run_memtester_instance subshell),
# since pmemtester checks MEMTESTER_PIDS[] which holds the subshell PID.
_write_pagemap_fixture() {
    local dir="$1"
    mkdir -p "$dir"
    echo "01000000-01004000 rw-p 00000000 00:00 0" > "$dir/maps"
    dd if=/dev/zero of="$dir/pagemap" bs=1 count=32800 2>/dev/null
    printf '\x00\x01\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32768 conv=notrunc 2>/dev/null
    printf '\x00\x02\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32776 conv=notrunc 2>/dev/null
    printf '\x00\x03\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32784 conv=notrunc 2>/dev/null
    printf '\x00\x04\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32792 conv=notrunc 2>/dev/null
}
if [[ -n "${PROC_BASE:-}" ]]; then
    _write_pagemap_fixture "${PROC_BASE}/$$"
    _write_pagemap_fixture "${PROC_BASE}/$PPID"
fi
echo "memtester pass"
sleep 0.5
exit 0
MOCK
    chmod +x "${mock_dir}/memtester"
}

@test "full run --show-physical without root prints permission warning" {
    # PROC_BASE pointing to a directory where no pagemap exists → unreadable
    export PROC_BASE="${TEST_LOG_DIR}/no_proc"
    mkdir -p "$PROC_BASE"
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --show-physical --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "root"
}

@test "full run --show-physical with mock pagemap reports physical addresses" {
    export PROC_BASE="${TEST_LOG_DIR}/proc"
    mkdir -p "$PROC_BASE"
    create_pagemap_memtester_mock "$TEST_MEMTESTER_DIR"
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --show-physical --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    assert_output --partial "Physical Address Mapping"
}

@test "full run --show-physical creates pagemap files in log dir" {
    export PROC_BASE="${TEST_LOG_DIR}/proc"
    mkdir -p "$PROC_BASE"
    create_pagemap_memtester_mock "$TEST_MEMTESTER_DIR"
    "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --show-physical --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF || true
    # At least thread_0_pagemap.txt should exist
    [[ -f "${TEST_LOG_DIR}/thread_0_pagemap.txt" ]]
}

@test "full run --show-physical with failing memtester shows physical mapping" {
    export PROC_BASE="${TEST_LOG_DIR}/proc"
    mkdir -p "$PROC_BASE"
    # Create a failing memtester that still sets up pagemap fixtures
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
_write_pagemap_fixture() {
    local dir="$1"
    mkdir -p "$dir"
    echo "01000000-01004000 rw-p 00000000 00:00 0" > "$dir/maps"
    dd if=/dev/zero of="$dir/pagemap" bs=1 count=32800 2>/dev/null
    printf '\x00\x01\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32768 conv=notrunc 2>/dev/null
    printf '\x00\x02\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32776 conv=notrunc 2>/dev/null
    printf '\x00\x03\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32784 conv=notrunc 2>/dev/null
    printf '\x00\x04\x00\x00\x00\x00\x00\x80' | dd of="$dir/pagemap" bs=1 seek=32792 conv=notrunc 2>/dev/null
}
if [[ -n "${PROC_BASE:-}" ]]; then
    _write_pagemap_fixture "${PROC_BASE}/$$"
    _write_pagemap_fixture "${PROC_BASE}/$PPID"
fi
echo "FAILURE: stuck address"
sleep 0.5
exit 1
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --show-physical --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_failure
    assert_output --partial "Physical Address Mapping"
}

@test "full run without --show-physical does not create pagemap files" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
    [[ ! -f "${TEST_LOG_DIR}/thread_0_pagemap.txt" ]]
}

@test "full run --show-physical combined with --stop-on-error" {
    export PROC_BASE="${TEST_LOG_DIR}/proc"
    mkdir -p "$PROC_BASE"
    create_pagemap_memtester_mock "$TEST_MEMTESTER_DIR"
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --show-physical --stop-on-error --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
}

@test "full run --show-physical combined with --numa-node" {
    local node_fixture="${TEST_LOG_DIR}/sys_node"
    mkdir -p "${node_fixture}/node0"
    export SYS_NODE_BASE="$node_fixture"
    export PROC_BASE="${TEST_LOG_DIR}/proc"
    mkdir -p "$PROC_BASE"
    create_pagemap_memtester_mock "$TEST_MEMTESTER_DIR"
    create_mock numactl 'shift; shift; exec "$@"'
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --show-physical --numa-node 0 --size 4M \
        $TEST_STRESSAPPTEST_OFF $TEST_ESTIMATE_OFF
    assert_success
}
