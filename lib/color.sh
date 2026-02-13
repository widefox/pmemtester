#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Coloured terminal output for pmemtester
# Supports auto-detection, forced on/off, and NO_COLOR convention.

COLOR_ENABLED=0

# ANSI escape sequences (set by color_init)
_C_GREEN=""
_C_RED=""
_C_YELLOW=""
_C_RESET=""

# _stdout_is_tty: check if stdout is a terminal (testable wrapper)
_stdout_is_tty() {
    [[ -t 1 ]]
}

# color_init: resolve COLOR_MODE into COLOR_ENABLED and set escape sequences
# Call after parse_args sets COLOR_MODE.
color_init() {
    case "${COLOR_MODE:-auto}" in
        on)
            COLOR_ENABLED=1
            ;;
        off)
            COLOR_ENABLED=0
            ;;
        auto)
            if [[ -n "${NO_COLOR:-}" ]]; then
                COLOR_ENABLED=0
            elif [[ -z "${TERM:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
                COLOR_ENABLED=0
            elif _stdout_is_tty; then
                COLOR_ENABLED=1
            else
                COLOR_ENABLED=0
            fi
            ;;
    esac

    if [[ "$COLOR_ENABLED" -eq 1 ]]; then
        _C_GREEN=$'\033[32m'
        _C_RED=$'\033[31m'
        _C_YELLOW=$'\033[33m'
        _C_RESET=$'\033[0m'
    else
        _C_GREEN=""
        _C_RED=""
        _C_YELLOW=""
        _C_RESET=""
    fi
}

# color_pass: print coloured PASS verdict
color_pass() {
    echo "${_C_GREEN}PASS${_C_RESET}"
}

# color_fail: print coloured FAIL verdict with optional source
# Usage: color_fail [source]
color_fail() {
    local source="${1:-}"
    if [[ -n "$source" ]]; then
        echo "${_C_RED}FAIL${_C_RESET} (${source})"
    else
        echo "${_C_RED}FAIL${_C_RESET}"
    fi
}

# color_warn: print coloured WARNING with message
# Usage: color_warn <message>
color_warn() {
    local message="${1:-}"
    echo "${_C_YELLOW}WARNING${_C_RESET}: ${message}"
}
