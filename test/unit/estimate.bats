setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    load_lib logging.sh
    load_lib timing.sh
    load_lib unit_convert.sh
    load_lib estimate.sh
}

# --- estimate_duration tests ---

@test "estimate_duration 1s cal 1MB target 256MB 1iter = 256" {
    run estimate_duration 1 1 256 1
    assert_success
    assert_output "256"
}

@test "estimate_duration 2s cal 1MB target 128MB 3iter = 768" {
    run estimate_duration 2 1 128 3
    assert_success
    assert_output "768"
}

@test "estimate_duration 1s cal 1MB target 1MB 1iter = 1 (identity)" {
    run estimate_duration 1 1 1 1
    assert_success
    assert_output "1"
}

@test "estimate_duration 0s calibration returns 0" {
    run estimate_duration 0 1 256 1
    assert_success
    assert_output "0"
}

@test "estimate_duration 2s cal 128MB target 1024MB 1iter = 16" {
    # 2 * 1024 * 1 / 128 = 16
    run estimate_duration 2 128 1024 1
    assert_success
    assert_output "16"
}

@test "estimate_duration 5s cal 512MB target 512MB 1iter = 5 (identity when cal=target)" {
    # 5 * 512 * 1 / 512 = 5
    run estimate_duration 5 512 512 1
    assert_success
    assert_output "5"
}

@test "estimate_duration 3s cal 64MB target 8192MB 3iter = 1152" {
    # 3 * 8192 * 3 / 64 = 1152
    run estimate_duration 3 64 8192 3
    assert_success
    assert_output "1152"
}

@test "estimate_duration large values no overflow" {
    # 10s * 100000MB * 100iter / 500MB = 200000
    run estimate_duration 10 500 100000 100
    assert_success
    assert_output "200000"
}

# --- run_calibration tests ---

@test "run_calibration succeeds with mock memtester" {
    setup_mock_dir
    create_mock memtester 'echo "memtester calibration pass"; exit 0'
    local log_dir
    log_dir="$(mktemp -d)"

    run run_calibration "${MOCK_DIR}/memtester" "$log_dir" 12
    assert_success
    # Output should be a non-negative integer (seconds)
    [[ "$output" =~ ^[0-9]+$ ]]

    rm -rf "$log_dir"
    teardown_mock_dir
}

@test "run_calibration creates calibration.log" {
    setup_mock_dir
    create_mock memtester 'echo "memtester calibration output"; exit 0'
    local log_dir
    log_dir="$(mktemp -d)"

    run_calibration "${MOCK_DIR}/memtester" "$log_dir" 12
    [[ -f "${log_dir}/calibration.log" ]]

    rm -rf "$log_dir"
    teardown_mock_dir
}

@test "run_calibration logs to calibration.log" {
    setup_mock_dir
    create_mock memtester 'echo "calibration test output"; exit 0'
    local log_dir
    log_dir="$(mktemp -d)"

    run_calibration "${MOCK_DIR}/memtester" "$log_dir" 12
    # Log file should contain memtester output
    grep -q "calibration test output" "${log_dir}/calibration.log"

    rm -rf "$log_dir"
    teardown_mock_dir
}

@test "run_calibration failure returns non-zero" {
    setup_mock_dir
    create_mock memtester 'echo "memtester failed" >&2; exit 1'
    local log_dir
    log_dir="$(mktemp -d)"

    run run_calibration "${MOCK_DIR}/memtester" "$log_dir" 12
    assert_failure

    rm -rf "$log_dir"
    teardown_mock_dir
}

@test "run_calibration uses specified calibration size" {
    setup_mock_dir
    # Mock memtester that records its arguments
    create_mock memtester 'echo "$@" > "${0%/*}/memtester_args.txt"; exit 0'
    local log_dir
    log_dir="$(mktemp -d)"

    run_calibration "${MOCK_DIR}/memtester" "$log_dir" 48
    # memtester should have been called with "48M 1"
    local args
    args="$(cat "${MOCK_DIR}/memtester_args.txt")"
    [[ "$args" == "48M 1" ]]

    rm -rf "$log_dir"
    teardown_mock_dir
}

# --- print_estimate tests ---

@test "print_estimate shows estimated completion" {
    local log_dir
    log_dir="$(mktemp -d)"
    : > "${log_dir}/master.log"

    run print_estimate 120 "$log_dir"
    assert_success
    assert_output --partial "Estimated completion"

    rm -rf "$log_dir"
}

@test "print_estimate shows ETA timestamp" {
    local log_dir
    log_dir="$(mktemp -d)"
    : > "${log_dir}/master.log"

    run print_estimate 60 "$log_dir"
    assert_success
    # ETA line should contain a date-like pattern (YYYY-MM-DD)
    assert_output --partial "ETA:"

    rm -rf "$log_dir"
}

@test "print_estimate writes to master.log" {
    local log_dir
    log_dir="$(mktemp -d)"
    : > "${log_dir}/master.log"

    print_estimate 90 "$log_dir"
    grep -q "Estimated completion" "${log_dir}/master.log"

    rm -rf "$log_dir"
}

@test "print_estimate uses format_duration" {
    local log_dir
    log_dir="$(mktemp -d)"
    : > "${log_dir}/master.log"

    # 90 seconds should show "1m 30s" from format_duration
    run print_estimate 90 "$log_dir"
    assert_success
    assert_output --partial "1m 30s"

    rm -rf "$log_dir"
}
