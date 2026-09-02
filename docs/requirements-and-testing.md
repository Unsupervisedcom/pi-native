# Requirements and Testing

PiNative uses executable RFC 2119 requirements to keep observable product behavior aligned with automated and manual verification.

## Where requirements live

- `specs/` contains numbered product requirements under `### REQ-NNN.M` headings.
- Automated tests include comments such as `// 2119: REQ-003.4.1` to identify the behavior they cover.
- Requirements that depend on subjective visual judgment, configured external services, or release infrastructure remain explicitly manual.
- `.2119/` stores generated coverage and review metadata used by the requirements tooling.

Current specifications cover composer attachments, Promote to Project, conversation navigation and parallel work, shell layout, chat readiness, and release distribution.

## Required validation

### Local unit and integration tests

Use the unit helper during implementation:

```sh
scripts/test-unit.sh
```

The helper runs the `PiNativeUnitTests` scheme, excludes `PiNativeUITests`, streams concise test progress, and enforces bounded timeouts. Pass normal `xcodebuild test` filters after the script name for focused runs, for example:

```sh
scripts/test-unit.sh -only-testing:PiNativeTests/ComposerPromptHistoryUnitTests
```

### Pull request workflow checks

Pull requests run two GitHub Actions workflows:

1. **CI / Requirements and unit tests** (`.github/workflows/ci.yml`) is the blocking merge gate. It runs:

   ```sh
   npx --yes rfc2119 lint
   npx --yes rfc2119 check
   xcodebuild test -project PiNative.xcodeproj -scheme PiNativeUnitTests \
     -destination 'platform=macOS' -parallel-testing-enabled NO
   xcodebuild build-for-testing -project PiNative.xcodeproj -scheme PiNativeUnitTests \
     -destination 'platform=macOS' -parallel-testing-enabled NO
   ```

2. **UI Tests / Deterministic macOS UI tests** (`.github/workflows/ui-tests.yml`) is a required smoke/regression gate. It runs:

   ```sh
   scripts/test-ui-deterministic.sh
   ```

   This workflow builds PiNative, compiles the full UI test bundle, launches the real app on a hosted `macos-15` runner, and drives the currently stable deterministic XCUITest subset. Tests that require live Pi/provider state or are quarantined for CI-environment fragility remain skipped at runtime but compile with the bundle. The gate catches UI test bundle compile failures, app launch failures, accessibility identifier regressions, and stable mocked-flow interaction regressions. Because hosted macOS runners can differ from developer machines in timing, focus, permissions, keychain state, and installed tooling, failures should be investigated from the uploaded result bundle before assuming they reproduce locally.

### Local UI test helpers

Before pushing app changes, run the focused related-UI helper:

```sh
scripts/test-ui-related.sh
```

This compiles the entire `PiNativeUITests` bundle, then runs only UI tests selected from changed app files. UI-test-only changes compile the bundle but may not run a runtime UI flow unless explicit `-only-testing:` filters are supplied.

To reproduce the required CI UI workflow locally, run:

```sh
scripts/test-ui-deterministic.sh
```

This uses real XCUITest interactivity with a launched app, like CI, but skips live or real-Pi integration UI tests.

### CI UI tests versus local/live verification

The deterministic CI UI workflow runs on a fresh hosted Mac. It does not use the developer's local Pi authentication, provider credentials, projects, persisted chats, keychain approvals, or filesystem state unless a test explicitly creates mock data for them. Your local environment can verify more realistic end-to-end behavior because it has your configured Pi installation and persisted app state.

Some UI tests use mock RPC responses. The opt-in live RPC smoke tests require a working Pi installation and configured model/provider credentials, so they are skipped by deterministic CI even though they still compile as part of the UI test bundle. Use `docs/smoke-test.md` for manual real-Pi verification scenarios when behavior depends on live Pi RPC, auth, provider catalogs, or local session state.

## What the requirements gate protects

The current suite includes coverage for:

- Attachment classification, prompt assembly, and image RPC payloads.
- Promote to Project validation, path containment, provenance, retries, and handoff behavior.
- Per-conversation runtime ownership, navigation during active work, output isolation, and scoped Stop behavior.
- Transcript persistence, hydration, and protection against stale or empty session data.
- Chat readiness and catastrophic RPC failure behavior.
- Shell layout invariants and release-distribution expectations.

The requirements gate complements normal implementation review and visual verification; it does not replace either.
