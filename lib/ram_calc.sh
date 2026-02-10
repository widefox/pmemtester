#!/usr/bin/env bash
# RAM calculation for pmemtester
# Determines how much RAM to test and how to divide it among threads.
# Requires: math_utils.sh, unit_convert.sh, system_detect.sh

# calculate_test_ram_kb: calculate target test RAM in kB
# Usage: calculate_test_ram_kb <percent> <ram_type>
# ram_type: available | total | free
calculate_test_ram_kb() {
    local percent="$1" ram_type="$2"
    local base_kb

    case "$ram_type" in
        available) base_kb="$(get_available_ram_kb)" ;;
        total)     base_kb="$(get_total_ram_kb)" ;;
        free)      base_kb="$(get_free_ram_kb)" ;;
        *)
            echo "ERROR: invalid ram_type '${ram_type}' (use: available, total, free)" >&2
            return 1
            ;;
    esac

    percentage_of "$base_kb" "$percent"
}

# divide_ram_per_thread_mb: divide total kB among threads, return MB per thread
# Usage: divide_ram_per_thread_mb <total_kb> <num_threads>
divide_ram_per_thread_mb() {
    local total_kb="$1" num_threads="$2"
    local per_thread_kb per_thread_mb

    per_thread_kb=$(( total_kb / num_threads ))
    per_thread_mb=$(kb_to_mb "$per_thread_kb")

    if [[ "$per_thread_mb" -eq 0 ]]; then
        echo "ERROR: RAM per thread < 1 MB (${per_thread_kb} kB). Not enough RAM to test." >&2
        return 1
    fi

    echo "$per_thread_mb"
}

# validate_ram_params: validate RAM calculation parameters
# Usage: validate_ram_params <percent> <num_threads> <ram_per_thread_mb>
validate_ram_params() {
    local percent="$1" num_threads="$2" ram_per_thread_mb="$3"

    if [[ "$percent" -le 0 ]]; then
        echo "ERROR: percent must be > 0 (got ${percent})" >&2
        return 1
    fi
    if [[ "$percent" -gt 100 ]]; then
        echo "ERROR: percent must be <= 100 (got ${percent})" >&2
        return 1
    fi
    if [[ "$num_threads" -le 0 ]]; then
        echo "ERROR: thread count must be > 0 (got ${num_threads})" >&2
        return 1
    fi
    if [[ "$ram_per_thread_mb" -le 0 ]]; then
        echo "ERROR: RAM per thread must be > 0 MB (got ${ram_per_thread_mb})" >&2
        return 1
    fi
    return 0
}
