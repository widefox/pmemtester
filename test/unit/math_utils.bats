setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib math_utils.sh
}

# --- ceiling_div ---

@test "ceiling_div rounds up" {
    run ceiling_div 10 3
    assert_success
    assert_output "4"
}

@test "ceiling_div exact division" {
    run ceiling_div 9 3
    assert_success
    assert_output "3"
}

@test "ceiling_div one by one" {
    run ceiling_div 1 1
    assert_success
    assert_output "1"
}

@test "ceiling_div zero numerator" {
    run ceiling_div 0 5
    assert_success
    assert_output "0"
}

@test "ceiling_div large values" {
    run ceiling_div 16384000 1024
    assert_success
    assert_output "16000"
}

@test "ceiling_div rounds up by one" {
    run ceiling_div 7 2
    assert_success
    assert_output "4"
}

@test "ceiling_div divide by zero fails" {
    run ceiling_div 10 0
    assert_failure
}

# --- percentage_of ---

@test "percentage_of 50 percent" {
    run percentage_of 1000 50
    assert_success
    assert_output "500"
}

@test "percentage_of 90 percent" {
    run percentage_of 1000 90
    assert_success
    assert_output "900"
}

@test "percentage_of non-round result truncates" {
    run percentage_of 999 90
    assert_success
    assert_output "899"
}

@test "percentage_of small value truncates to zero" {
    run percentage_of 1 90
    assert_success
    assert_output "0"
}

@test "percentage_of zero percent" {
    run percentage_of 1000 0
    assert_success
    assert_output "0"
}

@test "percentage_of 100 percent" {
    run percentage_of 100 100
    assert_success
    assert_output "100"
}

@test "percentage_of realistic 16GB at 90%" {
    run percentage_of 16384000 90
    assert_success
    assert_output "14745600"
}

# --- safe_multiply ---

@test "safe_multiply normal" {
    run safe_multiply 1024 1024
    assert_success
    assert_output "1048576"
}

@test "safe_multiply by zero" {
    run safe_multiply 0 999
    assert_success
    assert_output "0"
}

@test "safe_multiply overflow detection" {
    run safe_multiply 9999999999999999 9999999999
    assert_failure
}

# --- min_val / max_val ---

@test "min_val returns smaller (first)" {
    run min_val 3 5
    assert_success
    assert_output "3"
}

@test "min_val returns smaller (second)" {
    run min_val 5 3
    assert_success
    assert_output "3"
}

@test "min_val equal values" {
    run min_val 5 5
    assert_success
    assert_output "5"
}

@test "max_val returns larger" {
    run max_val 5 3
    assert_success
    assert_output "5"
}

@test "max_val returns larger (second)" {
    run max_val 3 5
    assert_success
    assert_output "5"
}

@test "max_val equal values" {
    run max_val 5 5
    assert_success
    assert_output "5"
}
