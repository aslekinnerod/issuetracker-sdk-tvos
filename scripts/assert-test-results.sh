#!/usr/bin/env bash
#
# Usage: scripts/assert-test-results.sh <path.xcresult> <minimum-test-count>
#
# Fails when a test run did not verify what it claims to have verified:
#   * the run did not pass,
#   * fewer tests ran than expected (a test target that compiled but
#     executed nothing still exits 0 and prints TEST SUCCEEDED),
#   * any test was SKIPPED. xcodebuild folds skips into its
#     "Executed N tests, with 0 failures" summary, so a skipped test is
#     indistinguishable from a passing one in the log. The submission
#     round-trip in the example app skips itself when no API key reaches
#     the test runner, which silently removes the only end-to-end
#     coverage while the run stays green.
#
# Runs locally against any bundle produced with -resultBundlePath.
set -euo pipefail

bundle=${1:?usage: assert-test-results.sh <path.xcresult> <minimum-test-count>}
min_tests=${2:?usage: assert-test-results.sh <path.xcresult> <minimum-test-count>}

if [ ! -e "$bundle" ]; then
  echo "::error::No result bundle at ${bundle} — the test step produced no results." >&2
  exit 1
fi

summary=$(xcrun xcresulttool get test-results summary --path "$bundle" --format json)

field() { printf '%s' "$summary" | jq -r "$1"; }

result=$(field '.result')
total=$(field '.totalTestCount')
passed=$(field '.passedTests')
failed=$(field '.failedTests')
skipped=$(field '.skippedTests')

# Always state what actually ran, including the OS. The destination is
# resolved at runtime, so the log is the only record of the runtime used.
printf '%s' "$summary" | jq -r '
  .devicesAndConfigurations[]?
  | "ran on \(.device.platform) — \(.device.deviceName), OS \(.device.osVersion)"
'
echo "result=${result} total=${total} passed=${passed} failed=${failed} skipped=${skipped}"

status=0

if [ "$result" != "Passed" ]; then
  echo "::error::Test run result is '${result}', not 'Passed'." >&2
  status=1
fi

if [ "$failed" -gt 0 ]; then
  echo "::error::${failed} test(s) failed." >&2
  status=1
fi

if [ "$total" -lt "$min_tests" ]; then
  echo "::error::Only ${total} test(s) ran, expected at least ${min_tests}." >&2
  status=1
fi

if [ "$skipped" -gt 0 ]; then
  echo "::error::${skipped} test(s) were SKIPPED — a skipped test verifies nothing." >&2
  xcrun xcresulttool get test-results tests --path "$bundle" --format json 2>/dev/null |
    jq -r '.. | objects | select(.nodeType == "Test Case" and .result == "Skipped") | "  skipped: \(.name)"' >&2 ||
    true
  status=1
fi

exit "$status"
