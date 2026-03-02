setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib math_utils.sh
    load_lib unit_convert.sh
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
    pmemtester_version="0.5"
    run parse_args --version
    assert_success
    assert_output --partial "pmemtester 0.5"
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
    PERCENT=0 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

@test "validate_args percent 101 fails" {
    PERCENT=101 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

@test "validate_args invalid ram type fails" {
    PERCENT=90 RAM_TYPE=bogus MEMTESTER_DIR=/usr/local/bin ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

@test "validate_args iterations zero fails" {
    PERCENT=90 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=0 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
    assert_output --partial "iterations"
}

@test "validate_args valid defaults passes" {
    PERCENT=90 RAM_TYPE=available MEMTESTER_DIR=/usr/local/bin ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args valid ram-type total passes" {
    PERCENT=90 RAM_TYPE=total MEMTESTER_DIR=/usr/local/bin ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args valid ram-type free passes" {
    PERCENT=90 RAM_TYPE=free MEMTESTER_DIR=/usr/local/bin ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
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
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=bogus STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
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
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=bogus STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
    assert_output --partial "stressapptest"
}

@test "validate_args negative stressapptest-seconds fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=-1 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
    assert_output --partial "stressapptest-seconds"
}

@test "validate_args valid stressapptest defaults passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args stressapptest mode on passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=on STRESSAPPTEST_SECONDS=60 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args stressapptest mode off passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=off STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
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

# --- decimal --percent tests ---

@test "parse_args --percent 0.1" {
    parse_args --percent 0.1
    [[ "$PERCENT" == "0.1" ]]
}

@test "parse_args --percent 50.5" {
    parse_args --percent 50.5
    [[ "$PERCENT" == "50.5" ]]
}

@test "parse_args --percent sets PERCENT_SET" {
    parse_args --percent 80
    [[ "$PERCENT_SET" == "1" ]]
}

@test "parse_args default PERCENT_SET is 0" {
    parse_args
    [[ "$PERCENT_SET" == "0" ]]
}

@test "validate_args decimal percent 0.1 passes" {
    PERCENT=0.1 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args decimal percent 50.5 passes" {
    PERCENT=50.5 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args decimal percent 0.001 passes" {
    PERCENT=0.001 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args decimal percent 100.0 passes" {
    PERCENT=100.0 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args percent 0 fails (decimal path)" {
    PERCENT=0 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

@test "validate_args percent 0.0 fails" {
    PERCENT=0.0 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

@test "validate_args percent 100.1 fails" {
    PERCENT=100.1 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

@test "validate_args percent abc fails (decimal path)" {
    PERCENT=abc RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0
    run validate_args
    assert_failure
}

# --- --size flag tests ---

@test "parse_args --size 256M" {
    parse_args --size 256M
    [[ "$SIZE" == "256M" ]]
}

@test "parse_args --size 2G" {
    parse_args --size 2G
    [[ "$SIZE" == "2G" ]]
}

@test "parse_args --size 1024K" {
    parse_args --size 1024K
    [[ "$SIZE" == "1024K" ]]
}

@test "parse_args default SIZE is empty" {
    parse_args
    [[ -z "$SIZE" ]]
}

@test "validate_args --size 256M passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="256M" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args --size 2G passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="2G" PERCENT_SET=0
    run validate_args
    assert_success
}

@test "validate_args --size bare number fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="256" PERCENT_SET=0
    run validate_args
    assert_failure
    assert_output --partial "unit suffix"
}

@test "validate_args --size 0M fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="0M" PERCENT_SET=0
    run validate_args
    assert_failure
}

# --- mutual exclusion tests ---

@test "validate_args --percent and --size mutually exclusive" {
    PERCENT=50 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="256M" PERCENT_SET=1
    run validate_args
    assert_failure
    assert_output --partial "mutually exclusive"
}

@test "validate_args --size without explicit --percent passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="256M" PERCENT_SET=0
    run validate_args
    assert_success
}

# --- usage text ---

@test "usage includes --size" {
    run usage
    assert_success
    assert_output --partial "--size"
}

