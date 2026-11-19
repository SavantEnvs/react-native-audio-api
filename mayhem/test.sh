#!/usr/bin/env bash
#
# mayhem/test.sh — runs upstream's own C++ gtest suite (packages/react-native-audio-api/common/cpp/test),
# built by mayhem/build.sh with the project's normal flags. Runs the "smoke" selection upstream's
# run-tests.sh uses by default (cpp_test_smoke_filter from test/filters.sh; the slow randomized graph
# suites are upstream's "extended" mode). Counts come from gtest's own summary lines; a missing
# summary (runner neutered / crashed) is a failure.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TEST_DIR="$SRC/packages/react-native-audio-api/common/cpp/test"
RUNNER="$TEST_DIR/build/tests"
if [ ! -x "$RUNNER" ]; then
  echo "test.sh: $RUNNER missing — mayhem/build.sh should have built it" >&2
  emit_ctrf gtest 0 1 0
  exit 1
fi

# shellcheck source=/dev/null
source "$TEST_DIR/filters.sh"
FILTER="$(cpp_test_smoke_filter)"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
( cd "$TEST_DIR" && "$RUNNER" --gtest_filter="$FILTER" ) 2>&1 | tee "$LOG" | grep -E '^\[  (FAILED|PASSED|SKIPPED) |^\[==========\]'
rc=${PIPESTATUS[0]}

ran=$(sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\? from .* ran\..*/\1/p' "$LOG" | tail -1)
passed=$(sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\?\..*/\1/p' "$LOG" | tail -1)
failed=$(sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\?, listed below.*/\1/p' "$LOG" | tail -1)
skipped=$(sed -n 's/^\[  SKIPPED \] \([0-9][0-9]*\) tests\?, listed below.*/\1/p' "$LOG" | tail -1)
passed=${passed:-0}; failed=${failed:-0}; skipped=${skipped:-0}

if [ -z "$ran" ] || [ "$ran" -eq 0 ]; then
  echo "test.sh: gtest printed no summary (exit $rc) — counting as a failure" >&2
  failed=$(( failed + 1 ))
elif [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then
  echo "test.sh: gtest exited $rc without reporting failed tests — counting as a failure" >&2
  failed=1
fi
emit_ctrf gtest "$passed" "$failed" "$skipped"
