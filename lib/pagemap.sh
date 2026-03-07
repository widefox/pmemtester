#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Virtual-to-physical address translation via /proc/PID/pagemap

PROC_BASE="${PROC_BASE:-/proc}"
PAGE_SIZE="${PAGE_SIZE:-4096}"
PAGEMAP_SAMPLE_STRIDE="${PAGEMAP_SAMPLE_STRIDE:-512}"

# check_pagemap_readable: verify /proc/PID/pagemap exists and is readable
# Returns 0 if readable, 1 if not (requires root/CAP_SYS_ADMIN since kernel 4.0)
# Usage: check_pagemap_readable <pid>
check_pagemap_readable() {
    local pid="$1"
    local pagemap_file="${PROC_BASE}/${pid}/pagemap"
    [[ -r "$pagemap_file" ]]
}

# extract_pfn_from_entry: extract PFN from a 16-character hex pagemap entry string
# Bit 63 = present/swapped. Bits 0-54 = PFN.
# Outputs PFN (decimal) if present (bit 63 set), "not_present" otherwise.
# Usage: extract_pfn_from_entry <hex_entry>
extract_pfn_from_entry() {
    local hex_entry="$1"
    # Check bit 63: first hex digit >= 8 means bit 63 is set
    local first_char="${hex_entry:0:1}"
    local first_val=$(( 16#${first_char} ))
    if (( first_val < 8 )); then
        echo "not_present"
        return 0
    fi
    # Mask to bits 0-54: clear bits 55-63
    # Bits 55-63 are the top 9 bits of the 64-bit value
    # PFN mask = 0x007FFFFFFFFFFFFF
    # In bash: strip the top nibble's contribution above bit 54
    # The entry is 16 hex chars = 64 bits. Bits 55-63 = top 2.25 nibbles.
    # Mask bits 0-54 from the third hex char onwards.
    # Bit 55 is in the second hex char (bits 56-59 are char[1], bits 52-55 are char[2])
    # Actually: hex_entry[0] = bits 60-63, hex_entry[1] = bits 56-59, hex_entry[2] = bits 52-55
    # PFN is bits 0-54, so we need to mask hex_entry[2] to keep only bit 52-54 (lower 3 bits of that nibble)
    local char2="${hex_entry:2:1}"
    local char2_val=$(( 16#${char2} ))
    local char2_masked=$(( char2_val & 7 ))  # keep bits 0-2 of this nibble (= bits 52-54)
    local pfn_hex_masked
    printf -v pfn_hex_masked "%x%s" "$char2_masked" "${hex_entry:3:13}"
    echo $(( 16#${pfn_hex_masked} ))
}

# pfn_to_phys_addr: convert PFN to physical address (PFN * PAGE_SIZE)
# Outputs hex physical address (without 0x prefix)
# Usage: pfn_to_phys_addr <pfn_decimal>
pfn_to_phys_addr() {
    local pfn="$1"
    local phys_addr=$(( pfn * PAGE_SIZE ))
    printf "%x\n" "$phys_addr"
}

# read_pagemap_entry: read a single pagemap entry for a virtual address
# Calculates offset = (vaddr / PAGE_SIZE) * 8, reads 8 bytes via od
# Outputs PFN (decimal) or "not_present"
# Usage: read_pagemap_entry <pid> <virtual_address_decimal>
read_pagemap_entry() {
    local pid="$1" vaddr="$2"
    local pagemap_file="${PROC_BASE}/${pid}/pagemap"
    [[ -r "$pagemap_file" ]] || return 1

    local page_num=$(( vaddr / PAGE_SIZE ))
    local offset=$(( page_num * 8 ))

    # Read 8 bytes as a single 64-bit hex value (native byte order)
    local hex_entry
    hex_entry="$(od -A n -t x8 -j "$offset" -N 8 "$pagemap_file" 2>/dev/null | tr -d ' \n')"
    [[ -n "$hex_entry" ]] || return 1

    # Pad to 16 chars
    while [[ ${#hex_entry} -lt 16 ]]; do hex_entry="0${hex_entry}"; done

    extract_pfn_from_entry "$hex_entry"
}

# read_pagemap_range: sample pagemap entries across a VMA range
# Reads pagemap for pages at every <stride> interval within [start_hex, end_hex).
# Outputs "vaddr_hex:pfn_decimal:phys_addr_hex" lines, skipping not_present pages.
# Usage: read_pagemap_range <pid> <start_hex> <end_hex> <sample_stride>
read_pagemap_range() {
    local pid="$1" start_hex="$2" end_hex="$3" stride="$4"
    local pagemap_file="${PROC_BASE}/${pid}/pagemap"
    [[ -r "$pagemap_file" ]] || return 1

    local start_dec=$(( 16#${start_hex} ))
    local end_dec=$(( 16#${end_hex} ))
    local start_page=$(( start_dec / PAGE_SIZE ))
    local end_page=$(( end_dec / PAGE_SIZE ))
    local num_pages=$(( end_page - start_page ))

    [[ "$num_pages" -gt 0 ]] || return 0

    local file_offset=$(( start_page * 8 ))

    local page_idx=0
    while (( page_idx < num_pages )); do
        local entry_offset=$(( file_offset + page_idx * 8 ))
        local hex_entry
        hex_entry="$(od -A n -t x8 -j "$entry_offset" -N 8 "$pagemap_file" 2>/dev/null | tr -d ' \n')"
        [[ -n "$hex_entry" ]] || { page_idx=$(( page_idx + stride )); continue; }

        # Pad to 16 chars
        while [[ ${#hex_entry} -lt 16 ]]; do hex_entry="0${hex_entry}"; done

        local pfn
        pfn="$(extract_pfn_from_entry "$hex_entry")"
        if [[ "$pfn" != "not_present" ]]; then
            local vaddr=$(( (start_page + page_idx) * PAGE_SIZE ))
            local vaddr_hex phys_hex
            printf -v vaddr_hex "%08x" "$vaddr"
            phys_hex="$(pfn_to_phys_addr "$pfn")"
            echo "${vaddr_hex}:${pfn}:${phys_hex}"
        fi

        page_idx=$(( page_idx + stride ))
    done
}

# capture_thread_pagemap: snapshot pagemap for one memtester thread
# Finds VMA range, samples pagemap, writes to log_dir/thread_N_pagemap.txt
# Usage: capture_thread_pagemap <pid> <thread_id> <log_dir>
capture_thread_pagemap() {
    local pid="$1" thread_id="$2" log_dir="$3"
    local outfile="${log_dir}/thread_${thread_id}_pagemap.txt"

    if ! check_pagemap_readable "$pid"; then
        echo "not_available" > "$outfile"
        return 0
    fi

    local vma_range
    if ! vma_range="$(get_vma_range "$pid")"; then
        echo "not_available" > "$outfile"
        return 0
    fi

    local start_hex end_hex
    read -r start_hex end_hex <<< "$vma_range"

    local entries
    entries="$(read_pagemap_range "$pid" "$start_hex" "$end_hex" "$PAGEMAP_SAMPLE_STRIDE")"

    if [[ -z "$entries" ]]; then
        echo "not_available" > "$outfile"
        return 0
    fi

    # Compute min/max physical addresses
    local min_phys="" max_phys="" page_count=0
    local line phys_hex
    while IFS= read -r line; do
        phys_hex="${line##*:}"
        page_count=$(( page_count + 1 ))
        if [[ -z "$min_phys" ]] || [[ $(( 16#${phys_hex} )) -lt $(( 16#${min_phys} )) ]]; then
            min_phys="$phys_hex"
        fi
        if [[ -z "$max_phys" ]] || [[ $(( 16#${phys_hex} )) -gt $(( 16#${max_phys} )) ]]; then
            max_phys="$phys_hex"
        fi
    done <<< "$entries"

    {
        echo "# min_phys=${min_phys} max_phys=${max_phys} pages=${page_count}"
        echo "$entries"
    } > "$outfile"
}

# capture_all_pagemaps: iterate MEMTESTER_PIDS[] and capture each
# Reads global MEMTESTER_PIDS array.
# Usage: capture_all_pagemaps <log_dir>
capture_all_pagemaps() {
    local log_dir="$1"
    local i=0
    for pid in "${MEMTESTER_PIDS[@]}"; do
        capture_thread_pagemap "$pid" "$i" "$log_dir"
        i=$(( i + 1 ))
    done
}

# format_physical_report: format pagemap data as human-readable report
# Reads thread_N_pagemap.txt, outputs min/max physical address, page count.
# Usage: format_physical_report <pagemap_file>
format_physical_report() {
    local pagemap_file="$1"
    local first_line
    first_line="$(head -1 "$pagemap_file")"

    if [[ "$first_line" == "not_available" ]]; then
        echo "not_available"
        return 0
    fi

    # Parse header: # min_phys=X max_phys=Y pages=Z
    local min_phys max_phys pages
    min_phys="$(echo "$first_line" | sed -n 's/.*min_phys=\([^ ]*\).*/\1/p')"
    max_phys="$(echo "$first_line" | sed -n 's/.*max_phys=\([^ ]*\).*/\1/p')"
    pages="$(echo "$first_line" | sed -n 's/.*pages=\([^ ]*\).*/\1/p')"

    echo "Physical address range: 0x${min_phys} - 0x${max_phys} (${pages} sampled pages)"
}

# report_physical_mapping: print physical mapping report for all threads
# Usage: report_physical_mapping <log_dir> <num_threads>
report_physical_mapping() {
    local log_dir="$1" num_threads="$2"
    local i
    echo "--- Physical Address Mapping ---"
    for (( i = 0; i < num_threads; i++ )); do
        local pagemap_file="${log_dir}/thread_${i}_pagemap.txt"
        if [[ -f "$pagemap_file" ]]; then
            local report
            report="$(format_physical_report "$pagemap_file")"
            echo "  Thread ${i}: ${report}"
        fi
    done
}

# get_vma_range: find the largest anonymous rw-p mapping in /proc/PID/maps
# This is memtester's mmap'd test region (anonymous, read-write, private).
# Anonymous = no pathname (columns after inode are empty), not [stack]/[heap]/etc.
# Outputs "start_hex end_hex" or returns 1 on failure.
# Usage: get_vma_range <pid>
get_vma_range() {
    local pid="$1"
    local maps_file="${PROC_BASE}/${pid}/maps"
    [[ -f "$maps_file" ]] || return 1

    local result
    result="$(awk '
        /rw-p/ {
            # Check if this is anonymous: no pathname after the inode field
            # Format: start-end perms offset dev inode [pathname]
            # Anonymous mappings have no pathname or have special names like [stack]
            # We want: no pathname at all (NF == 5 when split by space, but
            # the format uses variable whitespace, so check $6)
            if (NF == 5 || (NF >= 6 && $6 ~ /^$/)) {
                # No pathname - truly anonymous
                split($1, addr, "-")
                # Use shell-safe decimal conversion via printf
                cmd = "printf \"%d\" 0x" addr[1]
                cmd | getline start_dec
                close(cmd)
                cmd = "printf \"%d\" 0x" addr[2]
                cmd | getline end_dec
                close(cmd)
                size = end_dec - start_dec
                if (size > max_size) {
                    max_size = size
                    max_start = addr[1]
                    max_end = addr[2]
                }
            }
        }
        END {
            if (max_size > 0) print max_start, max_end
        }
    ' "$maps_file")"

    [[ -n "$result" ]] || return 1
    echo "$result"
}
