#!/usr/bin/env bats
# Regression tests for pmemtester
# Each test is traced to a specific issue, commit, or reported defect.
# Naming: "regression #N: <title>" where N matches the GitHub issue number
# or a sequential ID for internally-discovered regressions.

setup() {
    load '../test_helper/common_setup'
    _common_setup
}

# ============================================================================
# GitHub Issue #1: "misleading locked memory size ERROR"
# https://github.com/widefox/pmemtester/issues/1
#
# Bug: check_memlock_sufficient() printed "ERROR:" when memlock limit was
# lower than requested, even though the condition was non-fatal (the size
# gets adjusted and a real error is only printed on adjustment failure).
# Fix: Changed "ERROR:" to "INFO:" in the diagnostic message.
# ============================================================================

@test "regression #1: memlock insufficient prints INFO not ERROR" {
    load_lib memlock.sh
    _read_ulimit_l() { echo "65536"; }
    run check_memlock_sufficient 131072
    assert_failure
    assert_output --partial "INFO:"
    refute_output --partial "ERROR:"
}

@test "regression #1: memlock insufficient message includes limit and needed values" {
    load_lib memlock.sh
    _read_ulimit_l() { echo "65536"; }
    run check_memlock_sufficient 131072
    assert_failure
    assert_output --partial "65536"
    assert_output --partial "131072"
}

@test "regression #1: configure_memlock failure prints ERROR (fatal path)" {
    load_lib memlock.sh
    _set_ulimit_l() { return 1; }
    run configure_memlock 131072
    assert_failure
    assert_output --partial "ERROR:"
}

# ============================================================================
# Regression: decimal_to_millipercent must reject negative values
# Internally discovered during v0.4 development. Negative percent would
# produce a nonsensical RAM target.
# ============================================================================

@test "regression: decimal_to_millipercent rejects negative input" {
    load_lib math_utils.sh
    run decimal_to_millipercent "-5"
    assert_failure
    assert_output --partial "must not be negative"
}

@test "regression: decimal_to_millipercent rejects -0.1" {
    load_lib math_utils.sh
    run decimal_to_millipercent "-0.1"
    assert_failure
}

# ============================================================================
# Regression: parse_size_to_kb must reject bare numbers (no suffix)
# Without this check, "256" would be silently treated as bytes or fail
# unpredictably. The user must specify K, M, G, or T.
# ============================================================================

@test "regression: --size rejects bare numbers without suffix" {
    load_lib unit_convert.sh
    run parse_size_to_kb "256"
    assert_failure
    assert_output --partial "requires a unit suffix"
}

@test "regression: --size rejects zero" {
    load_lib unit_convert.sh
    run parse_size_to_kb "0M"
    assert_failure
    assert_output --partial "must be > 0"
}

# ============================================================================
# Regression: --percent and --size mutual exclusion
# If both were accepted silently, the user could get confused about which
# value was used. This was enforced in v0.3.
# ============================================================================

@test "regression: --percent and --size are mutually exclusive" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --percent 50 --size 256M
    run validate_args
    assert_failure
    assert_output --partial "mutually exclusive"
}

# ============================================================================
# Regression: ceiling_div must not crash on zero denominator
# Division by zero in bash causes a fatal error. The function must guard
# against it and return a clean error.
# ============================================================================

@test "regression: ceiling_div handles zero denominator gracefully" {
    load_lib math_utils.sh
    run ceiling_div 10 0
    assert_failure
    assert_output --partial "division by zero"
}

# ============================================================================
# Regression: divide_ram_per_core_mb must fail when result < 1 MB
# If RAM is too small per core, memtester would be invoked with 0M which
# is invalid. This guard was added after hitting the issue in testing.
# ============================================================================

@test "regression: divide_ram_per_core_mb rejects sub-1MB allocation" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib ram_calc.sh
    run divide_ram_per_core_mb 512 2
    assert_failure
    assert_output --partial "RAM per core < 1 MB"
}

# ============================================================================
# Regression: safe_multiply must detect 64-bit integer overflow
# Bash integers are 64-bit signed. Multiplying large values silently wraps
# around, producing incorrect (possibly negative) results.
# ============================================================================

@test "regression: safe_multiply detects overflow" {
    load_lib math_utils.sh
    run safe_multiply 9999999999999999 9999999999
    assert_failure
    assert_output --partial "integer overflow"
}

@test "regression: safe_multiply succeeds for valid large values" {
    load_lib math_utils.sh
    run safe_multiply 1000000 1000000
    assert_success
    assert_output "1000000000000"
}

# ============================================================================
# Regression: validate_args must reject unknown options
# Unrecognised flags must cause immediate failure with a clear message,
# not be silently ignored.
# ============================================================================

@test "regression: parse_args rejects unknown flags" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    run parse_args --nonexistent-flag
    assert_failure
    assert_output --partial "unknown option"
}

# ============================================================================
# Regression: validate_args --ram-type rejects invalid values
# Only "available", "total", and "free" are valid. Anything else must fail
# with a clear error message.
# ============================================================================

@test "regression: --ram-type rejects invalid value" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --ram-type "bogus"
    run validate_args
    assert_failure
    assert_output --partial "must be available, total, or free"
}

# ============================================================================
# Regression: (( i++ )) pitfall with set -e
# When i=0, (( i++ )) evaluates to 0 (falsy) and exits under set -e.
# All loop counters must use i=$(( i + 1 )) instead.
# ============================================================================

@test "regression: loop counter increment from 0 does not exit under set -e" {
    run bash -c '
        set -e
        i=0
        i=$(( i + 1 ))
        echo "$i"
    '
    assert_success
    assert_output "1"
}

@test "regression: (( i++ )) from 0 fails under set -e (demonstrating the pitfall)" {
    run bash -c '
        set -e
        i=0
        (( i++ ))
        echo "$i"
    '
    assert_failure
}

# ============================================================================
# Regression: decimal_to_millipercent handles leading-zero edge cases
# Values like "08" or "09" must not be interpreted as invalid octal.
# The implementation uses 10# prefix to force base-10.
# ============================================================================

@test "regression: decimal_to_millipercent handles 08 (not octal)" {
    load_lib math_utils.sh
    run decimal_to_millipercent "08"
    assert_success
    assert_output "8000"
}

@test "regression: decimal_to_millipercent handles 09 (not octal)" {
    load_lib math_utils.sh
    run decimal_to_millipercent "09"
    assert_success
    assert_output "9000"
}

@test "regression: decimal_to_millipercent handles 0.08 (not octal)" {
    load_lib math_utils.sh
    run decimal_to_millipercent "0.08"
    assert_success
    assert_output "80"
}
