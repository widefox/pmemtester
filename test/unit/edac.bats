setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    FIXTURE_DIR="${PROJECT_ROOT}/test/fixtures"
    load_lib edac.sh
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

@test "check_edac_supported sysfs exists" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"
    run check_edac_supported
    assert_success
}

@test "check_edac_supported sysfs missing" {
    export EDAC_BASE="${TEST_DIR}/nonexistent"
    run check_edac_supported
    assert_failure
}

@test "capture_edac_messages finds EDAC lines" {
    create_mock dmesg 'cat '"${FIXTURE_DIR}/edac_messages_errors.txt"
    run capture_edac_messages
    assert_success
    assert_output --partial "EDAC"
}

@test "capture_edac_messages no EDAC lines" {
    create_mock dmesg 'echo "no relevant lines here"'
    run capture_edac_messages
    assert_success
    assert_output ""
}

@test "capture_edac_messages dmesg permission denied" {
    create_mock dmesg 'echo "dmesg: read kernel buffer failed: Operation not permitted" >&2; exit 1'
    run capture_edac_messages
    assert_failure
}

@test "capture_edac_counters reads sysfs values" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"
    run capture_edac_counters
    assert_success
    assert_output --partial "ce_count"
    assert_output --partial "ue_count"
}

@test "capture_edac_counters with nonzero counts" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_nonzero"
    run capture_edac_counters
    assert_success
    assert_output --partial "3"
}

@test "compare_edac_messages identical" {
    local f="${TEST_DIR}/msgs.txt"
    echo "EDAC MC: init" > "$f"
    run compare_edac_messages "$f" "$f"
    assert_success
}

@test "compare_edac_messages new errors" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "EDAC MC: init" > "$before"
    printf "EDAC MC: init\nEDAC MC0: 1 CE error\n" > "$after"
    run compare_edac_messages "$before" "$after"
    assert_failure
}

@test "classify_edac_counters unchanged returns none" {
    local f="${TEST_DIR}/counters.txt"
    echo "mc0/csrow0/ce_count:0" > "$f"
    echo "mc0/csrow0/ue_count:0" >> "$f"
    run classify_edac_counters "$f" "$f"
    assert_success
    assert_output "none"
}

@test "classify_edac_counters increased returns ce_only" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:3" > "$after"
    echo "mc0/csrow0/ue_count:0" >> "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ce_only"
}

# classify_edac_counters tests

@test "classify_edac_counters no change" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    cp "$before" "$after"
    run classify_edac_counters "$before" "$after"
    assert_success
    assert_output "none"
}

@test "classify_edac_counters ce only" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:3" > "$after"
    echo "mc0/csrow0/ue_count:0" >> "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ce_only"
}

@test "classify_edac_counters ue only" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:0" > "$after"
    echo "mc0/csrow0/ue_count:2" >> "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ue_only"
}

@test "classify_edac_counters ce and ue" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:5" > "$after"
    echo "mc0/csrow0/ue_count:1" >> "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ce_and_ue"
}

@test "classify_edac_counters multi-MC ce only" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    printf "mc0/csrow0/ce_count:0\nmc0/csrow0/ue_count:0\nmc1/csrow0/ce_count:0\nmc1/csrow0/ue_count:0\n" > "$before"
    printf "mc0/csrow0/ce_count:2\nmc0/csrow0/ue_count:0\nmc1/csrow0/ce_count:1\nmc1/csrow0/ue_count:0\n" > "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ce_only"
}

@test "classify_edac_counters multi-MC mixed" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    printf "mc0/csrow0/ce_count:0\nmc0/csrow0/ue_count:0\nmc1/csrow0/ce_count:0\nmc1/csrow0/ue_count:0\n" > "$before"
    printf "mc0/csrow0/ce_count:3\nmc0/csrow0/ue_count:0\nmc1/csrow0/ce_count:0\nmc1/csrow0/ue_count:1\n" > "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ce_and_ue"
}

@test "classify_edac_counters new counter in after file" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    printf "mc0/csrow0/ce_count:0\nmc0/csrow0/ue_count:2\n" > "$after"
    run classify_edac_counters "$before" "$after"
    assert_failure
    assert_line "ue_only"
}

@test "classify_edac_counters ignores non-ce/ue counters" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    printf "mc0/csrow0/ce_count:0\nmc0/csrow0/ue_count:0\nmc0/csrow0/other_count:0\n" > "$before"
    printf "mc0/csrow0/ce_count:0\nmc0/csrow0/ue_count:0\nmc0/csrow0/other_count:5\n" > "$after"
    run classify_edac_counters "$before" "$after"
    assert_success
    assert_output "none"
}

@test "classify_edac_counters ignores counter decrease" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:5" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:3" > "$after"
    echo "mc0/csrow0/ue_count:0" >> "$after"
    run classify_edac_counters "$before" "$after"
    assert_success
    assert_output "none"
}

@test "classify_edac_counters empty files" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    : > "$before"
    : > "$after"
    run classify_edac_counters "$before" "$after"
    assert_success
    assert_output "none"
}

@test "classify_edac_counters reports changed counters on stderr" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:3" > "$after"
    echo "mc0/csrow0/ue_count:0" >> "$after"
    run classify_edac_counters "$before" "$after"
    assert_output --partial "ce_only"
    # stderr is merged into output by bats 'run'
    assert_output --partial "mc0/csrow0/ce_count"
}
