setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib cli.sh
}

@test "parse_args defaults" {
    parse_args
    [[ "$PERCENT" == "90" ]]
    [[ "$RAM_TYPE" == "available" ]]
    [[ "$MEMTESTER_DIR" == "/usr/local/bin" ]]
    [[ "$ITERATIONS" == "1" ]]
}

@test "parse_args --percent 80" {
    parse_args --percent 80
    [[ "$PERCENT" == "80" ]]
}

@test "parse_args --ram-type total" {
    parse_args --ram-type total
    [[ "$RAM_TYPE" == "total" ]]
}

@test "parse_args --ram-type free" {
    parse_args --ram-type free
    [[ "$RAM_TYPE" == "free" ]]
}

@test "parse_args --memtester-dir custom" {
    parse_args --memtester-dir /usr/bin
    [[ "$MEMTESTER_DIR" == "/usr/bin" ]]
}

@test "parse_args --log-dir custom" {
    parse_args --log-dir /tmp/logs
    [[ "$LOG_DIR" == "/tmp/logs" ]]
}

@test "parse_args --iterations 3" {
    parse_args --iterations 3
    [[ "$ITERATIONS" == "3" ]]
}

@test "parse_args --version" {
    pmemtester_version="0.1"
    run parse_args --version
    assert_success
    assert_output --partial "pmemtester 0.1"
}

@test "parse_args --help" {
    run parse_args --help
    assert_success
    assert_output --partial "Usage"
}

@test "parse_args unknown flag fails" {
    run parse_args --bogus
    assert_failure
}

@test "parse_args multiple flags" {
    parse_args --percent 80 --ram-type total --iterations 5
    [[ "$PERCENT" == "80" ]]
    [[ "$RAM_TYPE" == "total" ]]
    [[ "$ITERATIONS" == "5" ]]
}

@test "validate_args percent zero fails" {
    PERCENT=0 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=1
    run validate_args
    assert_failure
}

@test "validate_args percent 101 fails" {
    PERCENT=101 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=1
    run validate_args
    assert_failure
}

@test "validate_args invalid ram type fails" {
    PERCENT=90 RAM_TYPE=bogus MEMTESTER_DIR=/usr/local/bin ITERATIONS=1
    run validate_args
    assert_failure
}

@test "validate_args iterations zero fails" {
    PERCENT=90 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=0
    run validate_args
    assert_failure
    assert_output --partial "iterations"
}

@test "validate_args valid defaults passes" {
    PERCENT=90 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=1
    run validate_args
    assert_success
}

@test "validate_args valid ram-type total passes" {
    PERCENT=90 RAM_TYPE=total MEMTESTER_DIR=/usr/local/bin ITERATIONS=1
    run validate_args
    assert_success
}

@test "validate_args valid ram-type free passes" {
    PERCENT=90 RAM_TYPE=free MEMTESTER_DIR=/usr/local/bin ITERATIONS=1
    run validate_args
    assert_success
}

@test "usage outputs to stderr" {
    run usage
    assert_success
    assert_output --partial "Usage"
}
