setup() {
    load '../test_helper/common_setup'
    _common_setup
    FIXTURE_DIR="${PROJECT_ROOT}/test/fixtures"
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib system_detect.sh
    load_lib ram_calc.sh
}

@test "calculate_test_ram_kb 90% available" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run calculate_test_ram_kb 90 available
    assert_success
    assert_output "11059200"
}

@test "calculate_test_ram_kb 50% total" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run calculate_test_ram_kb 50 total
    assert_success
    assert_output "8192000"
}

@test "calculate_test_ram_kb 90% free" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run calculate_test_ram_kb 90 free
    assert_success
    assert_output "7372800"
}

@test "calculate_test_ram_kb 100% available" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run calculate_test_ram_kb 100 available
    assert_success
    assert_output "12288000"
}

@test "calculate_test_ram_kb low memory" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_low"
    run calculate_test_ram_kb 90 available
    assert_success
    assert_output "184320"
}

@test "calculate_test_ram_kb invalid type fails" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run calculate_test_ram_kb 90 bogus
    assert_failure
}

@test "divide_ram_per_core_mb 8 cores" {
    run divide_ram_per_core_mb 11059200 8
    assert_success
    assert_output "1350"
}

@test "divide_ram_per_core_mb 4 cores" {
    run divide_ram_per_core_mb 204800 4
    assert_success
    assert_output "50"
}

@test "divide_ram_per_core_mb result too small fails" {
    run divide_ram_per_core_mb 512 2
    assert_failure
}

@test "divide_ram_per_core_mb single core" {
    run divide_ram_per_core_mb 11059200 1
    assert_success
    assert_output "10800"
}

@test "validate_ram_params valid" {
    run validate_ram_params 90 8 1350
    assert_success
}

@test "validate_ram_params zero percent fails" {
    run validate_ram_params 0 8 1350
    assert_failure
}

@test "validate_ram_params percent over 100 fails" {
    run validate_ram_params 101 8 1350
    assert_failure
}

@test "validate_ram_params zero cores fails" {
    run validate_ram_params 90 0 1350
    assert_failure
}

@test "validate_ram_params zero MB per core fails" {
    run validate_ram_params 90 8 0
    assert_failure
}
