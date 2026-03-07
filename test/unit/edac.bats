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

# --- poll_edac_for_ue tests ---

@test "poll_edac_for_ue writes ue to sentinel when UE detected" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    # Baseline: no errors
    echo "mc0/csrow0/ce_count:0" > "$baseline"
    echo "mc0/csrow0/ue_count:0" >> "$baseline"

    # Override EDAC_BASE so capture_edac_counters reads a fixture with a UE
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ue_only"

    # Run poll in background with 0s interval
    poll_edac_for_ue "$baseline" "$sentinel" 0 &
    local poll_pid=$!

    # Give it time to detect
    sleep 0.5
    kill "$poll_pid" 2>/dev/null || true
    wait "$poll_pid" 2>/dev/null || true

    [[ -f "$sentinel" ]]
    [[ "$(cat "$sentinel")" == "ue" ]]
}

@test "poll_edac_for_ue does not write sentinel when only CE" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    echo "mc0/csrow0/ce_count:0" > "$baseline"
    echo "mc0/csrow0/ue_count:0" >> "$baseline"

    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ce_only"

    poll_edac_for_ue "$baseline" "$sentinel" 0 &
    local poll_pid=$!
    sleep 0.3
    kill "$poll_pid" 2>/dev/null || true
    wait "$poll_pid" 2>/dev/null || true

    # Sentinel should not be written (or not contain "ue")
    if [[ -f "$sentinel" ]]; then
        [[ "$(cat "$sentinel")" != "ue" ]]
    fi
}

@test "poll_edac_for_ue stops when sentinel contains stop" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    echo "mc0/csrow0/ue_count:0" > "$baseline"
    # Pre-write stop sentinel
    echo "stop" > "$sentinel"

    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_ue_only"

    # Should exit immediately (sentinel already says stop)
    run poll_edac_for_ue "$baseline" "$sentinel" 0
    # It exits; sentinel still contains "stop", not "ue"
    [[ "$(cat "$sentinel")" == "stop" ]]
}

@test "poll_edac_for_ue does nothing when no UE and no stop" {
    local baseline="${TEST_DIR}/baseline.txt"
    local sentinel="${TEST_DIR}/sentinel.txt"

    echo "mc0/csrow0/ce_count:0" > "$baseline"
    echo "mc0/csrow0/ue_count:0" >> "$baseline"

    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"

    poll_edac_for_ue "$baseline" "$sentinel" 0 &
    local poll_pid=$!
    sleep 0.3
    kill "$poll_pid" 2>/dev/null || true
    wait "$poll_pid" 2>/dev/null || true

    [[ ! -f "$sentinel" ]]
}

# --- parse_edac_error_addresses tests ---

@test "parse_edac_error_addresses extracts physical addresses from dmesg" {
    local dmesg_file="${TEST_DIR}/edac_dmesg.txt"
    cat > "$dmesg_file" <<'EOF'
[12345.678] EDAC MC0: 1 CE error on CPU#0Channel#0_DIMM#0 (channel:0 slot:0 page:0x1a2b3 offset:0x0 grain:8 syndrome:0x0)
[12346.789] EDAC MC0: 1 UE error on CPU#0Channel#1_DIMM#0 (channel:1 slot:0 page:0x2b3c4 offset:0x100 grain:8)
EOF
    run parse_edac_error_addresses "$dmesg_file"
    assert_success
    # Should extract physical addresses: page*4096+offset
    assert_output --partial "1a2b3"
    assert_output --partial "2b3c4"
}

@test "parse_edac_error_addresses returns empty for clean dmesg" {
    local dmesg_file="${TEST_DIR}/edac_dmesg.txt"
    echo "[12345.678] Some other kernel message" > "$dmesg_file"
    run parse_edac_error_addresses "$dmesg_file"
    assert_success
    [[ -z "$output" ]]
}

@test "parse_edac_error_addresses handles multiple error lines" {
    local dmesg_file="${TEST_DIR}/edac_dmesg.txt"
    cat > "$dmesg_file" <<'EOF'
[100.0] EDAC MC0: 1 CE error (channel:0 slot:0 page:0xaaa offset:0x0 grain:8)
[200.0] EDAC MC0: 1 CE error (channel:0 slot:0 page:0xbbb offset:0x0 grain:8)
[300.0] EDAC MC1: 1 UE error (channel:1 slot:0 page:0xccc offset:0x200 grain:8)
EOF
    run parse_edac_error_addresses "$dmesg_file"
    assert_success
    local line_count
    line_count="$(echo "$output" | wc -l)"
    [[ "$line_count" -eq 3 ]]
}

# --- format_edac_dimm_topology tests ---

@test "format_edac_dimm_topology lists MC/csrow/channel structure" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"
    run format_edac_dimm_topology
    assert_success
    assert_output --partial "mc0"
    assert_output --partial "csrow0"
}

@test "format_edac_dimm_topology reads dimm_label if available" {
    # Create a fixture with dimm_label
    local edac_dir="${TEST_DIR}/edac/mc/mc0/csrow0"
    mkdir -p "$edac_dir"
    echo "0" > "$edac_dir/ce_count"
    echo "0" > "$edac_dir/ue_count"
    echo "DIMM_A1" > "$edac_dir/ch0_dimm_label"
    export EDAC_BASE="${TEST_DIR}/edac"
    run format_edac_dimm_topology
    assert_success
    assert_output --partial "DIMM_A1"
}

@test "format_edac_dimm_topology handles missing dimm_label" {
    export EDAC_BASE="${FIXTURE_DIR}/edac_counters_zero"
    run format_edac_dimm_topology
    assert_success
    # Should still produce output without crashing
    [[ -n "$output" ]]
}

# --- correlate_physical_to_edac tests ---

@test "correlate_physical_to_edac matches address to MC with error" {
    local pagemap_file="${TEST_DIR}/thread_0_pagemap.txt"
    cat > "$pagemap_file" <<'EOF'
# min_phys=1a2b3000 max_phys=1a2b4000 pages=2
01000000:107187:1a2b3000
01001000:107188:1a2b4000
EOF
    local edac_msg_file="${TEST_DIR}/edac_msgs.txt"
    cat > "$edac_msg_file" <<'EOF'
[12345.678] EDAC MC0: 1 UE error (channel:0 slot:0 page:0x1a2b3 offset:0x0 grain:8)
EOF
    run correlate_physical_to_edac "$pagemap_file" "$edac_msg_file"
    assert_success
    assert_output --partial "MC0"
    assert_output --partial "1a2b3"
}

@test "correlate_physical_to_edac returns unknown when no match" {
    local pagemap_file="${TEST_DIR}/thread_0_pagemap.txt"
    cat > "$pagemap_file" <<'EOF'
# min_phys=1a2b3000 max_phys=1a2b4000 pages=2
01000000:107187:1a2b3000
01001000:107188:1a2b4000
EOF
    local edac_msg_file="${TEST_DIR}/edac_msgs.txt"
    # EDAC error at a completely different address
    cat > "$edac_msg_file" <<'EOF'
[12345.678] EDAC MC1: 1 UE error (channel:0 slot:0 page:0xfffff offset:0x0 grain:8)
EOF
    run correlate_physical_to_edac "$pagemap_file" "$edac_msg_file"
    assert_success
    assert_output --partial "no overlap"
}
