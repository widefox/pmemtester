#!/usr/bin/env bats
# Performance and benchmark tests for pmemtester
# These measure overhead of the wrapper layer and verify scaling properties.
# Not testing memtester performance itself (that depends on hardware);
# testing pmemtester's orchestration overhead with mocked externals.

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/mock_helpers'
    _common_setup
    setup_mock_dir
    FIXTURE_DIR="${PROJECT_ROOT}/test/fixtures"
    TEST_LOG_DIR="$(mktemp -d)"
    TEST_MEMTESTER_DIR="$(mktemp -d)"

    # Ultra-fast memtester mock (just exits)
    cat > "${TEST_MEMTESTER_DIR}/memtester" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "${TEST_MEMTESTER_DIR}/memtester"

    create_mock lscpu '
case "$*" in
    *Socket,Core,CPU,Node*)
        echo "# Socket,Core,CPU,Node"
        echo "0,0,0,0"
        echo "0,1,1,0"
        echo "0,2,2,0"
        echo "0,3,3,0"
        ;;
    *)
        echo "# Socket,Core"
        echo "0,0"
        echo "0,1"
        echo "0,2"
        echo "0,3"
        ;;
esac'

    create_mock dmesg 'echo ""'
    export PROC_MEMINFO="${FIXTURE_DIR}/proc_meminfo_normal"
    export EDAC_BASE="${TEST_LOG_DIR}/no_edac"
    export MOCK_ULIMIT_L="unlimited"
    export SYS_CPU_BASE="${FIXTURE_DIR}/sys_cpu_cache_3mb"
}

teardown() {
    teardown_mock_dir
    [[ -d "${TEST_LOG_DIR:-}" ]] && rm -rf "$TEST_LOG_DIR"
    [[ -d "${TEST_MEMTESTER_DIR:-}" ]] && rm -rf "$TEST_MEMTESTER_DIR"
}

# ============================================================================
# PERF-001: Wrapper startup overhead
# The pmemtester script itself (sourcing libs, parsing args, init) should
# complete in under 2 seconds even with slow shells.
# ============================================================================

@test "performance: --help completes in under 2 seconds" {
    local start end elapsed
    start=$(date +%s%N)
    run "${PROJECT_ROOT}/pmemtester" --help
    end=$(date +%s%N)
    assert_success

    elapsed=$(( (end - start) / 1000000 ))  # ms
    # Startup + help text should be well under 2000ms
    [[ "$elapsed" -lt 2000 ]] || {
        echo "FAIL: --help took ${elapsed}ms (limit: 2000ms)"
        return 1
    }
}

@test "performance: --version completes in under 2 seconds" {
    local start end elapsed
    start=$(date +%s%N)
    run "${PROJECT_ROOT}/pmemtester" --version
    end=$(date +%s%N)
    assert_success

    elapsed=$(( (end - start) / 1000000 ))
    [[ "$elapsed" -lt 2000 ]] || {
        echo "FAIL: --version took ${elapsed}ms (limit: 2000ms)"
        return 1
    }
}

# ============================================================================
# PERF-002: Full run overhead with instant memtester
# With a mock memtester that exits immediately, the total wall time measures
# pmemtester's orchestration overhead (spawn, wait, log, EDAC, verdict).
# ============================================================================

@test "performance: full run with 1 thread overhead < 5 seconds" {
    local start end elapsed
    start=$(date +%s%N)
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --threads 1 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    end=$(date +%s%N)
    assert_success

    elapsed=$(( (end - start) / 1000000 ))
    [[ "$elapsed" -lt 5000 ]] || {
        echo "FAIL: 1-thread run took ${elapsed}ms (limit: 5000ms)"
        return 1
    }
}

@test "performance: full run with 4 threads overhead < 5 seconds" {
    local start end elapsed
    start=$(date +%s%N)
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --threads 4 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    end=$(date +%s%N)
    assert_success

    elapsed=$(( (end - start) / 1000000 ))
    [[ "$elapsed" -lt 5000 ]] || {
        echo "FAIL: 4-thread run took ${elapsed}ms (limit: 5000ms)"
        return 1
    }
}

