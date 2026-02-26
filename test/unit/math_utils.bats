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

# --- decimal_to_millipercent ---

@test "decimal_to_millipercent integer 1" {
    run decimal_to_millipercent 1
    assert_success
    assert_output "1000"
}

@test "decimal_to_millipercent integer 90" {
    run decimal_to_millipercent 90
    assert_success
    assert_output "90000"
}

@test "decimal_to_millipercent integer 100" {
    run decimal_to_millipercent 100
    assert_success
    assert_output "100000"
}

@test "decimal_to_millipercent 0.1" {
    run decimal_to_millipercent 0.1
    assert_success
    assert_output "100"
}

@test "decimal_to_millipercent 0.01" {
    run decimal_to_millipercent 0.01
    assert_success
    assert_output "10"
}

@test "decimal_to_millipercent 0.001" {
    run decimal_to_millipercent 0.001
    assert_success
    assert_output "1"
}

@test "decimal_to_millipercent 50.5" {
    run decimal_to_millipercent 50.5
    assert_success
    assert_output "50500"
}

@test "decimal_to_millipercent 99.999" {
    run decimal_to_millipercent 99.999
    assert_success
    assert_output "99999"
}

@test "decimal_to_millipercent leading dot .5" {
    run decimal_to_millipercent .5
    assert_success
    assert_output "500"
}

@test "decimal_to_millipercent trailing dot 50." {
    run decimal_to_millipercent 50.
    assert_success
    assert_output "50000"
}

@test "decimal_to_millipercent 100.0" {
    run decimal_to_millipercent 100.0
    assert_success
    assert_output "100000"
}

@test "decimal_to_millipercent 1.5" {
    run decimal_to_millipercent 1.5
    assert_success
    assert_output "1500"
}

@test "decimal_to_millipercent 0.123" {
    run decimal_to_millipercent 0.123
    assert_success
    assert_output "123"
}

@test "decimal_to_millipercent 10.10" {
    run decimal_to_millipercent 10.10
    assert_success
    assert_output "10100"
}

@test "decimal_to_millipercent empty fails" {
    run decimal_to_millipercent ""
    assert_failure
}

@test "decimal_to_millipercent negative fails" {
    run decimal_to_millipercent -5
    assert_failure
}

@test "decimal_to_millipercent non-numeric fails" {
    run decimal_to_millipercent abc
    assert_failure
}

@test "decimal_to_millipercent 4+ decimal places fails" {
    run decimal_to_millipercent 0.0001
    assert_failure
}

@test "decimal_to_millipercent multiple dots fails" {
    run decimal_to_millipercent 1.2.3
    assert_failure
}

@test "decimal_to_millipercent just a dot fails" {
    run decimal_to_millipercent .
    assert_failure
}

# --- percentage_of_milli ---

@test "percentage_of_milli 90% of 1000" {
    run percentage_of_milli 1000 90000
    assert_success
    assert_output "900"
}

@test "percentage_of_milli 0.1% of 12288000" {
    run percentage_of_milli 12288000 100
    assert_success
    assert_output "12288"
}

@test "percentage_of_milli 50.5% of 12288000" {
    run percentage_of_milli 12288000 50500
    assert_success
    assert_output "6205440"
}

@test "percentage_of_milli 100% returns full value" {
    run percentage_of_milli 12288000 100000
    assert_success
    assert_output "12288000"
}

@test "percentage_of_milli 0.1% of 100 truncates to 0" {
    run percentage_of_milli 100 100
    assert_success
    assert_output "0"
}

@test "percentage_of_milli 0.001% of 12288000" {
    run percentage_of_milli 12288000 1
    assert_success
    assert_output "122"
}
