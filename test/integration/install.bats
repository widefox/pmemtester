setup() {
    load '../test_helper/common_setup'
    _common_setup
    INSTALL_DIR="$(mktemp -d)"
}

teardown() {
    [[ -d "${INSTALL_DIR:-}" ]] && rm -rf "$INSTALL_DIR"
}

@test "make install default MEMTESTER_DIR is /usr/local/bin" {
    make -C "$PROJECT_ROOT" install DESTDIR="$INSTALL_DIR" PREFIX=/usr/local 2>/dev/null
    local cli_sh="${INSTALL_DIR}/usr/local/lib/pmemtester/cli.sh"
    [[ -f "$cli_sh" ]]
    grep -q '/usr/local/bin' "$cli_sh"
}

@test "make install custom MEMTESTER_DIR patches default" {
    make -C "$PROJECT_ROOT" install DESTDIR="$INSTALL_DIR" PREFIX=/usr/local MEMTESTER_DIR=/usr/bin 2>/dev/null
    local cli_sh="${INSTALL_DIR}/usr/local/lib/pmemtester/cli.sh"
    [[ -f "$cli_sh" ]]
    # The default should now be /usr/bin, not /usr/local/bin
    grep -q 'DEFAULT_MEMTESTER_DIR="/usr/bin"' "$cli_sh"
}

@test "make install custom MEMTESTER_DIR updates help text" {
    make -C "$PROJECT_ROOT" install DESTDIR="$INSTALL_DIR" PREFIX=/usr/local MEMTESTER_DIR=/usr/bin 2>/dev/null
    local installed="${INSTALL_DIR}/usr/local/bin/pmemtester"
    [[ -x "$installed" ]]

    # Source the installed libs and check usage output
    run bash -c "
        source '${INSTALL_DIR}/usr/local/lib/pmemtester/cli.sh'
        usage
    "
    assert_success
    assert_output --partial "default: /usr/bin"
}

@test "make install without MEMTESTER_DIR keeps original default" {
    make -C "$PROJECT_ROOT" install DESTDIR="$INSTALL_DIR" PREFIX=/usr/local 2>/dev/null
    local installed="${INSTALL_DIR}/usr/local/bin/pmemtester"
    [[ -x "$installed" ]]

    run bash -c "
        source '${INSTALL_DIR}/usr/local/lib/pmemtester/cli.sh'
        usage
    "
    assert_success
    assert_output --partial "default: /usr/local/bin"
}
