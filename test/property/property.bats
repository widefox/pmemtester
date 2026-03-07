#!/usr/bin/env bats
# Property-based tests for pmemtester
# These verify mathematical invariants that must hold for ALL valid inputs,
# not just specific examples. Uses boundary values and random sampling.

setup() {
    load '../test_helper/common_setup'
    _common_setup
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib ram_calc.sh
}

# ============================================================================
# Property: ceiling_div(a, b) * b >= a  (result * divisor covers numerator)
# ============================================================================

@test "property: ceiling_div result covers numerator (small values)" {
    local a b result
    for a in 0 1 2 3 7 10 15 99 100 1023 1024 1025; do
        for b in 1 2 3 4 7 8 16 100 1024; do
            result="$(ceiling_div "$a" "$b")"
            [[ $(( result * b )) -ge "$a" ]] || {
                echo "FAIL: ceiling_div($a, $b)=$result but $result * $b = $(( result * b )) < $a"
                return 1
            }
        done
    done
}

@test "property: ceiling_div result is tight (not one more than needed)" {
    local a b result
    for a in 1 2 3 7 10 15 99 100 1023 1024 1025; do
        for b in 1 2 3 4 7 8 16 100 1024; do
            result="$(ceiling_div "$a" "$b")"
            # result - 1 should NOT cover a (otherwise result is too large)
            if [[ "$result" -gt 0 ]]; then
                [[ $(( (result - 1) * b )) -lt "$a" ]] || {
                    echo "FAIL: ceiling_div($a, $b)=$result but $(( result - 1 )) * $b = $(( (result - 1) * b )) >= $a"
                    return 1
                }
            fi
        done
    done
}

# ============================================================================
# Property: percentage_of(x, 100) == x  (100% of anything is itself)
# ============================================================================

@test "property: percentage_of 100 percent is identity" {
    local x
    for x in 0 1 100 1024 12288000 999999999; do
        run percentage_of "$x" 100
        assert_success
        assert_output "$x"
    done
}

# ============================================================================
# Property: percentage_of(x, 0) == 0  (0% of anything is zero)
# ============================================================================

@test "property: percentage_of 0 percent is zero" {
    local x
    for x in 0 1 100 1024 12288000 999999999; do
        run percentage_of "$x" 0
        assert_success
        assert_output "0"
    done
}

# ============================================================================
# Property: percentage_of(x, p) <= x  (percentage never exceeds input)
# ============================================================================

