setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    load_lib pagemap.sh
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

# Helper: write an 8-byte little-endian pagemap entry to a file at a given offset
# Usage: write_pagemap_entry <file> <offset_bytes> <8-byte-hex-value-big-endian>
# Example: write_pagemap_entry f 0 "8000000000012345"
#   → writes bytes 45 23 01 00 00 00 00 80 at offset 0
write_pagemap_entry() {
    local file="$1" offset="$2" hex_be="$3"
    # Pad to 16 hex chars
    while [[ ${#hex_be} -lt 16 ]]; do hex_be="0${hex_be}"; done
    # Convert big-endian hex to little-endian bytes
    local i byte
    for (( i = 14; i >= 0; i -= 2 )); do
        byte="${hex_be:$i:2}"
        printf "\\x${byte}"
    done | dd of="$file" bs=1 seek="$offset" conv=notrunc 2>/dev/null
}

# Helper: create a pagemap file with a single entry at virtual page 0
# Usage: create_simple_pagemap <file> <8-byte-hex-value-big-endian>
create_simple_pagemap() {
    local file="$1" hex_be="$2"
    # Create 8-byte file
    dd if=/dev/zero of="$file" bs=8 count=1 2>/dev/null
    write_pagemap_entry "$file" 0 "$hex_be"
}

# --- check_pagemap_readable tests ---

@test "check_pagemap_readable returns 1 when file missing" {
    PROC_BASE="$TEST_DIR"
    run check_pagemap_readable 99999
    assert_failure
}

@test "check_pagemap_readable returns 0 when file exists and readable" {
    local pid_dir="${TEST_DIR}/12345"
    mkdir -p "$pid_dir"
    touch "$pid_dir/pagemap"
    chmod 644 "$pid_dir/pagemap"
    PROC_BASE="$TEST_DIR"
    run check_pagemap_readable 12345
    assert_success
}

# --- extract_pfn_from_entry tests ---

@test "extract_pfn_from_entry returns PFN from present page" {
    # Bit 63 set (present), PFN = 0x12345 = 74565
    run extract_pfn_from_entry "8000000000012345"
    assert_success
    assert_output "74565"
}

@test "extract_pfn_from_entry returns not_present for absent page" {
    # Bit 63 not set
    run extract_pfn_from_entry "0000000000012345"
    assert_success
    assert_output "not_present"
}

@test "extract_pfn_from_entry handles hugepage flag (bit 22)" {
    # Bit 63 set (present), bit 22 set (huge), PFN in bits 0-54
    # 0x8000000000412345 → bit 22 set, PFN = 0x412345 = 4268869
    run extract_pfn_from_entry "8000000000412345"
    assert_success
    assert_output "4268869"
}

# --- pfn_to_phys_addr tests ---

@test "pfn_to_phys_addr multiplies PFN by page size" {
    # PFN 1 * 4096 = 4096 = 0x1000
    PAGE_SIZE=4096
    run pfn_to_phys_addr 1
    assert_success
    assert_output "1000"
}

@test "pfn_to_phys_addr with page size 4096" {
    # PFN 256 * 4096 = 1048576 = 0x100000
    PAGE_SIZE=4096
    run pfn_to_phys_addr 256
    assert_success
    assert_output "100000"
}

@test "pfn_to_phys_addr with custom PAGE_SIZE" {
    # PFN 1 * 2097152 (2MB hugepage) = 0x200000
    PAGE_SIZE=2097152
    run pfn_to_phys_addr 1
    assert_success
    assert_output "200000"
}

# --- read_pagemap_entry tests ---

@test "read_pagemap_entry reads correct offset for virtual address" {
    local pid="11111"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"

    # Create pagemap: 2 entries (16 bytes), put PFN=0xABCD at page 1
    dd if=/dev/zero of="${pid_dir}/pagemap" bs=8 count=2 2>/dev/null
    write_pagemap_entry "${pid_dir}/pagemap" 8 "800000000000ABCD"

    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    # Virtual address 4096 = page 1 → offset 8
    run read_pagemap_entry "$pid" 4096
    assert_success
    assert_output "43981"   # 0xABCD = 43981
}

@test "read_pagemap_entry returns PFN for present page" {
    local pid="22222"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"

    # PFN = 0x1000 = 4096
    create_simple_pagemap "${pid_dir}/pagemap" "8000000000001000"

    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    # Virtual address 0 = page 0 → offset 0
    run read_pagemap_entry "$pid" 0
    assert_success
    assert_output "4096"
}

@test "read_pagemap_entry returns not_present for absent page" {
    local pid="33333"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"

    # Not present (bit 63 = 0)
    create_simple_pagemap "${pid_dir}/pagemap" "0000000000001000"

    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    run read_pagemap_entry "$pid" 0
    assert_success
    assert_output "not_present"
}

@test "read_pagemap_entry handles non-existent pagemap file" {
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    run read_pagemap_entry 99999 0
    assert_failure
}

# --- get_vma_range tests ---

# Helper: create a synthetic /proc/PID/maps file
create_maps_file() {
    local file="$1"
    cat > "$file" <<'EOF'
00400000-00452000 r-xp 00000000 08:01 12345      /usr/bin/memtester
00651000-00652000 r--p 00051000 08:01 12345      /usr/bin/memtester
00652000-00653000 rw-p 00052000 08:01 12345      /usr/bin/memtester
7f0000000000-7f0020000000 rw-p 00000000 00:00 0
7f0020000000-7f0020010000 rw-p 00000000 00:00 0
7f1000000000-7f1000002000 r-xp 00000000 08:01 67890      /lib/x86_64-linux-gnu/libc-2.31.so
7fffc0000000-7fffc0021000 rw-p 00000000 00:00 0                          [stack]
EOF
}

@test "get_vma_range finds largest anonymous rw-p mapping" {
    local pid="44444"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    create_maps_file "$pid_dir/maps"
    PROC_BASE="$TEST_DIR"
    run get_vma_range "$pid"
    assert_success
    # Largest anon rw-p is 7f0000000000-7f0020000000 (512 MB)
    assert_output "7f0000000000 7f0020000000"
}

@test "get_vma_range ignores named mappings (libraries, stack)" {
    local pid="55555"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    # Only named mappings and stack
    cat > "$pid_dir/maps" <<'EOF'
00400000-00452000 r-xp 00000000 08:01 12345      /usr/bin/memtester
00652000-00653000 rw-p 00052000 08:01 12345      /usr/bin/memtester
7fffc0000000-7fffc0021000 rw-p 00000000 00:00 0                          [stack]
EOF
    PROC_BASE="$TEST_DIR"
    run get_vma_range "$pid"
    assert_failure
}

@test "get_vma_range ignores read-only mappings" {
    local pid="66666"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    cat > "$pid_dir/maps" <<'EOF'
7f0000000000-7f0020000000 r--p 00000000 00:00 0
EOF
    PROC_BASE="$TEST_DIR"
    run get_vma_range "$pid"
    assert_failure
}

@test "get_vma_range returns empty when no anonymous rw-p found" {
    local pid="77777"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    cat > "$pid_dir/maps" <<'EOF'
00400000-00452000 r-xp 00000000 08:01 12345      /usr/bin/memtester
EOF
    PROC_BASE="$TEST_DIR"
    run get_vma_range "$pid"
    assert_failure
}

@test "get_vma_range handles maps file not found" {
    PROC_BASE="$TEST_DIR"
    run get_vma_range 99999
    assert_failure
}

@test "get_vma_range picks largest when multiple anonymous regions exist" {
    local pid="88888"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    cat > "$pid_dir/maps" <<'EOF'
7f0000000000-7f0000010000 rw-p 00000000 00:00 0
7f0010000000-7f0030000000 rw-p 00000000 00:00 0
7f0040000000-7f0040008000 rw-p 00000000 00:00 0
EOF
    PROC_BASE="$TEST_DIR"
    run get_vma_range "$pid"
    assert_success
    # Largest is 7f0010000000-7f0030000000 (512 MB)
    assert_output "7f0010000000 7f0030000000"
}

@test "get_vma_range outputs start and end in hex" {
    local pid="10101"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    cat > "$pid_dir/maps" <<'EOF'
00a00000-00b00000 rw-p 00000000 00:00 0
EOF
    PROC_BASE="$TEST_DIR"
    run get_vma_range "$pid"
    assert_success
    assert_output "00a00000 00b00000"
}

# --- read_pagemap_range tests ---

# Helper: create a multi-entry pagemap + maps file for range tests
# Creates 4 pages of pagemap entries at virtual address 0x1000000 (page 4096)
create_range_fixture() {
    local pid="$1"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"

    # maps file: one anonymous region covering pages 4096-4100 (0x1000000-0x1004000)
    echo "01000000-01004000 rw-p 00000000 00:00 0" > "$pid_dir/maps"

    # pagemap: need entries at offset 4096*8=32768 through 4099*8=32800
    # Create a file large enough (4100 * 8 = 32800 bytes)
    dd if=/dev/zero of="$pid_dir/pagemap" bs=1 count=32800 2>/dev/null

    # Write 4 entries: PFN 0x100, 0x200, 0x300, 0x400 (all present)
    write_pagemap_entry "$pid_dir/pagemap" 32768 "8000000000000100"
    write_pagemap_entry "$pid_dir/pagemap" 32776 "8000000000000200"
    write_pagemap_entry "$pid_dir/pagemap" 32784 "8000000000000300"
    write_pagemap_entry "$pid_dir/pagemap" 32792 "8000000000000400"
}

@test "read_pagemap_range outputs vaddr:pfn:phys lines for sampled pages" {
    local pid="20001"
    create_range_fixture "$pid"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096

    # Stride 1 = every page, 4 pages total
    run read_pagemap_range "$pid" "01000000" "01004000" 1
    assert_success
    # Should have 4 lines
    local line_count
    line_count="$(echo "$output" | wc -l)"
    [[ "$line_count" -eq 4 ]]
    # First line: vaddr 01000000, PFN 256 (0x100), phys 100000
    assert_output --partial "01000000:256:100000"
}

@test "read_pagemap_range skips not_present pages" {
    local pid="20002"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    echo "01000000-01003000 rw-p 00000000 00:00 0" > "$pid_dir/maps"
    # 3 pages: page 4096, 4097, 4098
    dd if=/dev/zero of="$pid_dir/pagemap" bs=1 count=32792 2>/dev/null
    # Page 0: present, PFN 0x100
    write_pagemap_entry "$pid_dir/pagemap" 32768 "8000000000000100"
    # Page 1: NOT present
    write_pagemap_entry "$pid_dir/pagemap" 32776 "0000000000000200"
    # Page 2: present, PFN 0x300
    write_pagemap_entry "$pid_dir/pagemap" 32784 "8000000000000300"

    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    run read_pagemap_range "$pid" "01000000" "01003000" 1
    assert_success
    # Should have 2 lines (skipped not_present)
    local line_count
    line_count="$(echo "$output" | wc -l)"
    [[ "$line_count" -eq 2 ]]
}

@test "read_pagemap_range with stride 1 reads every page" {
    local pid="20003"
    create_range_fixture "$pid"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    run read_pagemap_range "$pid" "01000000" "01004000" 1
    assert_success
    local line_count
    line_count="$(echo "$output" | wc -l)"
    [[ "$line_count" -eq 4 ]]
}

@test "read_pagemap_range with large stride samples sparse set" {
    local pid="20004"
    create_range_fixture "$pid"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    # Stride 2 on 4 pages = pages 0 and 2 = 2 entries
    run read_pagemap_range "$pid" "01000000" "01004000" 2
    assert_success
    local line_count
    line_count="$(echo "$output" | wc -l)"
    [[ "$line_count" -eq 2 ]]
}

@test "read_pagemap_range handles empty VMA range" {
    local pid="20005"
    local pid_dir="${TEST_DIR}/${pid}"
    mkdir -p "$pid_dir"
    touch "$pid_dir/pagemap"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    # start == end → 0 pages
    run read_pagemap_range "$pid" "01000000" "01000000" 1
    assert_success
    [[ -z "$output" ]]
}

# --- capture_thread_pagemap tests ---

@test "capture_thread_pagemap writes pagemap file to log_dir" {
    local pid="30001"
    create_range_fixture "$pid"
    local log_dir="${TEST_DIR}/logs"
    mkdir -p "$log_dir"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    PAGEMAP_SAMPLE_STRIDE=1

    run capture_thread_pagemap "$pid" 0 "$log_dir"
    assert_success
    [[ -f "${log_dir}/thread_0_pagemap.txt" ]]
}

@test "capture_thread_pagemap handles unreadable pagemap gracefully" {
    local log_dir="${TEST_DIR}/logs"
    mkdir -p "$log_dir"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096

    # PID with no pagemap file
    run capture_thread_pagemap 99999 0 "$log_dir"
    assert_success
    # Should write a file with "not_available" indicator
    [[ -f "${log_dir}/thread_0_pagemap.txt" ]]
    run cat "${log_dir}/thread_0_pagemap.txt"
    assert_output --partial "not_available"
}

@test "capture_thread_pagemap includes physical address range summary" {
    local pid="30003"
    create_range_fixture "$pid"
    local log_dir="${TEST_DIR}/logs"
    mkdir -p "$log_dir"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    PAGEMAP_SAMPLE_STRIDE=1

    capture_thread_pagemap "$pid" 0 "$log_dir"
    run cat "${log_dir}/thread_0_pagemap.txt"
    assert_output --partial "min_phys"
    assert_output --partial "max_phys"
}

# --- capture_all_pagemaps tests ---

@test "capture_all_pagemaps captures for all MEMTESTER_PIDS" {
    # Create two fake PIDs with pagemap data
    local pid1="40001" pid2="40002"
    create_range_fixture "$pid1"
    create_range_fixture "$pid2"
    local log_dir="${TEST_DIR}/logs"
    mkdir -p "$log_dir"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    PAGEMAP_SAMPLE_STRIDE=1
    MEMTESTER_PIDS=("$pid1" "$pid2")

    run capture_all_pagemaps "$log_dir"
    assert_success
    [[ -f "${log_dir}/thread_0_pagemap.txt" ]]
    [[ -f "${log_dir}/thread_1_pagemap.txt" ]]
}

@test "capture_all_pagemaps skips PIDs whose pagemap is gone" {
    local pid1="40003"
    create_range_fixture "$pid1"
    local log_dir="${TEST_DIR}/logs"
    mkdir -p "$log_dir"
    PROC_BASE="$TEST_DIR"
    PAGE_SIZE=4096
    PAGEMAP_SAMPLE_STRIDE=1
    # pid2 doesn't exist
    MEMTESTER_PIDS=("$pid1" "99998")

    run capture_all_pagemaps "$log_dir"
    assert_success
    [[ -f "${log_dir}/thread_0_pagemap.txt" ]]
    [[ -f "${log_dir}/thread_1_pagemap.txt" ]]
    # Thread 1 should have not_available
    run cat "${log_dir}/thread_1_pagemap.txt"
    assert_output --partial "not_available"
}

# --- format_physical_report tests ---

@test "format_physical_report outputs human-readable summary" {
    local pagemap_file="${TEST_DIR}/thread_0_pagemap.txt"
    cat > "$pagemap_file" <<'EOF'
# min_phys=100000 max_phys=400000 pages=4
01000000:256:100000
01001000:512:200000
01002000:768:300000
01003000:1024:400000
EOF
    run format_physical_report "$pagemap_file"
    assert_success
    assert_output --partial "100000"
    assert_output --partial "400000"
}

@test "format_physical_report shows physical address range" {
    local pagemap_file="${TEST_DIR}/thread_0_pagemap.txt"
    cat > "$pagemap_file" <<'EOF'
# min_phys=a00000 max_phys=b00000 pages=2
00a00000:2560:a00000
00a01000:2816:b00000
EOF
    run format_physical_report "$pagemap_file"
    assert_success
    assert_output --partial "a00000"
    assert_output --partial "b00000"
}

@test "format_physical_report shows not_available when no data" {
    local pagemap_file="${TEST_DIR}/thread_0_pagemap.txt"
    echo "not_available" > "$pagemap_file"
    run format_physical_report "$pagemap_file"
    assert_success
    assert_output --partial "not_available"
}
