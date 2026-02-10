setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib logging.sh
    TEST_LOG_DIR="$(mktemp -d)"
}

teardown() {
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
}

@test "init_logs creates directory" {
    local log_dir="${TEST_LOG_DIR}/newlogs"
    run init_logs "$log_dir" 4
    assert_success
    [[ -d "$log_dir" ]]
}

@test "init_logs creates master.log" {
    local log_dir="${TEST_LOG_DIR}/newlogs"
    init_logs "$log_dir" 4
    [[ -f "${log_dir}/master.log" ]]
}

@test "init_logs fails on unwritable path" {
    run init_logs "/proc/nonexistent/logs" 4
    assert_failure
}

@test "log_msg writes timestamped INFO" {
    local logfile="${TEST_LOG_DIR}/test.log"
    log_msg "INFO" "test message" "$logfile"
    run cat "$logfile"
    assert_output --regexp '\[.*\] \[INFO\] test message'
}

@test "log_msg writes timestamped ERROR" {
    local logfile="${TEST_LOG_DIR}/test.log"
    log_msg "ERROR" "fail message" "$logfile"
    run cat "$logfile"
    assert_output --regexp '\[.*\] \[ERROR\] fail message'
}

@test "log_master appends to master.log" {
    init_logs "$TEST_LOG_DIR" 2
    log_master "hello world" "$TEST_LOG_DIR"
    run cat "${TEST_LOG_DIR}/master.log"
    assert_output --regexp 'hello world'
}

@test "log_thread writes to correct file" {
    init_logs "$TEST_LOG_DIR" 4
    log_thread 2 "thread msg" "$TEST_LOG_DIR"
    [[ -f "${TEST_LOG_DIR}/thread_2.log" ]]
    run cat "${TEST_LOG_DIR}/thread_2.log"
    assert_output --regexp 'thread msg'
}

@test "aggregate_logs combines thread logs" {
    init_logs "$TEST_LOG_DIR" 2
    log_thread 0 "first thread" "$TEST_LOG_DIR"
    log_thread 1 "second thread" "$TEST_LOG_DIR"
    aggregate_logs "$TEST_LOG_DIR" 2
    run cat "${TEST_LOG_DIR}/master.log"
    assert_output --partial "first thread"
    assert_output --partial "second thread"
}
