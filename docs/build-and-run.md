# Build & Run

## Toolchain

Building this project requires the full Xcode toolchain, not just the
Command Line Tools. If `xcodebuild` errors with:

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools
instance
```

point the active developer directory at Xcode.app instead:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Building/running from the command line

```
xcodebuild -project PiNative.xcodeproj -scheme PiNative \
  -configuration Debug -destination 'platform=macOS' build
```

This uses the same scheme (`PiNative`) and DerivedData location that
Xcode's own ⌘R build uses, so a CLI build and an Xcode build are the same
artifact — there is no separate/stale copy produced by one path vs. the
other.

PiNative now uses the organization-owned bundle identifier
`com.unsupervised.PiNative`. macOS treats a build using the previous identifier
as a different app, so local permission grants and bundle-scoped preferences do
not migrate automatically.

## Building an internal unsigned DMG

For coworker testing, build a clearly labeled internal unsigned DMG:

```
scripts/build-release-dmg.sh --unsigned-internal 0.1.0
```

Expected outputs:

```
dist/PiNative-0.1.0-internal-unsigned.dmg
dist/PiNative-0.1.0-internal-unsigned.dmg.sha256
```

This DMG is for internal testing only. It is not Developer ID signed or
notarized, so macOS may warn that the developer cannot be verified. That warning
is expected for this temporary test artifact and does not represent the final
release experience.

## Building an official DMG

Official releases use the `--official` mode, which requires `APPLE_TEAM_ID`,
the organization Developer ID certificate, and a `notarytool` keychain profile. It signs,
notarizes, staples, and Gatekeeper-verifies the final artifact:

```
APPLE_TEAM_ID=YOUR_APPLE_TEAM_ID \
  scripts/build-release-dmg.sh --official 0.1.0 \
    --build-number 1 \
    --notary-profile pinative-notary
```

Use the tagged GitHub Actions release workflow for publishable artifacts rather
than uploading a locally built DMG. One-time Apple credentials, GitHub Actions
configuration, and the draft-release procedure are documented in
[Releasing PiNative](releasing.md).

## Avoiding "it's running an old version" confusion

If Xcode appears to launch a stale build after source changes:

1. First suspect DerivedData/Xcode build-cache staleness, not a source
   mismatch: `Product > Clean Build Folder` (⇧⌘K) in Xcode, or
   `rm -rf ~/Library/Developer/Xcode/DerivedData/PiNative-*` from the
   shell, then rebuild.
2. Confirm you're not launching a previously-built copy of `PiNative.app`
   from Finder/Spotlight/Dock instead of the one Xcode just built. Check
   `ps aux | grep PiNative` for the actual running binary's path — it
   should be under
   `~/Library/Developer/Xcode/DerivedData/PiNative-*/Build/Products/...`.
3. Confirm the scheme selector in Xcode's toolbar is set to `PiNative`
   (the project currently defines exactly one scheme, `PiNative`, plus
   the `PiNativeUITests` target).

## Agent workflow note

When an agent (e.g. Claude Code via `pi`) makes source changes in this
repo, it should do a CLI build via the command above before handing back,
to confirm the change compiles cleanly against the same scheme/DerivedData
Xcode itself will use for ⌘R. That keeps "run it from Xcode" and "the agent
just changed something" in sync without needing to relaunch or reset
anything beyond a normal build.
