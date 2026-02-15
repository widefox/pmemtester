#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Parallel memtester execution engine
# Requires: logging.sh

# Array to track background PIDs
MEMTESTER_PIDS=()

# run_memtester_instance: run a single memtester and log output
# Usage: run_memtester_instance <memtester_path> <size_arg> <iterations> <thread_id> <log_dir>
run_memtester_instance() {
    local memtester_path="$1" size_arg="$2" iterations="$3" thread_id="$4" log_dir="$5"
    local log_file="${log_dir}/thread_${thread_id}.log"

    log_thread "$thread_id" "Starting memtester: ${size_arg} x ${iterations} iterations" "$log_dir"

    if "$memtester_path" "$size_arg" "$iterations" >> "$log_file" 2>&1; then
        log_thread "$thread_id" "PASSED" "$log_dir"
        return 0
    else
        local rc=$?
        log_thread "$thread_id" "FAILED (exit code ${rc})" "$log_dir"
        return 1
    fi
}

# run_all_memtesters: launch memtester instances in background
# Usage: run_all_memtesters <memtester_path> <size_arg> <iterations> <num_threads> <log_dir>
run_all_memtesters() {
    local memtester_path="$1" size_arg="$2" iterations="$3" num_threads="$4" log_dir="$5"
    local i

    MEMTESTER_PIDS=()
    for (( i = 0; i < num_threads; i++ )); do
        run_memtester_instance "$memtester_path" "$size_arg" "$iterations" "$i" "$log_dir" &
        MEMTESTER_PIDS+=($!)
    done
}

# wait_and_collect: wait for all PIDs, return 0 if all pass, 1 if any fail
# Usage: wait_and_collect <log_dir>
wait_and_collect() {
    local log_dir="$1"
    local failed=0
    local i=0
    MEMTESTER_FAIL_COUNT=0

    for pid in "${MEMTESTER_PIDS[@]}"; do
        if ! wait "$pid"; then
            log_master "Thread ${i} FAILED" "$log_dir"
            MEMTESTER_FAIL_COUNT=$(( MEMTESTER_FAIL_COUNT + 1 ))
            failed=1
        fi
        i=$(( i + 1 ))
    done

    if [[ "$failed" -eq 1 ]]; then
        return 1
    fi
    return 0
}
