setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib memtester_mgmt.sh
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    [[ -d "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

@test "find_memtester in default location" {
    touch "${TEST_DIR}/memtester"
    chmod +x "${TEST_DIR}/memtester"
    run find_memtester "$TEST_DIR"
    assert_success
    assert_output "${TEST_DIR}/memtester"
}

@test "find_memtester in custom directory" {
    mkdir -p "${TEST_DIR}/custom"
    touch "${TEST_DIR}/custom/memtester"
    chmod +x "${TEST_DIR}/custom/memtester"
    run find_memtester "${TEST_DIR}/custom"
    assert_success
    assert_output "${TEST_DIR}/custom/memtester"
}

@test "find_memtester not found" {
    run find_memtester "$TEST_DIR"
    assert_failure
}

@test "validate_memtester executable file" {
    touch "${TEST_DIR}/memtester"
    chmod +x "${TEST_DIR}/memtester"
    run validate_memtester "${TEST_DIR}/memtester"
    assert_success
}

@test "validate_memtester non-executable" {
    touch "${TEST_DIR}/memtester"
    chmod -x "${TEST_DIR}/memtester"
    run validate_memtester "${TEST_DIR}/memtester"
    assert_failure
}

@test "validate_memtester nonexistent path" {
    run validate_memtester "${TEST_DIR}/nonexistent"
    assert_failure
}
