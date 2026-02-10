#!/usr/bin/env bash
# Logging utilities for pmemtester
# Provides per-thread logs and an aggregated master log.

# init_logs: create log directory and master.log
# Usage: init_logs <log_dir> <num_threads>
init_logs() {
    local log_dir="$1" num_threads="$2"
    if ! mkdir -p "$log_dir" 2>/dev/null; then
        echo "ERROR: cannot create log directory: ${log_dir}" >&2
        return 1
    fi
    : > "${log_dir}/master.log"
}

# log_msg: append a timestamped message to a log file
# Usage: log_msg <level> <message> <log_file>
log_msg() {
    local level="$1" message="$2" log_file="$3"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "$log_file"
}

# log_master: log to master.log
# Usage: log_master <message> <log_dir>
log_master() {
    log_msg "INFO" "$1" "${2}/master.log"
}

# log_thread: log to thread_N.log
# Usage: log_thread <thread_id> <message> <log_dir>
log_thread() {
    local thread_id="$1" message="$2" log_dir="$3"
    log_msg "INFO" "$message" "${log_dir}/thread_${thread_id}.log"
}

# aggregate_logs: append all thread logs into master.log
# Usage: aggregate_logs <log_dir> <num_threads>
aggregate_logs() {
    local log_dir="$1" num_threads="$2"
    local i
    for (( i = 0; i < num_threads; i++ )); do
        local thread_log="${log_dir}/thread_${i}.log"
        if [[ -f "$thread_log" ]]; then
            echo "--- Thread ${i} ---" >> "${log_dir}/master.log"
            cat "$thread_log" >> "${log_dir}/master.log"
        fi
    done
}
