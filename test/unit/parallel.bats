setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    load_lib logging.sh
    load_lib parallel.sh
    TEST_LOG_DIR="$(mktemp -d)"
    init_logs "$TEST_LOG_DIR" 4
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
}

@test "run_memtester_instance success" {
    create_mock memtester 'echo "memtester pass"; exit 0'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR"
    assert_success
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
}

@test "run_memtester_instance failure" {
    create_mock memtester 'echo "memtester FAIL" >&2; exit 1'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR"
    assert_failure
}

@test "run_all_memtesters launches N instances" {
    create_mock memtester 'echo "pass"; exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR"
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_1.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_2.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_3.log" ]]
}

@test "run_all_memtesters single thread" {
    create_mock memtester 'echo "pass"; exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 1 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR"
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
}

@test "wait_and_collect all pass returns 0" {
    create_mock memtester 'echo "pass"; exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    # Call directly (not via run) since MEMTESTER_PIDS must be in same shell
    wait_and_collect "$TEST_LOG_DIR"
    # If we get here without error, the test passes (wait_and_collect returned 0)
}

@test "wait_and_collect one fails returns 1" {
    local counter_file="${TEST_LOG_DIR}/.call_count"
    echo "0" > "$counter_file"
    # Mock that fails on the 2nd invocation
    create_mock memtester 'count=$(cat '"${counter_file}"'); count=$((count+1)); echo "$count" > '"${counter_file}"'; if [ "$count" -eq 2 ]; then exit 1; else echo "pass"; exit 0; fi'

    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    # Expect failure — negate the return
    ! wait_and_collect "$TEST_LOG_DIR"
}

@test "wait_and_collect all fail returns 1" {
    create_mock memtester 'exit 1'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    ! wait_and_collect "$TEST_LOG_DIR"
}

@test "wait_and_collect all pass sets MEMTESTER_FAIL_COUNT to 0" {
    create_mock memtester 'echo "pass"; exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 3 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR"
    [[ "$MEMTESTER_FAIL_COUNT" -eq 0 ]]
}

@test "wait_and_collect one fail sets MEMTESTER_FAIL_COUNT to 1" {
    local counter_file="${TEST_LOG_DIR}/.fail_count_test"
    echo "0" > "$counter_file"
    create_mock memtester 'count=$(cat '"${counter_file}"'); count=$((count+1)); echo "$count" > '"${counter_file}"'; if [ "$count" -eq 2 ]; then exit 1; else echo "pass"; exit 0; fi'

    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 3 "$TEST_LOG_DIR"
    ! wait_and_collect "$TEST_LOG_DIR"
    [[ "$MEMTESTER_FAIL_COUNT" -eq 1 ]]
}
