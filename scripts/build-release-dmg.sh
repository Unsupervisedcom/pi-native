#!/usr/bin/env bash
set -euo pipefail

readonly apple_team_id="${APPLE_TEAM_ID:-}"
readonly app_name="PiNative.app"
readonly product_bundle_identifier="com.unsupervised.PiNative"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-release-dmg.sh --unsigned-internal <version>
  scripts/build-release-dmg.sh --official <version> --build-number <number> --notary-profile <profile>

Modes:
  --unsigned-internal  Creates a clearly labeled, unsigned internal-test DMG.
  --official           Archives, Developer ID-signs, exports, notarizes, staples,
                       Gatekeeper-verifies, and checksums an official DMG.

The official mode requires APPLE_TEAM_ID, a matching Developer ID Application
identity in the active keychain, and a notarytool keychain profile. It never
accepts certificate material or notary credentials as command-line arguments.

Examples:
  scripts/build-release-dmg.sh --unsigned-internal 0.1.0
  scripts/build-release-dmg.sh --official 0.1.0 --build-number 42 --notary-profile pinative-notary
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || fail "missing value for $option"
}

validate_version() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] || fail "version must look like 0.1.0, got '$value'"
}

validate_build_number() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "build number must contain only digits, got '$value'"
}

find_developer_id_identity() {
  local identity
  identity="$(security find-identity -v -p codesigning | awk -v team_id="$apple_team_id" '
    index($0, "Developer ID Application:") && index($0, "(" team_id ")") {
      sub(/^[^"]*"/, "")
      sub(/".*$/, "")
      print
      exit
    }
  ')"
  [[ -n "$identity" ]] || fail "no Developer ID Application identity for Apple Team $apple_team_id is available in the active keychain"
  printf '%s\n' "$identity"
}

create_dmg() {
  local source_app="$1"
  local volume_name="$2"
  local staging="$3"
  local dmg_path="$4"

  [[ -d "$source_app" ]] || fail "expected app at $source_app"
  [[ -f "$dmg_ds_store" ]] || fail "missing DMG Finder layout resource at $dmg_ds_store"

  rm -rf "$staging"
  mkdir -p "$staging"
  ditto "$source_app" "$staging/$app_name"
  ln -s /Applications "$staging/Applications"
  cp "$dmg_ds_store" "$staging/.DS_Store"
  SetFile -a V "$staging/.DS_Store" 2>/dev/null || true

  rm -f "$dmg_path"
  echo "Creating $dmg_path..."
  hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$dmg_path"
}

write_checksum() {
  local dmg_path="$1"
  local checksum_path="$2"
  (
    cd "$(dirname "$dmg_path")"
    shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$checksum_path")"
  )
}

mode="${1:-}"
[[ -n "$mode" ]] || { usage >&2; fail "missing mode"; }

if [[ "$mode" == "-h" || "$mode" == "--help" ]]; then
  usage
  exit 0
fi

version=""
build_number=""
notary_profile=""

case "$mode" in
  --unsigned-internal)
    [[ $# -eq 2 ]] || { usage >&2; fail "--unsigned-internal expects exactly one version"; }
    version="$2"
    ;;
  --official)
    [[ $# -ge 2 ]] || { usage >&2; fail "--official requires a version"; }
    version="$2"
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --build-number)
          require_value "$1" "${2:-}"
          build_number="$2"
          shift 2
          ;;
        --notary-profile)
          require_value "$1" "${2:-}"
          notary_profile="$2"
          shift 2
          ;;
        *)
          usage >&2
          fail "unknown official-release option '$1'"
          ;;
      esac
    done
    [[ -n "$build_number" ]] || fail "--official requires --build-number"
    [[ -n "$notary_profile" ]] || fail "--official requires --notary-profile"
    ;;
  *)
    usage >&2
    fail "expected --unsigned-internal or --official mode"
    ;;
esac

validate_version "$version"
if [[ "$mode" == "--official" ]]; then
  validate_build_number "$build_number"
  [[ -n "$apple_team_id" ]] || fail "--official requires APPLE_TEAM_ID"
fi

for command in xcodebuild xcrun codesign hdiutil shasum ditto security plutil; do
  command -v "$command" >/dev/null || fail "$command not found; install/select full Xcode"
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$repo_root/build/release-dmg"
derived_data="$build_root/DerivedData"
staging="$build_root/staging"
dist="$repo_root/dist"
dmg_ds_store="$repo_root/packaging/dmg/DS_Store"
mkdir -p "$dist"

