setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib memlock.sh
}

@test "get_memlock_limit_kb numeric" {
    _read_ulimit_l() { echo "65536"; }
    run get_memlock_limit_kb
    assert_success
    assert_output "65536"
}

@test "get_memlock_limit_kb unlimited" {
    _read_ulimit_l() { echo "unlimited"; }
    run get_memlock_limit_kb
    assert_success
    # Should return a very large number
    [[ "$output" -gt 999999998 ]]
}

@test "check_memlock_sufficient under limit" {
    _read_ulimit_l() { echo "65536"; }
    run check_memlock_sufficient 32768
    assert_success
}

@test "check_memlock_sufficient at limit" {
    _read_ulimit_l() { echo "65536"; }
    run check_memlock_sufficient 65536
    assert_success
}

@test "check_memlock_sufficient over limit" {
    _read_ulimit_l() { echo "65536"; }
    run check_memlock_sufficient 65537
    assert_failure
}

@test "check_memlock_sufficient unlimited always passes" {
    _read_ulimit_l() { echo "unlimited"; }
    run check_memlock_sufficient 99999999
    assert_success
}

@test "configure_memlock success" {
    # Mock ulimit -l to accept setting (function override)
    _set_ulimit_l() { return 0; }
    run configure_memlock 131072
    assert_success
}

@test "configure_memlock failure" {
    _set_ulimit_l() { return 1; }
    run configure_memlock 131072
    assert_failure
}
