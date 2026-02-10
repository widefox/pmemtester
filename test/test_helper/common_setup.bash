_common_setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LIB_DIR="${PROJECT_ROOT}/lib"

    load "${PROJECT_ROOT}/test/test_helper/bats-support/load"
    load "${PROJECT_ROOT}/test/test_helper/bats-assert/load"

    load_lib() { source "${LIB_DIR}/$1"; }
}
