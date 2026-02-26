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
# shellcheck disable=SC2034
SIZE=""
# shellcheck disable=SC2034
PERCENT_SET=0

# usage: print help text
usage() {
    cat <<EOF
Usage: pmemtester ${pmemtester_version:-unknown} [OPTIONS]

Options:
  --percent N         Percentage of RAM to test (0.001-100, default: 90)
  --size SIZE         Total RAM to test: KiB/MiB/GiB/TiB (K, M, G, T suffix; e.g., 256M = 256 MiB)
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
            --percent)    PERCENT="$2"; PERCENT_SET=1; shift 2 ;;
            --size)       SIZE="$2"; shift 2 ;;
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
    # Mutual exclusion: --percent and --size
    if [[ "$PERCENT_SET" -eq 1 ]] && [[ -n "$SIZE" ]]; then
        echo "ERROR: --percent and --size are mutually exclusive" >&2
        return 1
    fi

    # Validate --size or --percent
    if [[ -n "$SIZE" ]]; then
        parse_size_to_kb "$SIZE" > /dev/null || return 1
    else
        # Validate percent via millipercent conversion
        local millipercent
        millipercent="$(decimal_to_millipercent "$PERCENT" 2>&1)" || {
            echo "ERROR: --percent must be 0.001-100 (got ${PERCENT})" >&2
            return 1
        }
        if [[ "$millipercent" -le 0 ]]; then
            echo "ERROR: --percent must be > 0 (got ${PERCENT})" >&2
            return 1
        fi
        if [[ "$millipercent" -gt 100000 ]]; then
            echo "ERROR: --percent must be <= 100 (got ${PERCENT})" >&2
            return 1
        fi
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
