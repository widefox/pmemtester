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

# --- kill_all_memtesters tests ---

@test "kill_all_memtesters with empty PID list does nothing" {
    MEMTESTER_PIDS=()
    # Should not fail even with no PIDs
    kill_all_memtesters "$TEST_LOG_DIR"
}

@test "kill_all_memtesters kills running processes" {
    # Start a long-running background process
    sleep 60 &
    local pid=$!
    MEMTESTER_PIDS=("$pid")

    kill_all_memtesters "$TEST_LOG_DIR"

    # Process should be gone
    ! kill -0 "$pid" 2>/dev/null
}

@test "kill_all_memtesters waits for processes to exit" {
    # A process that ignores SIGTERM briefly then exits
    ( trap '' TERM; sleep 1 ) &
    local pid=$!
    MEMTESTER_PIDS=("$pid")

    kill_all_memtesters "$TEST_LOG_DIR"

    # After kill_all_memtesters returns, the PID must not be running
    ! kill -0 "$pid" 2>/dev/null
}

# --- wait_and_collect stop_on_error tests ---

@test "wait_and_collect stop_on_error=0 waits for all threads" {
    # All 4 fail — without stop-on-error, wait for all
    create_mock memtester 'sleep 0.1; exit 1'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    ! wait_and_collect "$TEST_LOG_DIR" 0
    [[ "$MEMTESTER_FAIL_COUNT" -eq 4 ]]
}

@test "wait_and_collect stop_on_error=1 stops after first failure" {
    local flag_file="${TEST_LOG_DIR}/.order"
    echo "0" > "$flag_file"
    create_mock memtester 'n=$(cat '"\"$flag_file\""'); n=$((n+1)); echo "$n" > '"\"$flag_file\""'; if [ "$n" -eq 1 ]; then exit 1; else sleep 30; exit 0; fi'

    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 4 "$TEST_LOG_DIR"
    ! wait_and_collect "$TEST_LOG_DIR" 1
    [[ "$STOP_ON_ERROR_TRIGGERED" == "memtester" ]]
}

@test "wait_and_collect stop_on_error=1 all pass returns 0" {
    create_mock memtester 'exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 3 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR" 1
    [[ "$STOP_ON_ERROR_TRIGGERED" == "" ]]
}

@test "wait_and_collect no arg defaults to stop_on_error=0" {
    create_mock memtester 'exit 0'
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 2 "$TEST_LOG_DIR"
    # Should work without second argument (backwards compat)
    wait_and_collect "$TEST_LOG_DIR"
}

# --- CPU pinning and NUMA wrapping tests ---

@test "run_memtester_instance without cpu_id or numa_node runs directly" {
    create_mock memtester 'echo "args: $*"; exit 0'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR" "" ""
    assert_success
    # Should contain memtester output, no taskset/numactl
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    ! grep -q "taskset" "${TEST_LOG_DIR}/thread_0.log"
    ! grep -q "numactl" "${TEST_LOG_DIR}/thread_0.log"
}

@test "run_memtester_instance with cpu_id wraps with taskset" {
    local wrapper_log="${TEST_LOG_DIR}/wrapper.log"
    create_mock taskset 'echo "TASKSET: $*" >> '"${wrapper_log}"'; shift; shift; exec "$@"'
    create_mock memtester 'echo "memtester ran"; exit 0'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR" "3" ""
    assert_success
    [[ -f "$wrapper_log" ]]
    grep -q "TASKSET:.*-c 3" "$wrapper_log"
}

@test "run_memtester_instance with numa_node wraps with numactl" {
    local wrapper_log="${TEST_LOG_DIR}/wrapper.log"
    create_mock numactl 'echo "NUMACTL: $*" >> '"${wrapper_log}"'; shift; shift; exec "$@"'
    create_mock memtester 'echo "memtester ran"; exit 0'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR" "" "1"
    assert_success
    [[ -f "$wrapper_log" ]]
    grep -q "NUMACTL:.*--cpunodebind=1 --membind=1" "$wrapper_log"
}

@test "run_memtester_instance with both wraps numactl then taskset" {
    local wrapper_log="${TEST_LOG_DIR}/wrapper.log"
    create_mock numactl 'echo "NUMACTL: $*" >> '"${wrapper_log}"'; shift; shift; exec "$@"'
    create_mock taskset 'echo "TASKSET: $*" >> '"${wrapper_log}"'; shift; shift; exec "$@"'
    create_mock memtester 'echo "memtester ran"; exit 0'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR" "4" "0"
    assert_success
    [[ -f "$wrapper_log" ]]
    grep -q "NUMACTL:" "$wrapper_log"
    grep -q "TASKSET:" "$wrapper_log"
}

@test "run_memtester_instance with empty strings runs directly" {
    create_mock memtester 'echo "direct run"; exit 0'
    run run_memtester_instance "${MOCK_DIR}/memtester" "256M" 1 0 "$TEST_LOG_DIR" "" ""
    assert_success
}

@test "run_all_memtesters with CPU_LIST passes cpu_id per thread" {
    local wrapper_log="${TEST_LOG_DIR}/wrapper.log"
    : > "$wrapper_log"
    create_mock taskset 'echo "TASKSET: $*" >> '"${wrapper_log}"'; shift; shift; exec "$@"'
    create_mock memtester 'echo "pass"; exit 0'
    CPU_LIST=(0 2 4)
    NUMA_NODE=""
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 3 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR"
    grep -q "TASKSET:.*-c 0" "$wrapper_log"
    grep -q "TASKSET:.*-c 2" "$wrapper_log"
    grep -q "TASKSET:.*-c 4" "$wrapper_log"
}

@test "run_all_memtesters with empty CPU_LIST and NUMA_NODE runs without wrapping" {
    create_mock memtester 'echo "pass"; exit 0'
    CPU_LIST=()
    NUMA_NODE=""
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 2 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR"
    [[ -f "${TEST_LOG_DIR}/thread_0.log" ]]
    [[ -f "${TEST_LOG_DIR}/thread_1.log" ]]
}

@test "run_all_memtesters with NUMA_NODE wraps all threads" {
    local wrapper_log="${TEST_LOG_DIR}/wrapper.log"
    : > "$wrapper_log"
    create_mock numactl 'echo "NUMACTL: $*" >> '"${wrapper_log}"'; shift; shift; exec "$@"'
    create_mock memtester 'echo "pass"; exit 0'
    CPU_LIST=()
    NUMA_NODE="1"
    run_all_memtesters "${MOCK_DIR}/memtester" "256M" 1 2 "$TEST_LOG_DIR"
    wait_and_collect "$TEST_LOG_DIR"
    # Both threads should be wrapped with numactl
    local numactl_count
    numactl_count=$(grep -c "NUMACTL:" "$wrapper_log")
    [[ "$numactl_count" -eq 2 ]]
}
