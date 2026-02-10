setup_mock_dir() {
    MOCK_DIR="$(mktemp -d)"
    export PATH="${MOCK_DIR}:${PATH}"
}

create_mock() {
    local cmd_name="$1"
    local script_body="$2"
    cat > "${MOCK_DIR}/${cmd_name}" <<EOF
#!/usr/bin/env bash
${script_body}
EOF
    chmod +x "${MOCK_DIR}/${cmd_name}"
}

teardown_mock_dir() {
    [[ -d "${MOCK_DIR:-}" ]] && rm -rf "${MOCK_DIR}"
}
