setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    load_lib logging.sh
    load_lib timing.sh
    TEST_LOG_DIR="$(mktemp -d)"
    init_logs "$TEST_LOG_DIR" 1
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
}

# Cycle 1: format_duration

@test "format_duration 0 returns 0s" {
    run format_duration 0
    assert_success
    assert_output "0s"
}

@test "format_duration 45 returns 45s" {
    run format_duration 45
    assert_success
    assert_output "45s"
}

@test "format_duration 60 returns 1m 0s" {
    run format_duration 60
    assert_success
    assert_output "1m 0s"
}

@test "format_duration 135 returns 2m 15s" {
    run format_duration 135
    assert_success
    assert_output "2m 15s"
}

@test "format_duration 3661 returns 61m 1s" {
    run format_duration 3661
    assert_success
    assert_output "61m 1s"
}

# Cycle 2: format_wallclock

@test "format_wallclock returns YYYY-MM-DD HH:MM:SS pattern" {
    run format_wallclock
    assert_success
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_wallclock returns non-empty string" {
    run format_wallclock
    assert_success
    [[ -n "$output" ]]
}

# Cycle 3: format_eta

@test "format_eta 60 returns YYYY-MM-DD HH:MM:SS pattern" {
    run format_eta 60
    assert_success
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_eta 0 returns a timestamp" {
    run format_eta 0
    assert_success
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

# Cycle 4: print_status

@test "print_status prints to stdout with timestamp prefix" {
    run print_status "test message" "$TEST_LOG_DIR"
    assert_success
    [[ "$output" =~ ^\[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\]\ test\ message$ ]]
}

@test "print_status writes to master.log" {
    print_status "log check message" "$TEST_LOG_DIR"
    grep -q "log check message" "${TEST_LOG_DIR}/master.log"
}

# Cycle 5: format_phase_result

@test "format_phase_result all pass" {
    run format_phase_result 4 0
    assert_success
    assert_output "all 4 instances passed"
}

@test "format_phase_result 1 of 4 failed" {
    run format_phase_result 4 1
    assert_success
    assert_output "1 of 4 instances FAILED"
}

@test "format_phase_result all failed" {
    run format_phase_result 4 4
    assert_success
    assert_output "4 of 4 instances FAILED"
}

@test "format_phase_result single instance all pass" {
    run format_phase_result 1 0
    assert_success
    assert_output "all 1 instances passed"
}

# Cycle 6: format_edac_summary

@test "format_edac_summary none" {
    run format_edac_summary "none"
    assert_success
    assert_output "no errors detected"
}

@test "format_edac_summary ce_only" {
    run format_edac_summary "ce_only"
    assert_success
    assert_output "correctable errors (CE) detected"
}

@test "format_edac_summary ue_only" {
    run format_edac_summary "ue_only"
    assert_success
    assert_output "uncorrectable errors (UE) detected"
}

@test "format_edac_summary ce_and_ue" {
    run format_edac_summary "ce_and_ue"
    assert_success
    assert_output "correctable and uncorrectable errors detected"
}
