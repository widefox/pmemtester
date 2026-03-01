#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# System detection utilities for pmemtester
# Reads RAM info from /proc/meminfo and core count from lscpu.

PROC_MEMINFO="${PROC_MEMINFO:-/proc/meminfo}"
SYS_CPU_BASE="${SYS_CPU_BASE:-/sys/devices/system/cpu}"

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

# get_l3_cache_kb: return total L3 cache size in kB
# Primary: sysfs (iterate index dirs, find level=3, read size).
# Fallback: getconf LEVEL3_CACHE_SIZE (returns bytes).
# Returns 1 on failure; caller should use a fallback size.
get_l3_cache_kb() {
    local cache_dir="${SYS_CPU_BASE}/cpu0/cache"

    # Primary: sysfs — iterate index dirs, find the one with level=3
    if [[ -d "$cache_dir" ]]; then
        local idx_dir
        for idx_dir in "${cache_dir}"/index*/; do
            [[ -d "$idx_dir" ]] || continue
            local level_file="${idx_dir}level"
            [[ -f "$level_file" ]] || continue
            local level
            level="$(cat "$level_file")"
            if [[ "$level" == "3" ]]; then
                local size_str
                size_str="$(cat "${idx_dir}size")"
                # Format: NNNNk or NNNNK — strip trailing K/k
                local size_kb="${size_str%%[Kk]}"
                if [[ "$size_kb" -gt 0 ]] 2>/dev/null; then
                    echo "$size_kb"
                    return 0
                fi
            fi
        done
    fi

    # Fallback: getconf LEVEL3_CACHE_SIZE (returns bytes)
    local bytes
    if bytes="$(getconf LEVEL3_CACHE_SIZE 2>/dev/null)" && [[ "$bytes" -gt 0 ]] 2>/dev/null; then
        echo $(( bytes / 1024 ))
        return 0
    fi

    return 1
}
