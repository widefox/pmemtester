#!/usr/bin/env bash
# Memtester binary discovery and validation

# find_memtester: locate the memtester binary
# Usage: find_memtester [search_dir]
find_memtester() {
    local search_dir="${1:-/usr/local/bin}"
    local path="${search_dir}/memtester"
    if [[ -x "$path" ]]; then
        echo "$path"
        return 0
    fi
    echo "ERROR: memtester not found at ${path}" >&2
    return 1
}

# validate_memtester: check that path is an executable file
# Usage: validate_memtester <path>
validate_memtester() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: memtester not found: ${path}" >&2
        return 1
    fi
    if [[ ! -x "$path" ]]; then
        echo "ERROR: memtester not executable: ${path}" >&2
        return 1
    fi
    return 0
}
