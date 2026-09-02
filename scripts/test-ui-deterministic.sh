#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_ROOT}/PiNative.xcodeproj"
SCHEME="PiNativeUITests"
DESTINATION="platform=macOS"
RESULT_BUNDLE_PATH="${PI_NATIVE_UI_TEST_RESULT_BUNDLE_PATH:-${PROJECT_ROOT}/build/test-results/PiNativeUITests.xcresult}"
LOG_FILE="${PI_NATIVE_UI_TEST_LOG_FILE:-${PROJECT_ROOT}/build/test-results/PiNativeUITests.log}"

usage() {
  cat <<'EOF'
Usage: scripts/test-ui-deterministic.sh [xcodebuild test filters/options...]

Runs the deterministic PiNative UI test subset used by GitHub Actions. Live or
real-Pi integration UI tests are skipped, but the whole UI test bundle still
compiles.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

cd "$PROJECT_ROOT"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
rm -rf "$RESULT_BUNDLE_PATH"

echo "Running deterministic PiNative UI tests with scheme ${SCHEME}…"
echo "Result bundle: ${RESULT_BUNDLE_PATH}"
echo "Log: ${LOG_FILE}"

set -o pipefail
xcodebuild test \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -parallel-testing-enabled NO \
  -skip-testing:PiNativeUITests/NewChatUITests/testNewChatWithLiveRPCResponds \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testModelsSettingsLoadsRealPiCatalogWithoutAConversation \
  -skip-testing:PiNativeUITests/ConversationNavigationUITests/testMockConversationTranscriptPersistsAfterRelaunch \
  -skip-testing:PiNativeUITests/ConversationNavigationUITests/testProjectRowSelectsNewestVisibleUnpinnedChat \
  -skip-testing:PiNativeUITests/ConversationNavigationUITests/testReturningToChatRestoresRecentTranscriptContent \
  -skip-testing:PiNativeUITests/ConversationNavigationUITests/testSelectedChatIsReadyWhileRPCStartupIsStalled \
  -skip-testing:PiNativeUITests/ConversationNavigationUITests/testSidebarChatRowSelectsChatFromVisibleRowTarget \
  -skip-testing:PiNativeUITests/ConversationNavigationUITests/testUpdatingSelectedChatRevealsBottomOfLongTranscript \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testComposerLoadsFavoriteCatalogBeforeConversationRPCStarts \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testComposerModelFavoritesAndSeparateEffortPicker \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testComposerRejectsReturnAndSendWithoutASelectedModel \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testEffortPickerShowsUnavailableStateWhenPiReportsNoLevels \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testModelAndEffortSelectionsBeforeRPCStartupAreAppliedToPi \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testModelsSettingsCatalogStatesAreVisible \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testModelsSettingsShowsEmptyAndErrorFromPiCatalogProcess \
  -skip-testing:PiNativeUITests/ModelSettingsUITests/testUnavailableFavoriteIsVisibleInModelsSettings \
  -skip-testing:PiNativeUITests/ActiveWorkUITests/testRunningChatShowsIndicator \
  -skip-testing:PiNativeUITests/ActiveWorkUITests/testVisibleStopButtonStopsLateOutputAndLeavesComposerUsable \
  -skip-testing:PiNativeUITests/ChatReadinessUITests/testNonCatastrophicLoadingKeepsDisplayedChatComposerInteractive \
  -skip-testing:PiNativeUITests/NewChatUITests/testNewChatCanStartWithoutProject \
  -skip-testing:PiNativeUITests/NewChatUITests/testNewChatWithMockRPCResponds \
  -skip-testing:PiNativeUITests/ProjectUITests/testArchiveChatRemovesItFromSidebar \
  -skip-testing:PiNativeUITests/ProjectUITests/testProjectDiffPillOpensGitDiffPane \
  -skip-testing:PiNativeUITests/PromoteToProjectUITests/testPromoteToProjectModalNameOnlyFlowOpensPromotedProjectChat \
  -skip-testing:PiNativeUITests/PromoteToProjectUITests/testPromoteToProjectModalShowsCreationFailureWithoutOpenProjectAction \
  -skip-testing:PiNativeUITests/PromoteToProjectUITests/testPromoteToProjectModalUsesPersistedSettingsFolderForDestination \
  -skip-testing:PiNativeUITests/ShellChromeUITests/testRightPaneToolbarToggleOnlyAppearsWhenPaneIsOpen \
  -skip-testing:PiNativeUITests/ShellChromeUITests/testSidebarTogglesKeepCenterChatVisible \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  "$@" | tee "$LOG_FILE"
