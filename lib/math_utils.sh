#!/usr/bin/env bash
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
