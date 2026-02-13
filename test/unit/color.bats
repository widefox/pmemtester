setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib color.sh
}

# color_init tests

@test "color_init auto mode on tty sets COLOR_ENABLED=1" {
    COLOR_MODE="auto"
    # Simulate TTY by overriding the check function
    _stdout_is_tty() { return 0; }
    export -f _stdout_is_tty
    unset NO_COLOR
    TERM="xterm"
    color_init
    [[ "$COLOR_ENABLED" == "1" ]]
}

@test "color_init auto mode non-tty sets COLOR_ENABLED=0" {
    COLOR_MODE="auto"
    _stdout_is_tty() { return 1; }
    export -f _stdout_is_tty
    unset NO_COLOR
    TERM="xterm"
    color_init
    [[ "$COLOR_ENABLED" == "0" ]]
}

@test "color_init auto mode TERM=dumb sets COLOR_ENABLED=0" {
    COLOR_MODE="auto"
    _stdout_is_tty() { return 0; }
    export -f _stdout_is_tty
    unset NO_COLOR
    TERM="dumb"
    color_init
    [[ "$COLOR_ENABLED" == "0" ]]
}

@test "color_init auto mode NO_COLOR set disables color" {
    COLOR_MODE="auto"
    _stdout_is_tty() { return 0; }
    export -f _stdout_is_tty
    NO_COLOR=1
    TERM="xterm"
    color_init
    [[ "$COLOR_ENABLED" == "0" ]]
}

@test "color_init on mode forces COLOR_ENABLED=1" {
    COLOR_MODE="on"
    color_init
    [[ "$COLOR_ENABLED" == "1" ]]
}

@test "color_init off mode forces COLOR_ENABLED=0" {
    COLOR_MODE="off"
    color_init
    [[ "$COLOR_ENABLED" == "0" ]]
}

# color output functions

@test "color_pass outputs green PASS when color enabled" {
    COLOR_MODE="on"
    color_init
    run color_pass
    assert_success
    # Check for ANSI green escape code and PASS text
    assert_output --partial "PASS"
    assert_output --partial $'\033[32m'
}

@test "color_pass outputs plain PASS when color disabled" {
    COLOR_MODE="off"
    color_init
    run color_pass
    assert_success
    assert_output "PASS"
    refute_output --partial $'\033['
}

@test "color_fail outputs red FAIL when color enabled" {
    COLOR_MODE="on"
    color_init
    run color_fail
    assert_success
    assert_output --partial "FAIL"
    assert_output --partial $'\033[31m'
}

@test "color_fail outputs plain FAIL when color disabled" {
    COLOR_MODE="off"
    color_init
    run color_fail
    assert_success
    assert_output "FAIL"
    refute_output --partial $'\033['
}

@test "color_fail with source shows source in output" {
    COLOR_MODE="on"
    color_init
    run color_fail "memtester"
    assert_success
    assert_output --partial "FAIL"
    assert_output --partial "memtester"
}

@test "color_fail with source plain shows source" {
    COLOR_MODE="off"
    color_init
    run color_fail "EDAC: ue_only"
    assert_success
    assert_output --partial "FAIL"
    assert_output --partial "EDAC: ue_only"
}

@test "color_warn outputs yellow WARNING when color enabled" {
    COLOR_MODE="on"
    color_init
    run color_warn "correctable EDAC errors"
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial $'\033[33m'
}

@test "color_warn outputs plain WARNING when color disabled" {
    COLOR_MODE="off"
    color_init
    run color_warn "correctable EDAC errors"
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "correctable EDAC errors"
    refute_output --partial $'\033['
}

@test "color_init auto mode unset TERM sets COLOR_ENABLED=0" {
    COLOR_MODE="auto"
    _stdout_is_tty() { return 0; }
    export -f _stdout_is_tty
    unset NO_COLOR
    unset TERM
    color_init
    [[ "$COLOR_ENABLED" == "0" ]]
}
