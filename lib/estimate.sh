#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Time estimation utilities for pmemtester
# Requires: timing.sh, logging.sh, unit_convert.sh

# estimate_duration: scale calibration time linearly
# Formula: cal_secs * ram_per_core_mb * iterations / calibration_mb
# Multiply before divide to preserve integer precision.
# Usage: estimate_duration <calibration_seconds> <calibration_mb> <ram_per_core_mb> <iterations>
estimate_duration() {
    local cal_secs="$1" cal_mb="$2" ram_mb="$3" iters="$4"
    echo $(( cal_secs * ram_mb * iters / cal_mb ))
}

# run_calibration: run memtester for 1 iteration at calibration_mb, return wall-clock seconds
# Logging stays ON (output captured to calibration.log).
# Usage: run_calibration <memtester_path> <log_dir> <calibration_mb>
run_calibration() {
    local memtester_path="$1" log_dir="$2" cal_mb="$3"
    local start_secs=$SECONDS

    "$memtester_path" "${cal_mb}M" 1 > "${log_dir}/calibration.log" 2>&1 || return 1

    local elapsed=$(( SECONDS - start_secs ))
    # Clamp minimum to 1 to avoid division-by-zero in downstream math
    if [[ "$elapsed" -lt 1 ]]; then
        elapsed=1
    fi
    echo "$elapsed"
}

# print_estimate: display and log estimated completion time
# Uses format_duration and format_eta from timing.sh, print_status from timing.sh
# Usage: print_estimate <estimated_seconds> <log_dir>
print_estimate() {
    local est_secs="$1" log_dir="$2"
    print_status "Estimated completion: ~$(format_duration "$est_secs") (ETA: $(format_eta "$est_secs"))" "$log_dir"
}
