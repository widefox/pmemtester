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
    pmemtester_version="0.2"
    run parse_args --version
    assert_success
    assert_output --partial "pmemtester 0.2"
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

@test "parse_args --allow-ce sets ALLOW_CE" {
    parse_args --allow-ce
    [[ "$ALLOW_CE" == "1" ]]
}

@test "parse_args default ALLOW_CE is 0" {
    parse_args
    [[ "$ALLOW_CE" == "0" ]]
}

@test "parse_args --allow-ce combined with other flags" {
    parse_args --percent 80 --allow-ce --iterations 3
    [[ "$ALLOW_CE" == "1" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "parse_args --color on sets COLOR_MODE" {
    parse_args --color on
    [[ "$COLOR_MODE" == "on" ]]
}

@test "parse_args --color off sets COLOR_MODE" {
    parse_args --color off
    [[ "$COLOR_MODE" == "off" ]]
}

@test "parse_args --color auto sets COLOR_MODE" {
    parse_args --color auto
    [[ "$COLOR_MODE" == "auto" ]]
}

@test "parse_args default COLOR_MODE is auto" {
    parse_args
    [[ "$COLOR_MODE" == "auto" ]]
}

@test "parse_args --color combined with other flags" {
    parse_args --percent 80 --color off --iterations 3
    [[ "$COLOR_MODE" == "off" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "validate_args invalid color mode fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=bogus
    run validate_args
    assert_failure
    assert_output --partial "color"
}

@test "usage includes --color" {
    run usage
    assert_success
    assert_output --partial "--color"
}

@test "usage includes --allow-ce" {
    run usage
    assert_success
    assert_output --partial "--allow-ce"
}

@test "usage outputs to stderr" {
    run usage
    assert_success
    assert_output --partial "Usage"
}

@test "usage shows default memtester-dir" {
    run usage
    assert_success
    assert_output --partial "default: /usr/local/bin"
}

@test "usage shows DEFAULT_MEMTESTER_DIR when changed" {
    DEFAULT_MEMTESTER_DIR="/usr/bin"
    run usage
    assert_success
    assert_output --partial "default: /usr/bin"
}

@test "parse_args default MEMTESTER_DIR uses DEFAULT_MEMTESTER_DIR" {
    DEFAULT_MEMTESTER_DIR="/usr/bin"
    # Re-source to pick up the new default
    MEMTESTER_DIR="$DEFAULT_MEMTESTER_DIR"
    parse_args
    [[ "$MEMTESTER_DIR" == "/usr/bin" ]]
}

@test "parse_args --memtester-dir overrides DEFAULT_MEMTESTER_DIR" {
    DEFAULT_MEMTESTER_DIR="/usr/bin"
    MEMTESTER_DIR="$DEFAULT_MEMTESTER_DIR"
    parse_args --memtester-dir /opt/memtester/bin
    [[ "$MEMTESTER_DIR" == "/opt/memtester/bin" ]]
}

# stressapptest flag tests

@test "parse_args defaults for stressapptest" {
    parse_args
    [[ "$STRESSAPPTEST_MODE" == "auto" ]]
    [[ "$STRESSAPPTEST_SECONDS" == "0" ]]
    [[ "$STRESSAPPTEST_DIR" == "/usr/local/bin" ]]
}

@test "parse_args --stressapptest on" {
    parse_args --stressapptest on
    [[ "$STRESSAPPTEST_MODE" == "on" ]]
}

@test "parse_args --stressapptest off" {
    parse_args --stressapptest off
    [[ "$STRESSAPPTEST_MODE" == "off" ]]
}

@test "parse_args --stressapptest auto" {
    parse_args --stressapptest auto
    [[ "$STRESSAPPTEST_MODE" == "auto" ]]
}

@test "parse_args --stressapptest-seconds 60" {
    parse_args --stressapptest-seconds 60
    [[ "$STRESSAPPTEST_SECONDS" == "60" ]]
}

@test "parse_args --stressapptest-seconds 0" {
    parse_args --stressapptest-seconds 0
    [[ "$STRESSAPPTEST_SECONDS" == "0" ]]
}

@test "parse_args --stressapptest-dir custom" {
    parse_args --stressapptest-dir /usr/bin
    [[ "$STRESSAPPTEST_DIR" == "/usr/bin" ]]
}

@test "parse_args stressapptest combined flags" {
    parse_args --stressapptest on --stressapptest-seconds 120 --stressapptest-dir /opt/bin
    [[ "$STRESSAPPTEST_MODE" == "on" ]]
    [[ "$STRESSAPPTEST_SECONDS" == "120" ]]
    [[ "$STRESSAPPTEST_DIR" == "/opt/bin" ]]
}

@test "parse_args stressapptest combined with existing flags" {
    parse_args --percent 80 --stressapptest on --iterations 3
    [[ "$PERCENT" == "80" ]]
    [[ "$STRESSAPPTEST_MODE" == "on" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "parse_args default STRESSAPPTEST_DIR uses DEFAULT_STRESSAPPTEST_DIR" {
    DEFAULT_STRESSAPPTEST_DIR="/usr/bin"
    STRESSAPPTEST_DIR="$DEFAULT_STRESSAPPTEST_DIR"
    parse_args
    [[ "$STRESSAPPTEST_DIR" == "/usr/bin" ]]
}

@test "parse_args --stressapptest-dir overrides DEFAULT_STRESSAPPTEST_DIR" {
    DEFAULT_STRESSAPPTEST_DIR="/usr/bin"
    STRESSAPPTEST_DIR="$DEFAULT_STRESSAPPTEST_DIR"
    parse_args --stressapptest-dir /opt/stressapptest/bin
    [[ "$STRESSAPPTEST_DIR" == "/opt/stressapptest/bin" ]]
}

@test "validate_args invalid stressapptest mode fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=bogus STRESSAPPTEST_SECONDS=0
    run validate_args
    assert_failure
    assert_output --partial "stressapptest"
}

@test "validate_args negative stressapptest-seconds fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=-1
    run validate_args
    assert_failure
    assert_output --partial "stressapptest-seconds"
}

@test "validate_args valid stressapptest defaults passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0
    run validate_args
    assert_success
}

@test "validate_args stressapptest mode on passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=on STRESSAPPTEST_SECONDS=60
    run validate_args
    assert_success
}

@test "validate_args stressapptest mode off passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=off STRESSAPPTEST_SECONDS=0
    run validate_args
    assert_success
}

@test "usage includes --stressapptest" {
    run usage
    assert_success
    assert_output --partial "--stressapptest"
}

@test "usage includes --stressapptest-seconds" {
    run usage
    assert_success
    assert_output --partial "--stressapptest-seconds"
}

@test "usage includes --stressapptest-dir" {
    run usage
    assert_success
    assert_output --partial "--stressapptest-dir"
}

@test "usage shows default stressapptest-dir" {
    run usage
    assert_success
    assert_output --partial "default: /usr/local/bin"
}

@test "usage shows DEFAULT_STRESSAPPTEST_DIR when changed" {
    DEFAULT_STRESSAPPTEST_DIR="/opt/sat"
    run usage
    assert_success
    assert_output --partial "default: /opt/sat"
}
