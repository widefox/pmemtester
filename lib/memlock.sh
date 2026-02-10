#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Kernel memory lock management for pmemtester
# memtester requires mlock(), which needs sufficient ulimit -l.

# Internal wrappers for testability
# Override via MOCK_ULIMIT_L env var for integration tests
_read_ulimit_l() { echo "${MOCK_ULIMIT_L:-$(ulimit -l)}"; }
_set_ulimit_l() {
    if [[ -n "${MOCK_ULIMIT_L:-}" ]]; then
	return 0
    fi
    ulimit -l "$1"
}

# get_memlock_limit_kb: return current memlock limit in kB
# "unlimited" is mapped to a large sentinel value.
get_memlock_limit_kb() {
    local raw
    raw="$(_read_ulimit_l)"
    if [[ "$raw" == "unlimited" ]]; then
        echo "999999999"
    else
        echo "$raw"
    fi
}

# check_memlock_sufficient: check if limit >= needed_kb
# Usage: check_memlock_sufficient <needed_kb>
check_memlock_sufficient() {
    local needed_kb="$1"
    local limit_kb
    limit_kb="$(get_memlock_limit_kb)"
    if [[ "$limit_kb" -ge "$needed_kb" ]]; then
        return 0
    fi
    echo "ERROR: memlock limit ${limit_kb} kB < needed ${needed_kb} kB" >&2
    return 1
}

# configure_memlock: attempt to set ulimit -l to needed value
# Usage: configure_memlock <needed_kb>
configure_memlock() {
    local needed_kb="$1"
    if ! _set_ulimit_l "$needed_kb"; then
        echo "ERROR: failed to set memlock limit to ${needed_kb} kB (may require root)" >&2
        return 1
    fi
    return 0
}