# ============================================================================
# PERF-003: Thread scaling — 4 threads should not be much slower than 1
# (with instant memtester, overhead is spawn/wait/log per thread)
# ============================================================================

@test "performance: 4 threads not more than 3x slower than 1 thread" {
    local start end

    # 1 thread
    start=$(date +%s%N)
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --threads 1 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    end=$(date +%s%N)
    assert_success
    local time_1=$(( (end - start) / 1000000 ))

    # Clean up logs
    rm -f "${TEST_LOG_DIR}"/thread_*.log "${TEST_LOG_DIR}"/master.log

    # 4 threads
    start=$(date +%s%N)
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --threads 4 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    end=$(date +%s%N)
    assert_success
    local time_4=$(( (end - start) / 1000000 ))

    # 4 threads should not be more than 3x the 1-thread time
    # (generous margin for system variability)
    local limit=$(( time_1 * 3 + 500 ))  # +500ms grace for fork/wait
    [[ "$time_4" -le "$limit" ]] || {
        echo "FAIL: 4-thread: ${time_4}ms, 1-thread: ${time_1}ms, limit: ${limit}ms"
        return 1
    }
}

# ============================================================================
# PERF-004: Argument parsing speed
# Parsing 20+ flags should complete instantly.
# ============================================================================

@test "performance: parse_args with many flags completes in under 10 seconds" {
    load_lib math_utils.sh
    load_lib unit_convert.sh
    load_lib cli.sh
    local pmemtester_version="test"

    local start end elapsed
    start=$(date +%s%N)
    for i in $(seq 1 100); do
        parse_args \
            --percent 50 \
            --ram-type total \
            --iterations 3 \
            --color off \
            --estimate off \
            --threads 2 \
            --stressapptest off \
            --stressapptest-seconds 60 \
            --stop-on-error \
            --allow-ce \
            --pin
    done
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))

    # 100 iterations of full flag parsing — generous threshold for slow systems
    [[ "$elapsed" -lt 10000 ]] || {
        echo "FAIL: 100x parse_args took ${elapsed}ms (limit: 10000ms)"
        return 1
    }
}

# ============================================================================
# PERF-005: Math function throughput
# Core math functions should handle thousands of calls per second.
# ============================================================================

@test "performance: ceiling_div 1000 calls in under 30 seconds" {
    load_lib math_utils.sh
    local start end elapsed
    start=$(date +%s%N)
    for i in $(seq 1 1000); do
        ceiling_div 12288000 1024 > /dev/null
    done
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    [[ "$elapsed" -lt 30000 ]] || {
        echo "FAIL: 1000 ceiling_div took ${elapsed}ms (limit: 30000ms)"
        return 1
    }
}

@test "performance: decimal_to_millipercent 1000 calls in under 60 seconds" {
    load_lib math_utils.sh
    local start end elapsed
    start=$(date +%s%N)
    for i in $(seq 1 1000); do
        decimal_to_millipercent "90.5" > /dev/null
    done
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    [[ "$elapsed" -lt 60000 ]] || {
        echo "FAIL: 1000 decimal_to_millipercent took ${elapsed}ms (limit: 60000ms)"
        return 1
    }
}

# ============================================================================
# PERF-006: Log file size is bounded
# Thread logs from a mocked run should not grow unboundedly.
# ============================================================================

@test "performance: thread log files are reasonably sized" {
    run "${PROJECT_ROOT}/pmemtester" \
        --memtester-dir "$TEST_MEMTESTER_DIR" \
        --log-dir "$TEST_LOG_DIR" \
        --percent 90 \
        --threads 4 \
        --estimate off \
        --stressapptest-dir "${TEST_LOG_DIR}/no_sat_bin"
    assert_success

    local log
    for log in "${TEST_LOG_DIR}"/thread_*.log; do
        local size
        size=$(wc -c < "$log")
        # Each thread log with instant mock should be under 10KB
        [[ "$size" -lt 10240 ]] || {
            echo "FAIL: ${log} is ${size} bytes (limit: 10240)"
            return 1
        }
    done
}