if [[ "$mode" == "--unsigned-internal" ]]; then
  artifact_base="PiNative-${version}-internal-unsigned"
  dmg_path="$dist/${artifact_base}.dmg"
  checksum_path="$dmg_path.sha256"

  rm -rf "$build_root"
  mkdir -p "$staging"
  rm -f "$dmg_path" "$checksum_path"

  echo "Building PiNative Release app for internal unsigned DMG..."
  xcodebuild \
    -project "$repo_root/PiNative.xcodeproj" \
    -scheme PiNative \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    MARKETING_VERSION="$version" \
    build

  built_app="$derived_data/Build/Products/Release/$app_name"
  create_dmg "$built_app" "PiNative ${version} Internal" "$staging" "$dmg_path"
  write_checksum "$dmg_path" "$checksum_path"

  cat <<EOF

Created internal unsigned DMG:
  $dmg_path
  $checksum_path

Internal unsigned test build.

This build is not Developer ID signed or notarized yet. macOS may warn that
the developer cannot be verified. This is expected for this temporary internal
test build and does not represent the final release experience.

PiNative requires Pi to be installed and configured separately before launch.
EOF
  exit 0
fi

command -v spctl >/dev/null || fail "spctl not found"
xcrun --find stapler >/dev/null || fail "stapler is unavailable in the selected Xcode toolchain"

developer_id_identity="$(find_developer_id_identity)"
artifact_base="PiNative-${version}"
dmg_path="$dist/${artifact_base}.dmg"
checksum_path="$dmg_path.sha256"
working_dmg_path="$build_root/${artifact_base}.dmg"
notary_result_path="${NOTARY_SUBMISSION_RESULT_PATH:-$build_root/notary-result.json}"
archive_path="$build_root/PiNative.xcarchive"
export_path="$build_root/export"
export_options="$build_root/ExportOptions-DeveloperID.plist"
mount_path="$build_root/mount"

mounted=0
cleanup() {
  local status=$?
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$mount_path" -quiet || true
  fi
  rm -rf "$build_root"
  exit "$status"
}
trap cleanup EXIT

rm -rf "$build_root"
mkdir -p "$build_root" "$staging"
rm -f "$dmg_path" "$checksum_path"

echo "Archiving signed PiNative ${version} (${build_number})..."
xcodebuild archive \
  -project "$repo_root/PiNative.xcodeproj" \
  -scheme PiNative \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data" \
  DEVELOPMENT_TEAM="$apple_team_id" \
  POSTHOG_PROJECT_API_KEY="${POSTHOG_PROJECT_API_KEY:-}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$developer_id_identity" \
  CODE_SIGNING_REQUIRED=YES \
  ENABLE_HARDENED_RUNTIME=YES \
  PRODUCT_BUNDLE_IDENTIFIER="$product_bundle_identifier" \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number"

echo "Exporting Developer ID app..."
cp "$repo_root/packaging/ExportOptions-DeveloperID.plist" "$export_options"
plutil -replace teamID -string "$apple_team_id" "$export_options"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options"

exported_app="$export_path/$app_name"
[[ -d "$exported_app" ]] || fail "expected exported app at $exported_app"

echo "Verifying exported app signature..."
codesign --verify --deep --strict --verbose=2 "$exported_app"
codesign -dv --verbose=4 "$exported_app"

create_dmg "$exported_app" "PiNative ${version}" "$staging" "$working_dmg_path"

echo "Signing DMG..."
codesign --force --sign "$developer_id_identity" --timestamp "$working_dmg_path"

echo "Submitting DMG for notarization..."
mkdir -p "$(dirname "$notary_result_path")"
xcrun notarytool submit "$working_dmg_path" --keychain-profile "$notary_profile" --wait --output-format json | tee "$notary_result_path"

echo "Stapling notarization ticket..."
xcrun stapler staple "$working_dmg_path"
xcrun stapler validate "$working_dmg_path"

echo "Assessing final DMG with Gatekeeper..."
spctl --assess --type open --context context:primary-signature -vv "$working_dmg_path"

echo "Verifying app signature inside DMG..."
mkdir -p "$mount_path"
hdiutil attach -readonly -nobrowse -mountpoint "$mount_path" "$working_dmg_path" >/dev/null
mounted=1
codesign --verify --deep --strict --verbose=2 "$mount_path/$app_name"
hdiutil detach "$mount_path" -quiet
mounted=0

mv "$working_dmg_path" "$dmg_path"
write_checksum "$dmg_path" "$checksum_path"

cat <<EOF

Created official signed and notarized DMG:
  $dmg_path
  $checksum_path

Verified Developer ID signature, notarization stapling, Gatekeeper assessment,
and the app bundle inside the final DMG.
EOF
