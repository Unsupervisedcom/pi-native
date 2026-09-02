#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_ROOT}/PiNative.xcodeproj"
SCHEME="PiNativeUITests"
DERIVED_DATA="${PROJECT_ROOT}/.derived-data/ui-tests"
DESTINATION="platform=macOS,arch=arm64"
LOG_FILE="/tmp/pinative-ui-tests.log"

usage() {
  cat <<'EOF'
Usage: scripts/test-ui.sh [xcodebuild test filters/options...]

Runs PiNative UI automation using the dedicated UI-test scheme. This is the
final pre-push gate only; do not use it during iterative implementation/review
churn. Run scripts/test-unit.sh first for focused unit/integration coverage.

Examples:
  scripts/test-ui.sh
  scripts/test-ui.sh -only-testing:PiNativeUITests/ActiveWorkUITests
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

cd "$PROJECT_ROOT"

echo "Running PiNative UI tests with scheme ${SCHEME}…"
echo "Log: ${LOG_FILE}"

xcodebuild test \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  "$@" >"$LOG_FILE" 2>&1

echo "UI tests passed."
