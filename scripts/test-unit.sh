#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_ROOT}/PiNative.xcodeproj"
SCHEME="PiNativeUnitTests"
DERIVED_DATA="${PROJECT_ROOT}/.derived-data/unit-tests"
DESTINATION="platform=macOS,arch=arm64"
LOG_FILE="/tmp/pinative-unit-tests.log"
BUILD_LOG_FILE="/tmp/pinative-unit-test-build.log"
BUILD_TIMEOUT_SECONDS="${UNIT_TEST_BUILD_TIMEOUT_SECONDS:-300}"
PER_TEST_TIMEOUT_SECONDS="${UNIT_TEST_CASE_TIMEOUT_SECONDS:-30}"
SUITE_TIMEOUT_SECONDS="${UNIT_TEST_SUITE_TIMEOUT_SECONDS:-60}"

usage() {
  cat <<'EOF'
Usage: scripts/test-unit.sh [xcodebuild test filters/options...]

Runs PiNative's unit/integration tests with the unit-only Xcode scheme. This
scheme includes PiNativeTests and excludes PiNativeUITests, so it is safe for
iterative development before the final pre-push UI gate. The test-suite timeout
starts only after the test bundle has compiled; compilation has its own hang guard.

Examples:
  scripts/test-unit.sh
  scripts/test-unit.sh -only-testing:PiNativeTests/PiChatTitleServiceTests
  scripts/test-unit.sh -only-testing:PiNativeTests/ChatTitleLifecycleTests/testGenerationFailureLeavesFallbackUnchangedAndNeverRetries

Pass extra xcodebuild test options after the script name. Do not use this script
for UI automation; use scripts/test-ui.sh at the final pre-push stage only.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

cd "$PROJECT_ROOT"

echo "Running PiNative unit tests with scheme ${SCHEME} (UI tests excluded)…"
echo "Build timeout: ${BUILD_TIMEOUT_SECONDS}s"
echo "Suite timeout: ${SUITE_TIMEOUT_SECONDS}s"
echo "Per-test timeout: ${PER_TEST_TIMEOUT_SECONDS}s"
echo "Test log: ${LOG_FILE}"
echo "Build log: ${BUILD_LOG_FILE}"
: >"$LOG_FILE"
: >"$BUILD_LOG_FILE"

# Stream concise XCTest outcomes from the full xcodebuild log. Build output and
# app logs are intentionally suppressed here; the complete unfiltered log remains
# available at $LOG_FILE.
python3 - "$LOG_FILE" <<'PY' &
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
with path.open("r", errors="replace") as handle:
    handle.seek(0, 2)
    while True:
        line = handle.readline()
        if not line:
            time.sleep(0.1)
            continue
        line = line.rstrip("\n")
        if line.startswith("Testing started"):
            print(line, flush=True)
        elif line.startswith("Test Case ") and line.endswith(" started."):
            print("START " + line[len("Test Case "):], flush=True)
        elif line.startswith("Test Case ") and " passed " in line:
            print("PASS  " + line[len("Test Case "):], flush=True)
        elif line.startswith("Test Case ") and " failed " in line:
            print("FAIL  " + line[len("Test Case "):], flush=True)
        elif line.startswith("Executed "):
            print(line, flush=True)
PY
TEST_OUTPUT_PID=$!

(
  while true; do
    sleep 15
    if ! grep -q "^Testing started" "$LOG_FILE" 2>/dev/null; then
      echo "Building unit-test bundle…"
    fi
  done
) &
PROGRESS_PID=$!

cleanup_tail() {
  kill "$TEST_OUTPUT_PID" "$PROGRESS_PID" >/dev/null 2>&1 || true
  wait "$TEST_OUTPUT_PID" "$PROGRESS_PID" 2>/dev/null || true
}

XCODE_PID=""
terminate_xcodebuild() {
  if [[ -n "$XCODE_PID" ]] && kill -0 "$XCODE_PID" 2>/dev/null; then
    kill -TERM -- "-$XCODE_PID" >/dev/null 2>&1 || true
    wait "$XCODE_PID" 2>/dev/null || true
  fi
  XCODE_PID=""
}

cleanup_all() {
  terminate_xcodebuild
  cleanup_tail
}

handle_signal() {
  trap - TERM INT EXIT
  cleanup_all
  exit 124
}

trap cleanup_all EXIT
trap handle_signal TERM INT

echo "Building PiNative unit-test bundle…"
set +e
build_xcodebuild_command=(
  xcodebuild build-for-testing
  -project "$PROJECT_FILE"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
)
NSUnbufferedIO=YES python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  "${build_xcodebuild_command[@]}" >>"$BUILD_LOG_FILE" 2>&1 &
XCODE_PID=$!
BUILD_RC=0
build_started_at=$(date +%s)
while kill -0 "$XCODE_PID" 2>/dev/null; do
  now=$(date +%s)
  if (( now - build_started_at >= BUILD_TIMEOUT_SECONDS )); then
    echo "TIMEOUT Unit-test bundle build exceeded ${BUILD_TIMEOUT_SECONDS}s; terminating build." >&2
    terminate_xcodebuild
    BUILD_RC=124
    break
  fi
  sleep 1
done
if [[ $BUILD_RC -eq 0 ]]; then
  wait "$XCODE_PID"
  BUILD_RC=$?
  XCODE_PID=""
fi
set -e
if [[ $BUILD_RC -ne 0 ]]; then
  cleanup_tail
  trap - TERM INT EXIT
  echo "Unit-test bundle build failed. Log: ${BUILD_LOG_FILE}" >&2
  tail -80 "$BUILD_LOG_FILE" >&2 || true
  exit "$BUILD_RC"
fi

: >"$LOG_FILE"
set +e
suite_started_at=$(date +%s)
xcodebuild_command=(
  xcodebuild test-without-building
  -project "$PROJECT_FILE"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance "$PER_TEST_TIMEOUT_SECONDS"
  -maximum-test-execution-time-allowance "$PER_TEST_TIMEOUT_SECONDS"
  "$@"
)
NSUnbufferedIO=YES python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  "${xcodebuild_command[@]}" >>"$LOG_FILE" 2>&1 &
XCODE_PID=$!

RC=0
timeout_reason=""
in_flight=""
started_at=0
while kill -0 "$XCODE_PID" 2>/dev/null; do
  current=$(python3 - "$LOG_FILE" <<'PY'
import re
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(errors="replace").splitlines()
started = []
finished = set()
start_pattern = re.compile(r"Test Case '-\[(?P<name>[^\]]+)\]' started\.")
finish_pattern = re.compile(r"Test Case '-\[(?P<name>[^\]]+)\]' (passed|failed) ")
for line in log:
    if match := start_pattern.search(line):
        started.append(match.group("name"))
    if match := finish_pattern.search(line):
        finished.add(match.group("name"))
for name in reversed(started):
    if name not in finished:
        print(name)
        break
PY
)
  now=$(date +%s)
  if (( now - suite_started_at >= SUITE_TIMEOUT_SECONDS )); then
    timeout_reason="Unit test suite exceeded ${SUITE_TIMEOUT_SECONDS}s"
    echo "TIMEOUT ${timeout_reason}; terminating unit test run." >&2
    terminate_xcodebuild
    RC=124
    break
  fi
  if [[ -z "$current" ]]; then
    in_flight=""
    started_at=0
  elif [[ "$current" != "$in_flight" ]]; then
    in_flight="$current"
    started_at=$now
  elif (( started_at > 0 && now - started_at >= PER_TEST_TIMEOUT_SECONDS )); then
    timeout_reason="${in_flight} exceeded ${PER_TEST_TIMEOUT_SECONDS}s"
    echo "TIMEOUT ${timeout_reason}; terminating unit test run." >&2
    terminate_xcodebuild
    RC=124
    break
  fi
  sleep 1
done

if [[ $RC -eq 0 ]]; then
  wait "$XCODE_PID"
  RC=$?
  XCODE_PID=""
fi
set -e
cleanup_tail
trap - TERM INT EXIT

echo
python3 - "$LOG_FILE" <<'PY'
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
pattern = re.compile(r"Test Case '-\[(?P<suite>[^ ]+) (?P<test>[^\]]+)\]' (?P<status>passed|failed) \((?P<seconds>[0-9.]+) seconds\)\.")
rows = []
for line in log_path.read_text(errors="replace").splitlines():
    match = pattern.search(line)
    if match:
        rows.append((float(match.group("seconds")), match.group("status").upper(), match.group("suite"), match.group("test")))

if rows:
    print("Unit test summary (slowest first):")
    for seconds, status, suite, test in sorted(rows, reverse=True):
        print(f"{seconds:7.3f}s  {status:<6}  {suite}.{test}")
else:
    print("Unit test summary: no completed XCTest cases found in log.")
PY

if [[ $RC -ne 0 ]]; then
  echo "Unit tests failed. Log: ${LOG_FILE}" >&2
  if [[ -n "$timeout_reason" ]]; then
    echo "Timeout reason: ${timeout_reason}" >&2
  fi
  python3 - "$LOG_FILE" <<'PY' >&2
import re
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(errors="replace").splitlines()
started = []
finished = set()
start_pattern = re.compile(r"Test Case '-\[(?P<name>[^\]]+)\]' started\.")
finish_pattern = re.compile(r"Test Case '-\[(?P<name>[^\]]+)\]' (passed|failed) ")
for line in log:
    if match := start_pattern.search(line):
        started.append(match.group("name"))
    if match := finish_pattern.search(line):
        finished.add(match.group("name"))
for name in reversed(started):
    if name not in finished:
        print(f"Suspect timed-out/hung test: {name}")
        break
PY
  tail -80 "$LOG_FILE" >&2 || true
  exit $RC
fi

echo "Unit tests passed."
