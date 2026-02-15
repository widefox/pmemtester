#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# stressapptest binary discovery, validation, and execution
# Requires: logging.sh

# find_stressapptest: locate the stressapptest binary
# Usage: find_stressapptest [search_dir]
find_stressapptest() {
    local search_dir="${1:-/usr/local/bin}"
    local path="${search_dir}/stressapptest"
    if [[ -x "$path" ]]; then
        echo "$path"
        return 0
    fi
    echo "ERROR: stressapptest not found at ${path}" >&2
    return 1
}

# validate_stressapptest: check that path is an executable file
# Usage: validate_stressapptest <path>
validate_stressapptest() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: stressapptest not found: ${path}" >&2
        return 1
    fi
    if [[ ! -x "$path" ]]; then
        echo "ERROR: stressapptest not executable: ${path}" >&2
        return 1
    fi
    return 0
}

# run_stressapptest: execute stressapptest and log results
# Usage: run_stressapptest <path> <seconds> <size_mb> <threads> <log_dir>
run_stressapptest() {
    local path="$1" seconds="$2" size_mb="$3" threads="$4" log_dir="$5"
    local log_file="${log_dir}/stressapptest.log"

    log_master "Starting stressapptest: ${size_mb}MB, ${seconds}s, ${threads} threads" "$log_dir"

    if "$path" -s "$seconds" -M "$size_mb" -m "$threads" > "$log_file" 2>&1; then
        log_master "stressapptest PASSED" "$log_dir"
        return 0
    else
        local rc=$?
        log_master "stressapptest FAILED (exit code ${rc})" "$log_dir"
        return 1
    fi
}
