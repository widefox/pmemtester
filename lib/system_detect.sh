#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# System detection utilities for pmemtester
# Reads RAM info from /proc/meminfo and core count from lscpu.

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

# get_core_count: return physical CPU core count via lscpu, fallback to nproc
get_core_count() {
    local count

    # Primary: lscpu provides unique socket,core pairs (physical cores)
    if count="$(lscpu -b -p=Socket,Core 2>/dev/null | grep -v '^#' | sort -u | wc -l)" \
       && [[ "$count" -gt 0 ]]; then
        echo "$count"
        return 0
    fi

    # Fallback: nproc (returns hardware threads, not cores, but better than nothing)
    if count="$(nproc 2>/dev/null)" && [[ "$count" -gt 0 ]]; then
        echo "$count"
        return 0
    fi

    echo "ERROR: cannot determine CPU core count (lscpu and nproc both failed)" >&2
    return 1
}
