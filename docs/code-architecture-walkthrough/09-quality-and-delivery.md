# Quality & Delivery

## Test layers

- [AttachmentSupportTests.swift](http://127.0.0.1:43117/open?path=PiNativeTests/AttachmentSupportTests.swift&line=1) covers classification, prompt assembly, image RPC encoding, and promotion defaults.
- [ParallelRuntimeTests.swift](http://127.0.0.1:43117/open?path=PiNativeTests/ParallelRuntimeTests.swift&line=1) covers keyed runtime navigation, output/draft isolation, scoped Stop, archive guards, and shutdown cleanup.
- [StopButtonTests.swift](http://127.0.0.1:43117/open?path=PiNativeTests/StopButtonTests.swift&line=1) covers immediate Stop and late-event fencing.
- [RequirementsCoverageTests.swift](http://127.0.0.1:43117/open?path=PiNativeTests/RequirementsCoverageTests.swift&line=1) exercises promotion safety, retries, persistence, hydration, and readiness invariants.
- [PiNativeUITests.swift](http://127.0.0.1:43117/open?path=PiNativeUITests/PiNativeUITests.swift&line=1) uses environment-controlled mock/stall/failure modes plus an opt-in real-Pi smoke test.

## Requirements discipline

- Observable obligations live in the Markdown specs under [specs](http://127.0.0.1:43117/open?path=specs/REQ-003-conversation-navigation-and-active-work.md&line=1).
- Automated tests carry `// 2119: REQ-…` markers; manual-only UI/release obligations stay explicit.
- [ci.yml](http://127.0.0.1:43117/open?path=.github/workflows/ci.yml&line=1) runs RFC 2119 lint/check, serialized unit tests, and build-for-testing on macOS.

## Build and distribution

- [run-app.sh](http://127.0.0.1:43117/open?path=scripts/run-app.sh&line=1) builds into repo-local DerivedData and safely relaunches the app.
- The Xcode project targets macOS 14 and Swift 6, with PostHog as its package dependency.
- [build-release-dmg.sh](http://127.0.0.1:43117/open?path=scripts/build-release-dmg.sh&line=1) currently creates clearly labeled internal unsigned DMGs and checksums.
- Developer ID signing, notarization, polished artwork, and tagged draft releases remain the active distribution milestone.
