#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Timing and status output utilities for pmemtester
# Requires: logging.sh

# format_duration: convert seconds to human-readable duration
# Usage: format_duration <seconds>
format_duration() {
    local total_seconds="$1"
    if [[ "$total_seconds" -lt 60 ]]; then
        echo "${total_seconds}s"
    else
        local mins=$(( total_seconds / 60 ))
        local secs=$(( total_seconds % 60 ))
        echo "${mins}m ${secs}s"
    fi
}

# format_wallclock: return current wall-clock time
# Usage: format_wallclock
format_wallclock() {
    date '+%Y-%m-%d %H:%M:%S'
}

# format_eta: return wall-clock time N seconds from now
# Usage: format_eta <seconds_from_now>
format_eta() {
    local seconds_from_now="$1"
    date -d "+${seconds_from_now} seconds" '+%Y-%m-%d %H:%M:%S'
}

# print_status: write timestamped message to both stdout and master.log
# Usage: print_status <message> <log_dir>
print_status() {
    local message="$1" log_dir="$2"
    local timestamp
    timestamp="$(format_wallclock)"
    echo "[${timestamp}] ${message}"
    log_master "$message" "$log_dir"
}

# format_phase_result: summarise pass/fail for phase completion
# Usage: format_phase_result <total_instances> <fail_count>
format_phase_result() {
    local total="$1" failed="$2"
    if [[ "$failed" -eq 0 ]]; then
        echo "all ${total} instances passed"
    else
        echo "${failed} of ${total} instances FAILED"
    fi
}

# format_edac_summary: human-readable EDAC classification
# Usage: format_edac_summary <classification>
format_edac_summary() {
    local classification="$1"
    case "$classification" in
        none)       echo "no errors detected" ;;
        ce_only)    echo "correctable errors (CE) detected" ;;
        ue_only)    echo "uncorrectable errors (UE) detected" ;;
        ce_and_ue)  echo "correctable and uncorrectable errors detected" ;;
        *)          echo "unknown classification: ${classification}" ;;
    esac
}