@test "property: percentage_of never exceeds input for 0-100%" {
    local x p result
    for x in 1 100 1024 12288000; do
        for p in 0 1 10 25 50 75 90 99 100; do
            result="$(percentage_of "$x" "$p")"
            [[ "$result" -le "$x" ]] || {
                echo "FAIL: percentage_of($x, $p)=$result > $x"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: percentage_of is monotonic (higher percent -> higher or equal result)
# ============================================================================

@test "property: percentage_of is monotonic" {
    local x prev_result result
    for x in 100 1024 12288000; do
        prev_result=0
        for p in 0 1 10 25 50 75 90 99 100; do
            result="$(percentage_of "$x" "$p")"
            [[ "$result" -ge "$prev_result" ]] || {
                echo "FAIL: percentage_of($x, $p)=$result < previous $prev_result"
                return 1
            }
            prev_result="$result"
        done
    done
}

# ============================================================================
# Property: decimal_to_millipercent round-trip consistency
# millipercent(x) / 1000 should approximate the integer part of x
# ============================================================================

@test "property: decimal_to_millipercent of integer N equals N * 1000" {
    local n result
    for n in 1 5 10 25 50 75 90 99 100; do
        result="$(decimal_to_millipercent "$n")"
        [[ "$result" -eq $(( n * 1000 )) ]] || {
            echo "FAIL: decimal_to_millipercent($n)=$result, expected $(( n * 1000 ))"
            return 1
        }
    done
}

# ============================================================================
# Property: percentage_of_milli with 100000 (=100%) equals the input
# ============================================================================

@test "property: percentage_of_milli at 100% is identity" {
    local x
    for x in 0 1 100 1024 12288000 999999999; do
        run percentage_of_milli "$x" 100000
        assert_success
        assert_output "$x"
    done
}

# ============================================================================
# Property: percentage_of_milli at 0 is zero
# ============================================================================

@test "property: percentage_of_milli at 0 is zero" {
    local x
    for x in 0 1 100 1024 12288000; do
        run percentage_of_milli "$x" 0
        assert_success
        assert_output "0"
    done
}

# ============================================================================
# Property: percentage_of_milli is monotonic in millipercent
# ============================================================================

@test "property: percentage_of_milli is monotonic in millipercent" {
    local x=12288000 prev_result=0 mp result
    for mp in 0 1 100 1000 10000 50000 90000 99000 100000; do
        result="$(percentage_of_milli "$x" "$mp")"
        [[ "$result" -ge "$prev_result" ]] || {
            echo "FAIL: percentage_of_milli($x, $mp)=$result < previous $prev_result"
            return 1
        }
        prev_result="$result"
    done
}

# ============================================================================
# Property: percentage_of and percentage_of_milli agree for whole percents
# percentage_of(x, p) == percentage_of_milli(x, p * 1000)
# ============================================================================

@test "property: percentage_of and percentage_of_milli agree for integer percents" {
    local x p old_result new_result
    for x in 100 1024 12288000; do
        for p in 0 1 10 25 50 75 90 99 100; do
            old_result="$(percentage_of "$x" "$p")"
            new_result="$(percentage_of_milli "$x" $(( p * 1000 )))"
            [[ "$old_result" -eq "$new_result" ]] || {
                echo "FAIL: percentage_of($x, $p)=$old_result != percentage_of_milli($x, $(( p * 1000 )))=$new_result"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: min_val(a, b) <= max_val(a, b)
# ============================================================================

@test "property: min_val <= max_val for all pairs" {
    local a b min max
    for a in 0 1 5 99 1000 999999; do
        for b in 0 1 5 99 1000 999999; do
            min="$(min_val "$a" "$b")"
            max="$(max_val "$a" "$b")"
            [[ "$min" -le "$max" ]] || {
                echo "FAIL: min_val($a, $b)=$min > max_val($a, $b)=$max"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: min_val(a, b) is either a or b
# ============================================================================

@test "property: min_val returns one of its inputs" {
    local a b result
    for a in 0 1 5 99; do
        for b in 0 1 5 99; do
            result="$(min_val "$a" "$b")"
            [[ "$result" -eq "$a" || "$result" -eq "$b" ]] || {
                echo "FAIL: min_val($a, $b)=$result is neither $a nor $b"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: max_val(a, b) is either a or b
# ============================================================================

@test "property: max_val returns one of its inputs" {
    local a b result
    for a in 0 1 5 99; do
        for b in 0 1 5 99; do
            result="$(max_val "$a" "$b")"
            [[ "$result" -eq "$a" || "$result" -eq "$b" ]] || {
                echo "FAIL: max_val($a, $b)=$result is neither $a nor $b"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: min_val and max_val are commutative
# ============================================================================

@test "property: min_val is commutative" {
    local a b
    for a in 0 1 5 99 1000; do
        for b in 0 1 5 99 1000; do
            [[ "$(min_val "$a" "$b")" == "$(min_val "$b" "$a")" ]] || {
                echo "FAIL: min_val($a,$b) != min_val($b,$a)"
                return 1
            }
        done
    done
}

@test "property: max_val is commutative" {
    local a b
    for a in 0 1 5 99 1000; do
        for b in 0 1 5 99 1000; do
            [[ "$(max_val "$a" "$b")" == "$(max_val "$b" "$a")" ]] || {
                echo "FAIL: max_val($a,$b) != max_val($b,$a)"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: parse_size_to_kb unit scaling
# 1T = 1024G, 1G = 1024M, 1M = 1024K
# ============================================================================

@test "property: parse_size_to_kb unit scaling is consistent" {
    local k m g t
    k="$(parse_size_to_kb "1K")"
    m="$(parse_size_to_kb "1M")"
    g="$(parse_size_to_kb "1G")"
    t="$(parse_size_to_kb "1T")"
    [[ "$m" -eq $(( k * 1024 )) ]] || { echo "1M != 1024 * 1K"; return 1; }
    [[ "$g" -eq $(( m * 1024 )) ]] || { echo "1G != 1024 * 1M"; return 1; }
    [[ "$t" -eq $(( g * 1024 )) ]] || { echo "1T != 1024 * 1G"; return 1; }
}

@test "property: parse_size_to_kb is linear (NM = N * 1M)" {
    local one_m n_m n
    one_m="$(parse_size_to_kb "1M")"
    for n in 2 4 8 16 256 1024; do
        n_m="$(parse_size_to_kb "${n}M")"
        [[ "$n_m" -eq $(( one_m * n )) ]] || {
            echo "FAIL: ${n}M=$n_m != $n * 1M=$(( one_m * n ))"
            return 1
        }
    done
}

# ============================================================================
# Property: safe_multiply(a, b) == a * b when no overflow
# ============================================================================

@test "property: safe_multiply matches native multiply for small values" {
    local a b result expected
    for a in 0 1 2 100 1024 65536; do
        for b in 0 1 2 100 1024 65536; do
            result="$(safe_multiply "$a" "$b")"
            expected=$(( a * b ))
            [[ "$result" -eq "$expected" ]] || {
                echo "FAIL: safe_multiply($a, $b)=$result != expected $expected"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: safe_multiply is commutative
# ============================================================================

@test "property: safe_multiply is commutative" {
    local a b
    for a in 0 1 7 100 1024; do
        for b in 0 1 7 100 1024; do
            [[ "$(safe_multiply "$a" "$b")" == "$(safe_multiply "$b" "$a")" ]] || {
                echo "FAIL: safe_multiply($a,$b) != safe_multiply($b,$a)"
                return 1
            }
        done
    done
}

# ============================================================================
# Property: divide_ram_per_core_mb * cores <= total_kb / 1024
# (floor division means per-core allocation never exceeds fair share)
# ============================================================================

@test "property: divide_ram_per_core_mb * cores fits within total" {
    local total_kb cores result total_mb
    for total_kb in 4096 8192 16384 1048576 12288000; do
        for cores in 1 2 4 8 16; do
            total_mb=$(( total_kb / 1024 ))
            if [[ $(( total_kb / cores / 1024 )) -ge 1 ]]; then
                result="$(divide_ram_per_core_mb "$total_kb" "$cores")"
                [[ $(( result * cores )) -le "$total_mb" ]] || {
                    echo "FAIL: $result * $cores = $(( result * cores )) > $total_mb"
                    return 1
                }
            fi
        done
    done
}