@test "usage shows decimal percent range" {
    run usage
    assert_success
    assert_output --partial "0.001-100"
}

# --- --estimate flag tests ---

@test "parse_args default ESTIMATE_MODE is auto" {
    parse_args
    [[ "$ESTIMATE_MODE" == "auto" ]]
}

@test "parse_args --estimate on" {
    parse_args --estimate on
    [[ "$ESTIMATE_MODE" == "on" ]]
}

@test "parse_args --estimate off" {
    parse_args --estimate off
    [[ "$ESTIMATE_MODE" == "off" ]]
}

@test "parse_args --estimate auto" {
    parse_args --estimate auto
    [[ "$ESTIMATE_MODE" == "auto" ]]
}

@test "parse_args --estimate combined with other flags" {
    parse_args --percent 80 --estimate on --iterations 3
    [[ "$ESTIMATE_MODE" == "on" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "validate_args invalid estimate mode fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 ESTIMATE_MODE=bogus
    run validate_args
    assert_failure
    assert_output --partial "estimate"
}

@test "validate_args estimate auto passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 ESTIMATE_MODE=auto
    run validate_args
    assert_success
}

@test "validate_args estimate on passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 ESTIMATE_MODE=on
    run validate_args
    assert_success
}

@test "validate_args estimate off passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 ESTIMATE_MODE=off
    run validate_args
    assert_success
}

@test "usage includes --estimate" {
    run usage
    assert_success
    assert_output --partial "--estimate"
}

# --- --stop-on-error flag tests ---

@test "parse_args default STOP_ON_ERROR is 0" {
    parse_args
    [[ "$STOP_ON_ERROR" == "0" ]]
}

@test "parse_args --stop-on-error sets STOP_ON_ERROR to 1" {
    parse_args --stop-on-error
    [[ "$STOP_ON_ERROR" == "1" ]]
}

@test "parse_args --stop-on-error combined with other flags" {
    parse_args --percent 80 --stop-on-error --iterations 3
    [[ "$STOP_ON_ERROR" == "1" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "usage includes --stop-on-error" {
    run usage
    assert_success
    assert_output --partial "--stop-on-error"
}

# --- --threads flag tests ---

@test "parse_args default THREADS is 0" {
    parse_args
    [[ "$THREADS" == "0" ]]
}

@test "parse_args --threads 4 sets THREADS" {
    parse_args --threads 4
    [[ "$THREADS" == "4" ]]
}

@test "parse_args --threads 1 sets THREADS" {
    parse_args --threads 1
    [[ "$THREADS" == "1" ]]
}

@test "parse_args --threads combined with other flags" {
    parse_args --percent 80 --threads 2 --iterations 3
    [[ "$THREADS" == "2" ]]
    [[ "$PERCENT" == "80" ]]
    [[ "$ITERATIONS" == "3" ]]
}

@test "validate_args --threads -1 fails" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto \
    STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 \
    ESTIMATE_MODE=auto STOP_ON_ERROR=0 THREADS=-1
    run validate_args
    assert_failure
    assert_output --partial "threads"
}

@test "validate_args --threads 4 passes" {
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto \
    STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 \
    ESTIMATE_MODE=auto STOP_ON_ERROR=0 THREADS=4
    run validate_args
    assert_success
}

@test "validate_args --threads warns if greater than nproc" {
    local mock_bin="${BATS_TEST_TMPDIR}/mock_bin"
    mkdir -p "$mock_bin"
    printf '#!/bin/sh\necho 2\n' > "${mock_bin}/nproc"
    chmod +x "${mock_bin}/nproc"
    PATH="${mock_bin}:${PATH}" \
    PERCENT=90 RAM_TYPE=available ITERATIONS=1 COLOR_MODE=auto \
    STRESSAPPTEST_MODE=auto STRESSAPPTEST_SECONDS=0 SIZE="" PERCENT_SET=0 \
    ESTIMATE_MODE=auto STOP_ON_ERROR=0 THREADS=8
    run validate_args
    assert_success
    assert_output --partial "WARNING"
}

@test "usage includes --threads" {
    run usage
    assert_success
    assert_output --partial "--threads"
}
