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

@test "compare_edac_counters unchanged" {
    local f="${TEST_DIR}/counters.txt"
    echo "mc0/csrow0/ce_count:0" > "$f"
    echo "mc0/csrow0/ue_count:0" >> "$f"
    run compare_edac_counters "$f" "$f"
    assert_success
}

@test "compare_edac_counters increased" {
    local before="${TEST_DIR}/before.txt"
    local after="${TEST_DIR}/after.txt"
    echo "mc0/csrow0/ce_count:0" > "$before"
    echo "mc0/csrow0/ue_count:0" >> "$before"
    echo "mc0/csrow0/ce_count:3" > "$after"
    echo "mc0/csrow0/ue_count:0" >> "$after"
    run compare_edac_counters "$before" "$after"
    assert_failure
}
