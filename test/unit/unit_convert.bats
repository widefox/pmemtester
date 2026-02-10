setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib unit_convert.sh
}

@test "kb_to_mb exact" {
    run kb_to_mb 1024
    assert_success
    assert_output "1"
}

@test "kb_to_mb larger" {
    run kb_to_mb 2048
    assert_success
    assert_output "2"
}

@test "kb_to_mb truncates below 1024" {
    run kb_to_mb 1023
    assert_success
    assert_output "0"
}

@test "kb_to_mb truncates remainder" {
    run kb_to_mb 1536
    assert_success
    assert_output "1"
}

@test "kb_to_mb realistic 16GB" {
    run kb_to_mb 16384000
    assert_success
    assert_output "16000"
}

@test "mb_to_kb basic" {
    run mb_to_kb 1
    assert_success
    assert_output "1024"
}

@test "mb_to_kb 256MB" {
    run mb_to_kb 256
    assert_success
    assert_output "262144"
}

@test "bytes_to_kb exact" {
    run bytes_to_kb 1024
    assert_success
    assert_output "1"
}

@test "bytes_to_kb truncates" {
    run bytes_to_kb 1023
    assert_success
    assert_output "0"
}

@test "bytes_to_kb 1MB" {
    run bytes_to_kb 1048576
    assert_success
    assert_output "1024"
}

@test "kb_to_bytes basic" {
    run kb_to_bytes 1
    assert_success
    assert_output "1024"
}

@test "kb_to_bytes 1MB" {
    run kb_to_bytes 1024
    assert_success
    assert_output "1048576"
}

@test "mb_to_memtester_arg formats correctly" {
    run mb_to_memtester_arg 256
    assert_success
    assert_output "256M"
}

@test "mb_to_memtester_arg large value" {
    run mb_to_memtester_arg 1024
    assert_success
    assert_output "1024M"
}
