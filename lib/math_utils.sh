#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Integer arithmetic utilities for pmemtester
# All operations are integer-only; no floating point.

# ceiling_div: ceil(a/b) using integer arithmetic
# Usage: ceiling_div <numerator> <denominator>
ceiling_div() {
    local num="$1" den="$2"
    if [[ "$den" -eq 0 ]]; then
        echo "ERROR: division by zero" >&2
        return 1
    fi
    if [[ "$num" -eq 0 ]]; then
        echo "0"
        return 0
    fi
    echo $(( (num + den - 1) / den ))
}

# percentage_of: value * percent / 100 (multiply first to preserve precision)
# Usage: percentage_of <value> <percent>
percentage_of() {
    local value="$1" percent="$2"
    echo $(( value * percent / 100 ))
}

# safe_multiply: a * b with 64-bit overflow detection
# Usage: safe_multiply <a> <b>
safe_multiply() {
    local a="$1" b="$2"
    if [[ "$a" -eq 0 ]] || [[ "$b" -eq 0 ]]; then
        echo "0"
        return 0
    fi
    local result=$(( a * b ))
    # Check for overflow: result / a should equal b
    if [[ $(( result / a )) -ne "$b" ]]; then
        echo "ERROR: integer overflow in ${a} * ${b}" >&2
        return 1
    fi
    echo "$result"
}

# min_val: return the smaller of two integers
min_val() {
    if [[ "$1" -le "$2" ]]; then
        echo "$1"
    else
        echo "$2"
    fi
}

# max_val: return the larger of two integers
max_val() {
    if [[ "$1" -ge "$2" ]]; then
        echo "$1"
    else
        echo "$2"
    fi
}

# decimal_to_millipercent: convert a decimal percent string to integer millipercents
# 0.1 → 100, 90 → 90000, 50.5 → 50500
# Supports up to 3 decimal places. Rejects empty, negative, non-numeric, 4+ decimals.
# Usage: decimal_to_millipercent <percent_string>
decimal_to_millipercent() {
    local input="$1"

    # Reject empty
    if [[ -z "$input" ]]; then
        echo "ERROR: percent value is empty" >&2
        return 1
    fi

    # Reject negative
    if [[ "$input" == -* ]]; then
        echo "ERROR: percent must not be negative (got ${input})" >&2
        return 1
    fi

    # Validate format: optional digits, optional dot, optional digits
    if [[ ! "$input" =~ ^[0-9]*\.?[0-9]*$ ]]; then
        echo "ERROR: percent must be numeric (got ${input})" >&2
        return 1
    fi

    # Reject lone dot
    if [[ "$input" == "." ]]; then
        echo "ERROR: percent value is empty" >&2
        return 1
    fi

    local int_part frac_part
    if [[ "$input" == *.* ]]; then
        int_part="${input%%.*}"
        frac_part="${input#*.}"
        # Default empty parts to 0
        int_part="${int_part:-0}"
        # Reject 4+ decimal places
        if [[ ${#frac_part} -gt 3 ]]; then
            echo "ERROR: --percent supports up to 3 decimal places (got ${input})" >&2
            return 1
        fi
    else
        int_part="$input"
        frac_part=""
    fi

    # Pad fractional part to exactly 3 digits
    while [[ ${#frac_part} -lt 3 ]]; do
        frac_part="${frac_part}0"
    done

    # Force base-10 to prevent octal interpretation
    echo $(( 10#$int_part * 1000 + 10#$frac_part ))
}

# percentage_of_milli: value * millipercent / 100000
# Usage: percentage_of_milli <value> <millipercent>
percentage_of_milli() {
    local value="$1" millipercent="$2"
    echo $(( value * millipercent / 100000 ))
}
