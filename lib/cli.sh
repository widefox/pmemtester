#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# CLI argument parsing for pmemtester

# Defaults (globals consumed by main script)
PERCENT=90
RAM_TYPE="available"
# DEFAULT_MEMTESTER_DIR is patched by 'make install MEMTESTER_DIR=/path' to bake
# in a distro-appropriate default (e.g., /usr/bin on Fedora, Debian, Arch, etc.)
DEFAULT_MEMTESTER_DIR="${DEFAULT_MEMTESTER_DIR:-/usr/local/bin}"
# shellcheck disable=SC2034
MEMTESTER_DIR="$DEFAULT_MEMTESTER_DIR"
# shellcheck disable=SC2034
LOG_DIR=""
ITERATIONS=1
ALLOW_CE=0
COLOR_MODE="auto"
# DEFAULT_STRESSAPPTEST_DIR is patched by 'make install STRESSAPPTEST_DIR=/path'
DEFAULT_STRESSAPPTEST_DIR="${DEFAULT_STRESSAPPTEST_DIR:-/usr/local/bin}"
# shellcheck disable=SC2034
STRESSAPPTEST_DIR="$DEFAULT_STRESSAPPTEST_DIR"
# shellcheck disable=SC2034
STRESSAPPTEST_MODE="auto"
# shellcheck disable=SC2034
STRESSAPPTEST_SECONDS=0
# shellcheck disable=SC2034
SIZE=""
# shellcheck disable=SC2034
PERCENT_SET=0
# shellcheck disable=SC2034
ESTIMATE_MODE="auto"
# shellcheck disable=SC2034
STOP_ON_ERROR=0
# shellcheck disable=SC2034
THREADS=0
# shellcheck disable=SC2034
NUMA_NODE=""
# shellcheck disable=SC2034
PIN=0
# shellcheck disable=SC2034
CHECK_DEPS=0

# usage: print help text
usage() {
    cat <<EOF
Usage: pmemtester ${pmemtester_version:-unknown} [OPTIONS]

Options:
  --percent N         Percentage of RAM to test (0.001-100, default: 90)
  --size SIZE         Total RAM to test: KiB/MiB/GiB/TiB (K, M, G, T suffix; e.g., 256M = 256 MiB)
  --ram-type TYPE     RAM measurement: available (default), total, free
  --memtester-dir DIR Directory containing memtester binary (default: ${DEFAULT_MEMTESTER_DIR})
  --log-dir DIR       Directory for log files (default: /tmp/pmemtester.PID)
  --iterations N      Number of memtester iterations (default: 1)
  --allow-ce          Allow correctable EDAC errors (CE); only fail on uncorrectable (UE)
  --color MODE        Coloured output: auto (default), on, off
  --stressapptest MODE  stressapptest pass: auto (default), on, off
  --stressapptest-seconds N  stressapptest duration (0 = use memtester time, default: 0)
  --stressapptest-dir DIR  Directory containing stressapptest binary (default: ${DEFAULT_STRESSAPPTEST_DIR})
  --estimate MODE     Time estimate calibration: auto (default), on, off
  --stop-on-error     Stop immediately when any error is detected (default: wait for all threads)
  --threads N         Number of memtester instances to run (default: auto-detect physical cores)
  --numa-node N       Constrain testing to NUMA node N or comma-separated nodes (requires numactl)
  --pin               Pin each memtester to a specific physical CPU core (uses taskset)
  --check-deps        Check all dependencies, show versions and paths, then exit
  --version           Show version
  --help              Show this help message
EOF
}

# parse_args: parse command-line arguments into global variables
# shellcheck disable=SC2034
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --percent)    PERCENT="$2"; PERCENT_SET=1; shift 2 ;;
            --size)       SIZE="$2"; shift 2 ;;
            --ram-type)   RAM_TYPE="$2"; shift 2 ;;
            --memtester-dir) MEMTESTER_DIR="$2"; shift 2 ;;
            --log-dir)    LOG_DIR="$2"; shift 2 ;;
            --iterations) ITERATIONS="$2"; shift 2 ;;
            --allow-ce)   ALLOW_CE=1; shift ;;
            --color)      COLOR_MODE="$2"; shift 2 ;;
            --stressapptest) STRESSAPPTEST_MODE="$2"; shift 2 ;;
            --stressapptest-seconds) STRESSAPPTEST_SECONDS="$2"; shift 2 ;;
            --stressapptest-dir) STRESSAPPTEST_DIR="$2"; shift 2 ;;
            --estimate) ESTIMATE_MODE="$2"; shift 2 ;;
            --stop-on-error) STOP_ON_ERROR=1; shift ;;
            --threads)    THREADS="$2"; shift 2 ;;
            --numa-node)  NUMA_NODE="$2"; shift 2 ;;
            --pin)        PIN=1; shift ;;
            --check-deps) CHECK_DEPS=1; shift ;;
            --version)    echo "pmemtester ${pmemtester_version:-unknown}"; exit 0 ;;
            --help)       usage; exit 0 ;;
            *)
                echo "ERROR: unknown option: $1" >&2
                return 1
                ;;
        esac
    done
}

