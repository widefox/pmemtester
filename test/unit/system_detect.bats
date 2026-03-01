setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    FIXTURE_DIR="${PROJECT_ROOT}/test/fixtures"
    load_lib system_detect.sh
}

teardown() {
    teardown_mock_dir
}

@test "get_total_ram_kb normal" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run get_total_ram_kb
    assert_success
    assert_output "16384000"
}

@test "get_free_ram_kb normal" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run get_free_ram_kb
    assert_success
    assert_output "8192000"
}

@test "get_available_ram_kb normal" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    run get_available_ram_kb
    assert_success
    assert_output "12288000"
}

@test "get_total_ram_kb low memory" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_low"
    run get_total_ram_kb
    assert_success
    assert_output "1024000"
}

@test "get_free_ram_kb low memory" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_low"
    run get_free_ram_kb
    assert_success
    assert_output "102400"
}

@test "get_available_ram_kb low memory" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_low"
    run get_available_ram_kb
    assert_success
    assert_output "204800"
}

@test "get_available_ram_kb missing field fails" {
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_no_available"
    run get_available_ram_kb
    assert_failure
}

@test "get_core_count returns physical core count" {
    create_mock lscpu 'echo "# Socket,Core"; echo "0,0"; echo "0,1"; echo "0,2"; echo "0,3"; echo "1,0"; echo "1,1"; echo "1,2"; echo "1,3"'
    run get_core_count
    assert_success
    assert_output "8"
}

@test "get_core_count deduplicates SMT threads" {
    create_mock lscpu 'echo "# Socket,Core"; echo "0,0"; echo "0,0"; echo "0,1"; echo "0,1"'
    run get_core_count
    assert_success
    assert_output "2"
}

@test "get_core_count single core" {
    create_mock lscpu 'echo "# Socket,Core"; echo "0,0"'
    run get_core_count
    assert_success
    assert_output "1"
}

@test "get_core_count lscpu failure falls back to nproc" {
    create_mock lscpu 'exit 1'
    create_mock nproc 'echo "4"'
    run get_core_count
    assert_success
    assert_output "4"
}

@test "get_core_count all methods fail" {
    create_mock lscpu 'exit 1'
    create_mock nproc 'exit 1'
    run get_core_count
    assert_failure
}

@test "get_core_count lscpu empty output falls back to nproc" {
    create_mock lscpu 'echo "# Socket,Core"'
    create_mock nproc 'echo "8"'
    run get_core_count
    assert_success
    assert_output "8"
}

# --- get_l3_cache_kb tests ---

@test "get_l3_cache_kb reads 3MB L3 from sysfs" {
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_3mb"
    run get_l3_cache_kb
    assert_success
    assert_output "3072"
}

@test "get_l3_cache_kb reads 96MB L3 from sysfs" {
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_96mb"
    run get_l3_cache_kb
    assert_success
    assert_output "98304"
}

@test "get_l3_cache_kb no L3 in sysfs falls back to getconf" {
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_no_l3"
    # getconf returns bytes; 6291456 bytes = 6144 kB
    create_mock getconf 'echo "6291456"'
    run get_l3_cache_kb
    assert_success
    assert_output "6144"
}

@test "get_l3_cache_kb no L3 and getconf fails returns error" {
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_no_l3"
    create_mock getconf 'exit 1'
    run get_l3_cache_kb
    assert_failure
}

@test "get_l3_cache_kb no L3 and getconf returns 0 returns error" {
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_no_l3"
    create_mock getconf 'echo "0"'
    run get_l3_cache_kb
    assert_failure
}

@test "get_l3_cache_kb finds L3 by level not by index number" {
    # L3 at index2 instead of index3
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_l3_at_index2"
    run get_l3_cache_kb
    assert_success
    assert_output "6144"
}

@test "get_l3_cache_kb sysfs directory missing falls back to getconf" {
    export SYS_CPU_BASE="${FIXTURE_DIR}/nonexistent_dir"
    create_mock getconf 'echo "3145728"'
    run get_l3_cache_kb
    assert_success
    assert_output "3072"
}
