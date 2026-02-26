#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Unit conversion utilities for pmemtester
# All values are integers. Conversions use floor division (truncation).

kb_to_mb() { echo $(( $1 / 1024 )); }
mb_to_kb() { echo $(( $1 * 1024 )); }
bytes_to_kb() { echo $(( $1 / 1024 )); }
kb_to_bytes() { echo $(( $1 * 1024 )); }
mb_to_memtester_arg() { echo "${1}M"; }

# parse_size_to_kb: parse a size string with unit suffix to kB
# Accepts K/k, M/m, G/g, T/t suffixes. Bare numbers rejected.
# Usage: parse_size_to_kb <size_string>
parse_size_to_kb() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "ERROR: --size value is empty" >&2
        return 1
    fi

    # Reject bare numbers (digits only, no suffix)
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --size requires a unit suffix (K, M, G, or T), got '${input}'" >&2
        return 1
    fi

    if [[ ! "$input" =~ ^([0-9]+)([KkMmGgTt])$ ]]; then
        echo "ERROR: --size must be a positive integer with K, M, G, or T suffix (got '${input}')" >&2
        return 1
    fi

    local number="${BASH_REMATCH[1]}"
    local suffix="${BASH_REMATCH[2]}"

    if [[ "$number" -eq 0 ]]; then
        echo "ERROR: --size must be > 0 (got '${input}')" >&2
        return 1
    fi

    case "$suffix" in
        [Kk]) echo "$number" ;;
        [Mm]) echo $(( number * 1024 )) ;;
        [Gg]) echo $(( number * 1048576 )) ;;
        [Tt]) echo $(( number * 1073741824 )) ;;
    esac
}