# validate_args: validate parsed arguments
validate_args() {
    # Mutual exclusion: --percent and --size
    if [[ "$PERCENT_SET" -eq 1 ]] && [[ -n "$SIZE" ]]; then
        echo "ERROR: --percent and --size are mutually exclusive" >&2
        return 1
    fi

    # Validate --size or --percent
    if [[ -n "$SIZE" ]]; then
        parse_size_to_kb "$SIZE" > /dev/null || return 1
    else
        # Validate percent via millipercent conversion
        local millipercent
        millipercent="$(decimal_to_millipercent "$PERCENT" 2>&1)" || {
            echo "ERROR: --percent must be 0.001-100 (got ${PERCENT})" >&2
            return 1
        }
        if [[ "$millipercent" -le 0 ]]; then
            echo "ERROR: --percent must be > 0 (got ${PERCENT})" >&2
            return 1
        fi
        if [[ "$millipercent" -gt 100000 ]]; then
            echo "ERROR: --percent must be <= 100 (got ${PERCENT})" >&2
            return 1
        fi
    fi

    case "$RAM_TYPE" in
        available|total|free) : ;;
        *)
            echo "ERROR: --ram-type must be available, total, or free (got ${RAM_TYPE})" >&2
            return 1
            ;;
    esac
    if [[ "$ITERATIONS" -le 0 ]]; then
        echo "ERROR: --iterations must be > 0 (got ${ITERATIONS})" >&2
        return 1
    fi
    case "$COLOR_MODE" in
        auto|on|off) : ;;
        *)
            echo "ERROR: --color must be auto, on, or off (got ${COLOR_MODE})" >&2
            return 1
            ;;
    esac
    case "$STRESSAPPTEST_MODE" in
        auto|on|off) : ;;
        *)
            echo "ERROR: --stressapptest must be auto, on, or off (got ${STRESSAPPTEST_MODE})" >&2
            return 1
            ;;
    esac
    if [[ "$STRESSAPPTEST_SECONDS" -lt 0 ]]; then
        echo "ERROR: --stressapptest-seconds must be >= 0 (got ${STRESSAPPTEST_SECONDS})" >&2
        return 1
    fi
    case "$ESTIMATE_MODE" in
        auto|on|off) : ;;
        *)
            echo "ERROR: --estimate must be auto, on, or off (got ${ESTIMATE_MODE})" >&2
            return 1
            ;;
    esac
    if [[ "$THREADS" -lt 0 ]] 2>/dev/null; then
        echo "ERROR: --threads must be >= 0 (got ${THREADS})" >&2
        return 1
    fi
    if [[ "$THREADS" -gt 0 ]]; then
        local logical_cpus
        logical_cpus="$(nproc 2>/dev/null || echo 0)"
        if [[ "$logical_cpus" -gt 0 ]] && [[ "$THREADS" -gt "$logical_cpus" ]]; then
            echo "WARNING: --threads ${THREADS} exceeds logical CPU count (${logical_cpus})" >&2
        fi
    fi
    if [[ -n "${NUMA_NODE:-}" ]]; then
        # Validate each node in comma-separated list
        local sys_node_base="${SYS_NODE_BASE:-/sys/devices/system/node}"
        local _node
        for _node in $(echo "$NUMA_NODE" | tr ',' ' '); do
            _node="$(echo "$_node" | tr -d '[:space:]')"
            if ! [[ "$_node" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --numa-node must be non-negative integer(s) (got ${NUMA_NODE})" >&2
                return 1
            fi
            if [[ ! -d "${sys_node_base}/node${_node}" ]]; then
                echo "ERROR: NUMA node ${_node} does not exist (${sys_node_base}/node${_node}/ not found)" >&2
                return 1
            fi
        done
        if ! command -v numactl > /dev/null 2>&1; then
            echo "ERROR: --numa-node requires numactl but it is not installed" >&2
            return 1
        fi
    fi
    return 0
}

# _check_bin: check for a binary and print status line
# Usage: _check_bin <name> <path_or_empty> <required>
# Sets _check_bin_found=1 if found, 0 if not
_check_bin() {
    local name="$1" path="$2" required="$3"
    # shellcheck disable=SC2034
    _check_bin_found=0
    if [[ -n "$path" ]] && [[ -x "$path" ]]; then
        local version_str
        version_str="$("$path" --version 2>&1 | head -1)" || version_str="(version unknown)"
        printf "  %-16s %-40s %s  [OK]\n" "$name" "$path" "$version_str"
        _check_bin_found=1
    else
        local label
        if [[ "$required" == "required" ]]; then
            label="${_C_RED}[MISSING]${_C_RESET}"
        else
            label="${_C_YELLOW}[NOT FOUND]${_C_RESET}"
        fi
        printf "  %-16s %-40s %s\n" "$name" "(not found)" "$label"
    fi
}

# _check_cmd: check for a command in PATH and print status line
# Usage: _check_cmd <name> <required>
# Sets _check_cmd_found=1 if found, 0 if not
_check_cmd() {
    local name="$1" required="$2"
    local path
    # shellcheck disable=SC2034
    _check_cmd_found=0
    if path="$(command -v "$name" 2>/dev/null)"; then
        local version_str
        version_str="$("$name" --version 2>&1 | head -1)" || version_str="(version unknown)"
        printf "  %-16s %-40s %s  [OK]\n" "$name" "$path" "$version_str"
        _check_cmd_found=1
    else
        local label
        if [[ "$required" == "required" ]]; then
            label="${_C_RED}[MISSING]${_C_RESET}"
        else
            label="${_C_YELLOW}[NOT FOUND]${_C_RESET}"
        fi
        printf "  %-16s %-40s %s\n" "$name" "(not found)" "$label"
    fi
}

# check_deps: check all dependencies and print diagnostic report
# Requires: color.sh (for _C_GREEN/_C_RED/_C_YELLOW/_C_RESET),
#           system_detect.sh (for get_core_count, PROC_MEMINFO, EDAC_BASE, SYS_NODE_BASE),
#           memlock.sh (for _read_ulimit_l)
# Exit 0 if all required deps found, 1 otherwise.
check_deps() {
    local missing=0

    echo "pmemtester ${pmemtester_version:-unknown} dependency check"
    echo ""

    # --- Required ---
    echo "Required:"

    # memtester (searched in MEMTESTER_DIR)
    local memtester_path="${MEMTESTER_DIR:-/usr/local/bin}/memtester"
    _check_bin "memtester" "$memtester_path" "required"
    [[ "$_check_bin_found" -eq 0 ]] && missing=1

    for cmd in lscpu awk find diff; do
        _check_cmd "$cmd" "required"
        [[ "$_check_cmd_found" -eq 0 ]] && missing=1
    done

    echo ""

    # --- Optional ---
    echo "Optional:"

    local stressapptest_path="${STRESSAPPTEST_DIR:-/usr/local/bin}/stressapptest"
    _check_bin "stressapptest" "$stressapptest_path" "optional"

    for cmd in numactl taskset dmesg nproc; do
        _check_cmd "$cmd" "optional"
    done

    echo ""

    # --- System ---
    echo "System:"

    # /proc/meminfo
    local meminfo="${PROC_MEMINFO:-/proc/meminfo}"
    if [[ -f "$meminfo" ]]; then
        local mem_total mem_avail
        mem_total="$(awk '/^MemTotal:/ { print $2 }' "$meminfo" 2>/dev/null)" || mem_total="?"
        mem_avail="$(awk '/^MemAvailable:/ { print $2 }' "$meminfo" 2>/dev/null)" || mem_avail="?"
        printf "  %-16s MemTotal: %s kB, MemAvailable: %s kB  [OK]\n" "/proc/meminfo" "$mem_total" "$mem_avail"
    else
        printf "  %-16s %s\n" "/proc/meminfo" "${_C_RED}[MISSING]${_C_RESET}"
        missing=1
    fi

    # EDAC
    local edac_base="${EDAC_BASE:-/sys/devices/system/edac}"
    if [[ -d "${edac_base}/mc" ]]; then
        local mc_count
        mc_count="$(find "${edac_base}/mc" -maxdepth 1 -type d -name 'mc*' 2>/dev/null | wc -l)"
        printf "  %-16s %s/mc/ (%s memory controllers)  [OK]\n" "EDAC" "$edac_base" "$mc_count"
    else
        printf "  %-16s %s\n" "EDAC" "[NOT FOUND] (no ECC or EDAC driver not loaded)"
    fi

    # NUMA
    local sys_node_base="${SYS_NODE_BASE:-/sys/devices/system/node}"
    if [[ -d "$sys_node_base" ]]; then
        local node_count
        node_count="$(find "$sys_node_base" -maxdepth 1 -type d -name 'node*' 2>/dev/null | wc -l)"
        printf "  %-16s %s nodes  [OK]\n" "NUMA" "$node_count"
    else
        printf "  %-16s %s\n" "NUMA" "[NOT FOUND]"
    fi

    # Physical cores
    local core_count
    if core_count="$(get_core_count 2>/dev/null)"; then
        printf "  %-16s %s cores  [OK]\n" "Physical cores" "$core_count"
    else
        printf "  %-16s %s\n" "Physical cores" "${_C_YELLOW}[UNKNOWN]${_C_RESET} (lscpu and nproc both failed)"
    fi

    # Memory lock
    local memlock_raw
    memlock_raw="$(_read_ulimit_l 2>/dev/null)" || memlock_raw="(unknown)"
    printf "  %-16s ulimit -l: %s  [OK]\n" "Memory lock" "$memlock_raw"

    echo ""

    # --- Summary ---
    if [[ "$missing" -eq 0 ]]; then
        echo "${_C_GREEN}All required dependencies found.${_C_RESET}"
        return 0
    else
        echo "${_C_RED}Some required dependencies are missing.${_C_RESET}"
        return 1
    fi
}
