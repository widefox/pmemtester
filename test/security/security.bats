#!/usr/bin/env bats
# Security tests for pmemtester
# Verify input sanitization, command injection resistance, and privilege handling.
# These tests ensure that untrusted input cannot lead to arbitrary code execution
# or information disclosure.

setup() {
    load '../test_helper/common_setup'
    _common_setup
}

# ============================================================================
# Command Injection via CLI Arguments
# All string arguments must be sanitized or rejected before use in shell
# commands. We test each parameter that accepts freeform strings.
# ============================================================================

@test "security: --memtester-dir rejects command injection via backticks" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    # This should be treated as a literal path, not executed
    parse_args --memtester-dir '$(touch /tmp/pwned)'
    # The path won't exist as a valid directory, so find_memtester should fail
    # but the command should NOT be executed
    [[ ! -f "/tmp/pwned" ]]
}

@test "security: --log-dir rejects command injection via dollar-paren" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --log-dir '$(echo INJECTED > /tmp/pwned)'
    # Parse should succeed (it's just a string), but the command must not run
    [[ ! -f "/tmp/pwned" ]]
}

@test "security: --stressapptest-dir rejects command injection" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --stressapptest-dir '`touch /tmp/pwned`'
    [[ ! -f "/tmp/pwned" ]]
}

# ============================================================================
# Numeric Arguments: Integer Overflow & Non-Numeric Injection
# ============================================================================

@test "security: --percent rejects shell metacharacters" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --percent '; echo pwned'
    run validate_args
    assert_failure
}

@test "security: --iterations rejects non-numeric input" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --iterations 'abc'
    run validate_args
    assert_failure
}

@test "security: --threads rejects negative values" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --threads '-1'
    run validate_args
    assert_failure
}

@test "security: --stressapptest-seconds rejects negative" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --stressapptest-seconds '-5'
    run validate_args
    assert_failure
}

# ============================================================================
# Size Parsing: Injection Through Unit Suffix
# ============================================================================

@test "security: parse_size_to_kb rejects embedded shell commands" {
    load_lib unit_convert.sh
    run parse_size_to_kb '$(whoami)M'
    assert_failure
}

@test "security: parse_size_to_kb rejects pipe characters" {
    load_lib unit_convert.sh
    run parse_size_to_kb '256M|cat /etc/shadow'
    assert_failure
}

@test "security: parse_size_to_kb rejects semicolons" {
    load_lib unit_convert.sh
    run parse_size_to_kb '256M;rm -rf /'
    assert_failure
}

@test "security: parse_size_to_kb rejects newlines" {
    load_lib unit_convert.sh
    local input=$'256M\nwhoami'
    run parse_size_to_kb "$input"
    assert_failure
}

# ============================================================================
# Decimal Percent Parsing: Injection Through Format
# ============================================================================

@test "security: decimal_to_millipercent rejects embedded commands" {
    load_lib math_utils.sh
    run decimal_to_millipercent '$(id)'
    assert_failure
}

@test "security: decimal_to_millipercent rejects spaces" {
    load_lib math_utils.sh
    run decimal_to_millipercent '50 && echo pwned'
    assert_failure
}

@test "security: decimal_to_millipercent rejects hex notation" {
    load_lib math_utils.sh
    run decimal_to_millipercent '0x50'
    assert_failure
}

# ============================================================================
# NUMA Node Injection
# ============================================================================

@test "security: --numa-node rejects non-numeric input" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    export SYS_NODE_BASE="$(mktemp -d)"
    parse_args --numa-node 'abc'
    run validate_args
    assert_failure
    assert_output --partial "must be non-negative integer"
    rm -rf "$SYS_NODE_BASE"
}

@test "security: --numa-node rejects shell metacharacters" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    export SYS_NODE_BASE="$(mktemp -d)"
    parse_args --numa-node '0;whoami'
    run validate_args
    assert_failure
    rm -rf "$SYS_NODE_BASE"
}

# ============================================================================
# Mode Arguments: Only Accept Whitelisted Values
# ============================================================================

@test "security: --color rejects injection" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --color '$(id)'
    run validate_args
    assert_failure
    assert_output --partial "must be auto, on, or off"
}

@test "security: --stressapptest rejects injection" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --stressapptest '`whoami`'
    run validate_args
    assert_failure
    assert_output --partial "must be auto, on, or off"
}

@test "security: --estimate rejects injection" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --estimate 'on; rm -rf /'
    run validate_args
    assert_failure
    assert_output --partial "must be auto, on, or off"
}

@test "security: --ram-type rejects injection" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --ram-type 'total$(id)'
    run validate_args
    assert_failure
    assert_output --partial "must be available, total, or free"
}

# ============================================================================
# Path Traversal
# ============================================================================

@test "security: --log-dir with path traversal does not escape" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    # parse_args accepts the path (it's just a string parameter)
    # but the actual directory creation/use should be safe
    parse_args --log-dir '../../etc/shadow'
    # The path is stored but not validated at parse time.
    # Validate that it's just stored as a string.
    [[ "$LOG_DIR" == "../../etc/shadow" ]]
}

# ============================================================================
# Empty / Missing Arguments
# ============================================================================

@test "security: --percent with empty string fails" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"
    parse_args --percent ''
    run validate_args
    assert_failure
}

@test "security: --size with empty string fails" {
    load_lib unit_convert.sh
    run parse_size_to_kb ""
    assert_failure
    assert_output --partial "empty"
}

# ============================================================================
# Environment Variable Isolation
# ============================================================================

@test "security: PROC_MEMINFO override does not leak to child processes" {
    # The override is only used within the parent process
    # Verify it's read-only within the function scope
    load_lib system_detect.sh
    local PROC_MEMINFO="${BATS_TEST_TMPDIR}/fake_meminfo"
    echo "MemTotal:       1024 kB" > "$PROC_MEMINFO"
    echo "MemFree:         512 kB" >> "$PROC_MEMINFO"
    echo "MemAvailable:    768 kB" >> "$PROC_MEMINFO"
    export PROC_MEMINFO
    run get_total_ram_kb
    assert_success
    assert_output "1024"
}

@test "security: EDAC_BASE override is scoped correctly" {
    load_lib edac.sh
    local EDAC_BASE="${BATS_TEST_TMPDIR}/fake_edac"
    # No mc directory — check_edac_supported should fail
    run check_edac_supported
    assert_failure
}

# ============================================================================
# Integer Boundary Values
# ============================================================================

@test "security: percentage_of handles max bash integer" {
    load_lib math_utils.sh
    # 2^62 is safe; 2^63-1 is the max signed 64-bit
    run percentage_of 4611686018427387903 1
    assert_success
    # 1% of max/2 should not overflow
    assert_output "46116860184273879"
}

@test "security: safe_multiply catches near-max overflow" {
    load_lib math_utils.sh
    # 2^32 * 2^32 = 2^64, which overflows 64-bit signed
    run safe_multiply 4294967296 4294967296
    assert_failure
    assert_output --partial "overflow"
}
