#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_ROOT}/PiNative.xcodeproj"
SCHEME="PiNativeUITests"
DERIVED_DATA="${PROJECT_ROOT}/.derived-data/ui-related-tests"
DESTINATION="platform=macOS,arch=arm64"
LOG_FILE="/tmp/pinative-ui-related-tests.log"
BUILD_LOG_FILE="/tmp/pinative-ui-related-build.log"

usage() {
  cat <<'EOF'
Usage: scripts/test-ui-related.sh [xcodebuild test filters/options...]

Compiles the whole PiNative UI test bundle, then runs only UI tests related to
changed files. Pass explicit -only-testing/-skip-testing flags to override the
changed-file selection.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

cd "$PROJECT_ROOT"

echo "Building PiNative UI test bundle…"
echo "Build log: ${BUILD_LOG_FILE}"
xcodebuild build-for-testing \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" >"$BUILD_LOG_FILE" 2>&1

TEST_APP="${DERIVED_DATA}/Build/Products/Debug/PiNative.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f -R -trusted "$TEST_APP"

if [[ $# -gt 0 ]]; then
  echo "Running explicitly requested UI tests…"
  echo "Log: ${LOG_FILE}"
  xcodebuild test-without-building \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    "$@" >"$LOG_FILE" 2>&1
  echo "Focused UI tests passed."
  exit 0
fi

base_ref="${PI_NATIVE_UI_BASE_REF:-}"
if [[ -z "$base_ref" ]]; then
  base_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
fi
if [[ -z "$base_ref" ]] || ! git rev-parse --verify --quiet "$base_ref" >/dev/null; then
  base_ref="origin/main"
fi
if ! git rev-parse --verify --quiet "$base_ref" >/dev/null; then
  base_ref="main"
fi
merge_base="$(git merge-base HEAD "$base_ref" 2>/dev/null || true)"

changed_files="$({
  if [[ -n "$merge_base" ]]; then git diff --name-only "$merge_base"...HEAD; fi
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"

if [[ -z "$changed_files" ]]; then
  echo "UI test bundle compiled; no changed files selected UI runtime tests."
  exit 0
fi

declare -a selected=()
add_test() {
  local test="$1"
  for existing in "${selected[@]:-}"; do
    [[ "$existing" == "$test" ]] && return
  done
  selected+=("$test")
}

while IFS= read -r file; do
  case "$file" in
    PiNative/PiHealth.swift|PiNative/PiNativeApp.swift|PiNativeUITests/PiStartupHealthUITests.swift)
      add_test "PiNativeUITests/PiStartupHealthUITests"
      ;;
    PiNative/PiRPCClient.swift)
      add_test "PiNativeUITests/ActiveWorkUITests"
      ;;
    PiNative/ChatPaneView.swift)
      add_test "PiNativeUITests/ChatReadinessUITests"
      ;;
    PiNative/PiConversationModel.swift|PiNative/PiConversationView.swift)
      add_test "PiNativeUITests/ConversationNavigationUITests"
      ;;
    PiNative/ModelSettingsModel.swift|PiNative/ModelSettingsView.swift)
      add_test "PiNativeUITests/ModelSettingsUITests"
      ;;
    PiNative/Components/NewChatStartView.swift)
      add_test "PiNativeUITests/NewChatUITests"
      ;;
    PiNative/ProjectSidebarView.swift|PiNative/DiffPaneView.swift)
      add_test "PiNativeUITests/ProjectUITests"
      ;;
    PiNative/PromoteToProject.swift)
      add_test "PiNativeUITests/PromoteToProjectUITests"
      ;;
    PiNative/MainWindowView.swift)
      add_test "PiNativeUITests/PiStartupHealthUITests"
      add_test "PiNativeUITests/ShellChromeUITests"
      ;;
    PiNative/RightPaneView.swift|PiNative/Components/WindowChromeConfigurator.swift)
      add_test "PiNativeUITests/ShellChromeUITests"
      ;;
  esac
done <<< "$changed_files"

if [[ ${#selected[@]} -eq 0 ]]; then
  echo "UI test bundle compiled; no related UI runtime tests selected."
  exit 0
fi

declare -a test_args=()
for test in "${selected[@]}"; do
  test_args+=("-only-testing:${test}")
done

test_args+=(
  "-skip-testing:PiNativeUITests/NewChatUITests/testNewChatWithLiveRPCResponds"
  "-skip-testing:PiNativeUITests/ModelSettingsUITests/testModelsSettingsLoadsRealPiCatalogWithoutAConversation"
)

echo "Running related UI tests: ${selected[*]}"
echo "Log: ${LOG_FILE}"
xcodebuild test-without-building \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  "${test_args[@]}" >"$LOG_FILE" 2>&1

echo "Related UI tests passed."
