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

# parse_edac_error_addresses: extract physical addresses from dmesg EDAC error messages
# Parses "page:0xNNN offset:0xNNN" patterns from EDAC error messages.
# Outputs "page_hex offset_hex mc_id" lines.
# Usage: parse_edac_error_addresses <dmesg_output_file>
parse_edac_error_addresses() {
    local dmesg_file="$1"
    [[ -f "$dmesg_file" ]] || return 0

    awk '
        /EDAC/ && /page:0x/ {
            mc = ""
            if (match($0, /EDAC MC([0-9]+)/, m)) {
                mc = "MC" m[1]
            } else if (match($0, /MC([0-9]+)/)) {
                mc = substr($0, RSTART, RLENGTH)
            }
            page = ""
            offset = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^page:0x/) {
                    sub(/^page:/, "", $i)
                    page = $i
                }
                if ($i ~ /^offset:0x/) {
                    sub(/^offset:/, "", $i)
                    offset = $i
                }
            }
            if (page != "") {
                if (offset == "") offset = "0x0"
                print page, offset, mc
            }
        }
    ' "$dmesg_file"
}

# format_edac_dimm_topology: list EDAC memory controller topology
# Walks ${EDAC_BASE}/mc/ tree, reads dimm_label if available.
# Outputs human-readable MC/csrow/channel listing.
# Usage: format_edac_dimm_topology
format_edac_dimm_topology() {
    local base="${EDAC_BASE}/mc"
    [[ -d "$base" ]] || return 1

    local mc_dir
    for mc_dir in "$base"/mc*; do
        [[ -d "$mc_dir" ]] || continue
        local mc_name="${mc_dir##*/}"
        echo "${mc_name}:"
        local csrow_dir
        for csrow_dir in "$mc_dir"/csrow*; do
            [[ -d "$csrow_dir" ]] || continue
            local csrow_name="${csrow_dir##*/}"
            local ce_count ue_count
            ce_count="$(cat "$csrow_dir/ce_count" 2>/dev/null)" || ce_count="?"
            ue_count="$(cat "$csrow_dir/ue_count" 2>/dev/null)" || ue_count="?"
            echo "  ${csrow_name}: ce=${ce_count} ue=${ue_count}"
            # Check for dimm labels
            local label_file
            for label_file in "$csrow_dir"/ch*_dimm_label; do
                [[ -f "$label_file" ]] || continue
                local ch_name="${label_file##*/}"
                ch_name="${ch_name%_dimm_label}"
                local label
                label="$(cat "$label_file")"
                echo "    ${ch_name}: ${label}"
            done
        done
    done
}

# correlate_physical_to_edac: correlate physical address range with EDAC errors
# Reads a pagemap summary file and an EDAC dmesg file, checks for overlap.
# Outputs correlation report.
# Usage: correlate_physical_to_edac <pagemap_file> <edac_msg_file>
correlate_physical_to_edac() {
    local pagemap_file="$1" edac_msg_file="$2"

    # Read pagemap min/max from header
    local header
    header="$(head -1 "$pagemap_file")"
    local min_phys max_phys
    min_phys="$(echo "$header" | sed -n 's/.*min_phys=\([^ ]*\).*/\1/p')"
    max_phys="$(echo "$header" | sed -n 's/.*max_phys=\([^ ]*\).*/\1/p')"

    if [[ -z "$min_phys" ]] || [[ -z "$max_phys" ]]; then
        echo "Correlation: pagemap data not available"
        return 0
    fi

    local min_dec=$(( 16#${min_phys} ))
    local max_dec=$(( 16#${max_phys} ))

    # Parse EDAC error addresses
    local edac_addresses
    edac_addresses="$(parse_edac_error_addresses "$edac_msg_file")"

    if [[ -z "$edac_addresses" ]]; then
        echo "Correlation: no EDAC error addresses found in dmesg"
        return 0
    fi

    local found_overlap=0
    local page_hex offset_hex mc_id
    while read -r page_hex offset_hex mc_id; do
        [[ -z "$page_hex" ]] && continue
        # Compute physical address: page * 4096 + offset
        local page_dec=$(( 16#${page_hex#0x} ))
        local offset_dec=$(( 16#${offset_hex#0x} ))
        local error_phys=$(( page_dec * 4096 + offset_dec ))
        local error_phys_hex
        printf -v error_phys_hex "%x" "$error_phys"

        if (( error_phys >= min_dec && error_phys <= max_dec )); then
            echo "MATCH: ${mc_id} error at 0x${error_phys_hex} (page:${page_hex}) overlaps thread physical range 0x${min_phys}-0x${max_phys}"
            found_overlap=1
        else
            echo "INFO: ${mc_id} error at 0x${error_phys_hex} (page:${page_hex}) outside thread range"
        fi
    done <<< "$edac_addresses"

    if [[ "$found_overlap" -eq 0 ]]; then
        echo "Correlation: EDAC errors found but no overlap with thread physical range (no overlap)"
    fi
}
