# REQ-006: Release Distribution

## Overview

PiNative needs a conventional macOS distribution path: a user should be able to visit the repository's Releases page, download the latest disk image, drag PiNative into Applications, and launch it without scary unsigned-app workarounds. The release process must account for Developer ID signing, hardened runtime, notarization, stapling, quarantine/Gatekeeper verification, CI secret handling, and the fact that Pi remains an external prerequisite.

## Requirements

### REQ-006.1: Release artifact availability

1. Every public release MUST include a downloadable `.dmg` artifact on the repository release page. [manual]
2. Every public release MUST include checksum information for the distributed `.dmg` artifact. [manual]
3. Every public release MUST identify the app version contained in the `.dmg` artifact. [manual]
4. Every official tagged release that passes signing, notarization, and verification gates MUST remain under manual maintainer publication control until the release-automation policy is revisited. [manual]

### REQ-006.2: Conventional macOS install experience

1. The release `.dmg` MUST present `PiNative.app` and an Applications-folder target for drag installation. [manual]
2. The release `.dmg` MUST use a volume name that identifies PiNative and the release version. [manual]
3. The release `.dmg` MUST include a custom, polished Finder presentation rather than an unstyled default disk image window. [manual]
4. The installed app bundle MUST launch when opened from `/Applications` on a Gatekeeper-enabled macOS system. [manual]

### REQ-006.3: Signing and notarization

1. Official releases MUST use an organization-owned Apple Developer Program team. [manual]
2. The release app bundle MUST use an organization-owned reverse-DNS bundle identifier before first official publication. [manual]
3. The release app bundle MUST be signed with a Developer ID Application identity from the organization-owned Apple Developer team. [manual]
4. The release app bundle MUST use hardened runtime. [manual]
5. The release `.dmg` MUST be submitted to Apple's notary service before publication. [manual]
6. The release `.dmg` MUST have a notarization ticket stapled before publication. [manual]
7. The release pipeline MUST verify the final `.dmg` with `spctl` before publication. [manual]
8. The release pipeline MUST verify the final app bundle signature with `codesign` before publication. [manual]

### REQ-006.4: Release automation

1. A tagged release workflow MUST build the Release configuration from a clean checkout. [manual]
2. A tagged release workflow MUST fail before publication when signing credentials are unavailable. [manual]
3. A tagged release workflow MUST keep Apple certificates, private keys, and notary credentials out of git-tracked files. [manual]
4. A tagged release workflow MUST publish only artifacts produced by that workflow run. [manual]

### REQ-006.5: User-facing restriction handling

1. Release notes MUST state that the app requires macOS 14 or newer. [manual]
2. Release notes MUST state that Pi must be installed and configured separately before using PiNative. [manual]
3. Release notes MUST explain that first launch may require approval of requested permissions when macOS prompts for them. [manual]
4. Release notes MUST avoid instructing users to disable Gatekeeper for official releases. [manual]
5. The README Requirements section MUST document Pi as an external prerequisite for PiNative. [manual]

### REQ-006.6: PostHog crash-symbol release readiness

1. When PostHog crash tracking is enabled for an official release, the release workflow MUST preserve and upload the exact Release dSYM corresponding to the app bundle in the distributed `.dmg`. [manual]
2. PostHog symbol-upload credentials MUST be available only within the CI release job that uploads symbols. [manual]
3. The official release workflow MUST NOT upload source context with PostHog crash symbols by default. [manual]
4. An official release with PostHog crash tracking enabled MUST remain unpublished until PostHog confirms acceptance of the dSYM corresponding to the distributed app. [manual]

## Manual acceptance criteria

- Download the latest release `.dmg` from GitHub Releases on a clean or disposable Mac user account.
- Open the `.dmg`, drag `PiNative.app` to Applications, eject the volume, and launch from `/Applications`.
- Confirm launch does not require right-click Open or `xattr -dr com.apple.quarantine`.
- Confirm `spctl --assess --type open --context context:primary-signature -vv PiNative-<version>.dmg` accepts the disk image.
- Confirm `codesign --verify --deep --strict --verbose=2 /Applications/PiNative.app` succeeds.
- Confirm the release notes and README clearly state that Pi is an external prerequisite.
- For an official release with PostHog crash tracking enabled, confirm the preserved dSYM UUIDs match the distributed app, PostHog accepted that dSYM before publication, source context was not uploaded, and symbol-upload credentials were confined to release CI.

## Non-goals

- This spec does not require Mac App Store distribution.
- This spec does not require automatic in-app updates.
- This spec does not require supporting unsigned community builds with the same launch experience as official releases.
- This spec does not require bundling, installing, or updating Pi.
- This spec does not itself enable PostHog crash tracking; REQ-006.6 applies only when that capability is enabled separately.
