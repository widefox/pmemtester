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

# compare_edac_counters: diff before/after counter captures
# Usage: compare_edac_counters <before_file> <after_file>
compare_edac_counters() {
    local before="$1" after="$2"
    if ! diff -q "$before" "$after" >/dev/null 2>&1; then
        echo "ERROR: EDAC counters changed:" >&2
        diff "$before" "$after" >&2
        return 1
    fi
    return 0
}
