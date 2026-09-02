#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/build-release-dmg.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  local description="$1"
  local expected_message="$2"
  shift 2

  local output
  if output="$("$@" 2>&1)"; then
    fail "$description unexpectedly succeeded"
  fi
  [[ "$output" == *"$expected_message"* ]] || fail "$description did not report '$expected_message': $output"
  echo "PASS: $description"
}

expect_success() {
  local description="$1"
  shift
  "$@" >/dev/null || fail "$description failed"
  echo "PASS: $description"
}

expect_official_export_receives_team_id() {
  local temporary_directory mock_bin output
  temporary_directory="$(mktemp -d)"
  mock_bin="$temporary_directory/bin"
  mkdir -p "$mock_bin"
  trap 'rm -rf "$temporary_directory"' RETURN

  cat > "$mock_bin/security" <<'EOF'
#!/usr/bin/env bash
printf '  1) TESTIDENTITY "Developer ID Application: Test (%s)"\n' "$APPLE_TEAM_ID"
EOF
  chmod +x "$mock_bin/security"

  cat > "$mock_bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "archive" ]]; then
  [[ "$*" == *"POSTHOG_PROJECT_API_KEY=phc_test"* ]] || exit 6
  exit 0
fi

if [[ "$1" == "-exportArchive" ]]; then
  export_options=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-exportOptionsPlist" ]]; then
      export_options="$2"
      break
    fi
    shift
  done
  [[ -n "$export_options" ]] || exit 2
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$export_options")" == "$APPLE_TEAM_ID" ]] || exit 3
  echo "verified copied export options team ID"
  exit 4
fi

exit 5
EOF
  chmod +x "$mock_bin/xcodebuild"

  if output="$(PATH="$mock_bin:$PATH" APPLE_TEAM_ID=LOCALTEAM POSTHOG_PROJECT_API_KEY=phc_test "$script" --official 0.1.0 --build-number 1 --notary-profile test 2>&1)"; then
    fail "injects the supplied team ID into copied export options unexpectedly succeeded"
  fi
  [[ "$output" == *"verified copied export options team ID"* ]] || fail "injects the supplied team ID into copied export options did not verify the generated plist: $output"
  echo "PASS: injects the supplied team ID into copied export options"
}

expect_success "help describes the official mode" "$script" --help
expect_failure "rejects an unknown mode" "expected --unsigned-internal or --official mode" "$script" --unknown 0.1.0
expect_failure "rejects a malformed version" "version must look like 0.1.0" "$script" --unsigned-internal invalid
expect_failure "requires an official build number" "--official requires --build-number" "$script" --official 0.1.0 --notary-profile local-profile
expect_failure "requires an official notarization profile" "--official requires --notary-profile" "$script" --official 0.1.0 --build-number 1
expect_failure "rejects a non-numeric build number" "build number must contain only digits" "$script" --official 0.1.0 --build-number one --notary-profile local-profile
expect_failure "requires an official Apple Team ID" "--official requires APPLE_TEAM_ID" env -u APPLE_TEAM_ID "$script" --official 0.1.0 --build-number 1 --notary-profile local-profile
expect_official_export_receives_team_id

echo "Release DMG command validation passed."
