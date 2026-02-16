setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib logging.sh
    load_lib stressapptest_mgmt.sh
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    [[ -d "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

@test "find_stressapptest in default location" {
    touch "${TEST_DIR}/stressapptest"
    chmod +x "${TEST_DIR}/stressapptest"
    run find_stressapptest "$TEST_DIR"
    assert_success
    assert_output "${TEST_DIR}/stressapptest"
}

@test "find_stressapptest in custom directory" {
    mkdir -p "${TEST_DIR}/custom"
    touch "${TEST_DIR}/custom/stressapptest"
    chmod +x "${TEST_DIR}/custom/stressapptest"
    run find_stressapptest "${TEST_DIR}/custom"
    assert_success
    assert_output "${TEST_DIR}/custom/stressapptest"
}

@test "find_stressapptest not found" {
    run find_stressapptest "$TEST_DIR"
    assert_failure
}

@test "validate_stressapptest executable file" {
    touch "${TEST_DIR}/stressapptest"
    chmod +x "${TEST_DIR}/stressapptest"
    run validate_stressapptest "${TEST_DIR}/stressapptest"
    assert_success
}

@test "validate_stressapptest non-executable" {
    touch "${TEST_DIR}/stressapptest"
    chmod -x "${TEST_DIR}/stressapptest"
    run validate_stressapptest "${TEST_DIR}/stressapptest"
    assert_failure
}

@test "validate_stressapptest nonexistent path" {
    run validate_stressapptest "${TEST_DIR}/nonexistent"
    assert_failure
}

# run_stressapptest tests

@test "run_stressapptest success exit code" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    assert_success
}

@test "run_stressapptest failure exit code" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: FAIL" >&2
exit 1
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    assert_failure
}

@test "run_stressapptest creates log file" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    [[ -f "${TEST_DIR}/stressapptest.log" ]]
}

@test "run_stressapptest passes correct arguments" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 60 512 "$TEST_DIR"
    grep -q -- "-s 60" "${TEST_DIR}/stressapptest.log"
    grep -q -- "-M 512" "${TEST_DIR}/stressapptest.log"
    ! grep -q -- "-m" "${TEST_DIR}/stressapptest.log"
}

@test "run_stressapptest does not pass -m flag (let stressapptest auto-detect)" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "args: $*"
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    # stressapptest auto-detects thread count from logical CPUs
    ! grep -q -- "-m" "${TEST_DIR}/stressapptest.log"
}

@test "run_stressapptest logs start to master log" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    grep -q "stressapptest" "${TEST_DIR}/master.log"
    grep -q "Starting" "${TEST_DIR}/master.log"
}

@test "run_stressapptest logs PASSED to master log on success" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: PASS"
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    grep -q "PASSED" "${TEST_DIR}/master.log"
}

@test "run_stressapptest logs FAILED to master log on failure" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "Status: FAIL" >&2
exit 1
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR" || true
    grep -q "FAILED" "${TEST_DIR}/master.log"
}

@test "run_stressapptest captures stderr in log" {
    cat > "${TEST_DIR}/stressapptest" <<'MOCK'
#!/usr/bin/env bash
echo "stdout line"
echo "stderr error" >&2
exit 0
MOCK
    chmod +x "${TEST_DIR}/stressapptest"
    init_logs "$TEST_DIR" 0
    run_stressapptest "${TEST_DIR}/stressapptest" 10 256 "$TEST_DIR"
    grep -q "stderr error" "${TEST_DIR}/stressapptest.log"
}
