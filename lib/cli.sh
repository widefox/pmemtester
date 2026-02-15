#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# CLI argument parsing for pmemtester

# Defaults (globals consumed by main script)
PERCENT=90
RAM_TYPE="available"
# DEFAULT_MEMTESTER_DIR is patched by 'make install MEMTESTER_DIR=/path' to bake
# in a distro-appropriate default (e.g., /usr/bin on Fedora, Debian, Arch, etc.)
DEFAULT_MEMTESTER_DIR="${DEFAULT_MEMTESTER_DIR:-/usr/local/bin}"
# shellcheck disable=SC2034
MEMTESTER_DIR="$DEFAULT_MEMTESTER_DIR"
# shellcheck disable=SC2034
LOG_DIR=""
ITERATIONS=1
ALLOW_CE=0
COLOR_MODE="auto"
# DEFAULT_STRESSAPPTEST_DIR is patched by 'make install STRESSAPPTEST_DIR=/path'
DEFAULT_STRESSAPPTEST_DIR="${DEFAULT_STRESSAPPTEST_DIR:-/usr/local/bin}"
# shellcheck disable=SC2034
STRESSAPPTEST_DIR="$DEFAULT_STRESSAPPTEST_DIR"
# shellcheck disable=SC2034
STRESSAPPTEST_MODE="auto"
# shellcheck disable=SC2034
STRESSAPPTEST_SECONDS=0

# usage: print help text
usage() {
    cat <<EOF
Usage: pmemtester ${pmemtester_version:-unknown} [OPTIONS]

Options:
  --percent N         Percentage of RAM to test (1-100, default: 90)
  --ram-type TYPE     RAM measurement: available (default), total, free
  --memtester-dir DIR Directory containing memtester binary (default: ${DEFAULT_MEMTESTER_DIR})
  --log-dir DIR       Directory for log files (default: /tmp/pmemtester.PID)
  --iterations N      Number of memtester iterations (default: 1)
  --allow-ce          Allow correctable EDAC errors (CE); only fail on uncorrectable (UE)
  --color MODE        Coloured output: auto (default), on, off
  --stressapptest MODE  stressapptest pass: auto (default), on, off
  --stressapptest-seconds N  stressapptest duration (0 = use memtester time, default: 0)
  --stressapptest-dir DIR  Directory containing stressapptest binary (default: ${DEFAULT_STRESSAPPTEST_DIR})
  --version           Show version
  --help              Show this help message
EOF
}

# parse_args: parse command-line arguments into global variables
# shellcheck disable=SC2034
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --percent)    PERCENT="$2"; shift 2 ;;
            --ram-type)   RAM_TYPE="$2"; shift 2 ;;
            --memtester-dir) MEMTESTER_DIR="$2"; shift 2 ;;
            --log-dir)    LOG_DIR="$2"; shift 2 ;;
            --iterations) ITERATIONS="$2"; shift 2 ;;
            --allow-ce)   ALLOW_CE=1; shift ;;
            --color)      COLOR_MODE="$2"; shift 2 ;;
            --stressapptest) STRESSAPPTEST_MODE="$2"; shift 2 ;;
            --stressapptest-seconds) STRESSAPPTEST_SECONDS="$2"; shift 2 ;;
            --stressapptest-dir) STRESSAPPTEST_DIR="$2"; shift 2 ;;
            --version)    echo "pmemtester ${pmemtester_version:-unknown}"; exit 0 ;;
            --help)       usage; exit 0 ;;
            *)
                echo "ERROR: unknown option: $1" >&2
                return 1
                ;;
        esac
    done
}

# validate_args: validate parsed arguments
validate_args() {
    if [[ "$PERCENT" -le 0 ]] || [[ "$PERCENT" -gt 100 ]]; then
        echo "ERROR: --percent must be 1-100 (got ${PERCENT})" >&2
        return 1
    fi
    case "$RAM_TYPE" in
        available|total|free) : ;;
        *)
            echo "ERROR: --ram-type must be available, total, or free (got ${RAM_TYPE})" >&2
            return 1
            ;;
    esac
    if [[ "$ITERATIONS" -le 0 ]]; then
        echo "ERROR: --iterations must be > 0 (got ${ITERATIONS})" >&2
        return 1
    fi
    case "$COLOR_MODE" in
        auto|on|off) : ;;
        *)
            echo "ERROR: --color must be auto, on, or off (got ${COLOR_MODE})" >&2
            return 1
            ;;
    esac
    case "$STRESSAPPTEST_MODE" in
        auto|on|off) : ;;
        *)
            echo "ERROR: --stressapptest must be auto, on, or off (got ${STRESSAPPTEST_MODE})" >&2
            return 1
            ;;
    esac
    if [[ "$STRESSAPPTEST_SECONDS" -lt 0 ]]; then
        echo "ERROR: --stressapptest-seconds must be >= 0 (got ${STRESSAPPTEST_SECONDS})" >&2
        return 1
    fi
    return 0
}
