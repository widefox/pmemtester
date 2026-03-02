#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# EDAC (Error Detection and Correction) monitoring for pmemtester
# Checks dmesg messages and sysfs counters for hardware memory errors.

EDAC_BASE="${EDAC_BASE:-/sys/devices/system/edac}"

# check_edac_supported: verify EDAC sysfs directory exists
check_edac_supported() {
    if [[ ! -d "${EDAC_BASE}/mc" ]]; then
        echo "ERROR: EDAC not available at ${EDAC_BASE}/mc" >&2
        return 1
    fi
    return 0
}

# capture_edac_messages: extract EDAC lines from dmesg
capture_edac_messages() {
    local output
    if ! output="$(dmesg 2>&1)"; then
        echo "ERROR: dmesg failed" >&2
        return 1
    fi
    echo "$output" | grep -i "EDAC" || true
}

# capture_edac_counters: read all ce_count and ue_count from sysfs
capture_edac_counters() {
    local base="${EDAC_BASE}/mc"
    find "$base" -name "*_count" -type f 2>/dev/null | sort | while read -r f; do
        local rel="${f#"${base}"/}"
        echo "${rel}:$(cat "$f")"
    done
}

# compare_edac_messages: diff before/after message captures
# Usage: compare_edac_messages <before_file> <after_file>
compare_edac_messages() {
    local before="$1" after="$2"
    if ! diff -q "$before" "$after" >/dev/null 2>&1; then
        echo "ERROR: new EDAC messages detected:" >&2
        diff "$before" "$after" >&2
        return 1
    fi
    return 0
}

# classify_edac_counters: classify counter changes as ce_only, ue_only, ce_and_ue, or none
# Reads path:value format from capture_edac_counters output files.
# Outputs classification to stdout, detail to stderr.
# Returns 0 if "none", 1 otherwise.
# Usage: classify_edac_counters <before_file> <after_file>
classify_edac_counters() {
    local before="$1" after="$2"
    local has_ce=0 has_ue=0

    # Build associative array of before values
    declare -A before_vals
    while IFS=: read -r path val; do
        [[ -z "$path" ]] && continue
        before_vals["$path"]="$val"
    done < "$before"

    # Compare with after values
    while IFS=: read -r path val; do
        [[ -z "$path" ]] && continue
        local prev="${before_vals[$path]:-0}"
        local delta=$(( val - prev ))
        if [[ "$delta" -gt 0 ]]; then
            case "$path" in
                *ce_count)
                    has_ce=1
                    echo "CE: ${path} ${prev} -> ${val} (+${delta})" >&2
                    ;;
                *ue_count)
                    has_ue=1
                    echo "UE: ${path} ${prev} -> ${val} (+${delta})" >&2
                    ;;
            esac
        fi
    done < "$after"

    if [[ "$has_ce" -eq 1 ]] && [[ "$has_ue" -eq 1 ]]; then
        echo "ce_and_ue"
        return 1
    elif [[ "$has_ce" -eq 1 ]]; then
        echo "ce_only"
        return 1
    elif [[ "$has_ue" -eq 1 ]]; then
        echo "ue_only"
        return 1
    else
        echo "none"
        return 0
    fi
}

# poll_edac_for_ue: background EDAC UE polling loop for --stop-on-error
# Writes "ue" to sentinel_file if a UE counter increase is detected.
# Exits immediately if sentinel_file already contains "stop".
# Usage: poll_edac_for_ue <baseline_file> <sentinel_file> <interval_seconds>
poll_edac_for_ue() {
    local baseline_file="$1" sentinel_file="$2" interval="$3"

    while true; do
        # Stop if sentinel says so
        if [[ -f "$sentinel_file" ]] && [[ "$(cat "$sentinel_file")" == "stop" ]]; then
            return 0
        fi

        [[ "$interval" -gt 0 ]] && sleep "$interval"

        local tmp
        tmp="$(mktemp)"
        capture_edac_counters > "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }

        local classification
        classification="$(classify_edac_counters "$baseline_file" "$tmp" 2>/dev/null)" || true
        rm -f "$tmp"

        case "$classification" in
            ue_only|ce_and_ue)
                echo "ue" > "$sentinel_file"
                return 0
                ;;
        esac
    done
}
