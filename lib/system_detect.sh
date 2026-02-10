#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# System detection utilities for pmemtester
# Reads RAM info from /proc/meminfo and thread count from nproc.

PROC_MEMINFO="${PROC_MEMINFO:-/proc/meminfo}"

# _read_meminfo_field: extract a numeric kB value from /proc/meminfo
# Usage: _read_meminfo_field <field_name>
_read_meminfo_field() {
    local field="$1"
    local value
    value="$(awk -v f="${field}:" '$1 == f { print $2 }' "$PROC_MEMINFO")"
    if [[ -z "$value" ]]; then
        echo "ERROR: field '${field}' not found in ${PROC_MEMINFO}" >&2
        return 1
    fi
    echo "$value"
}

get_total_ram_kb() { _read_meminfo_field "MemTotal"; }
get_free_ram_kb() { _read_meminfo_field "MemFree"; }
get_available_ram_kb() { _read_meminfo_field "MemAvailable"; }

# get_thread_count: return CPU thread count via nproc
get_thread_count() {
    local count
    if ! count="$(nproc 2>/dev/null)"; then
        echo "ERROR: nproc failed" >&2
        return 1
    fi
    echo "$count"
}
