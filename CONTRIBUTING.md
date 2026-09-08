# Contributing to PiNative

Thank you for helping improve PiNative. The project aims to be a polished native macOS GUI for Pi, with reliability and native Mac craft treated as equally important.

## Before you start

- Search existing issues and pull requests before opening a duplicate.
- Use an issue to discuss substantial features, architecture changes, or changes in product behavior before implementation.
- Keep each contribution focused. Do not combine unrelated cleanup with the requested change.
- Read [`AGENTS.md`](AGENTS.md) for repository-specific engineering guidance.

## Development setup

You need:

- A Mac running macOS 14 or newer.
- The full Xcode app, selected with `xcode-select`.
- Pi installed and configured so `pi --mode rpc` starts successfully.

Clone the repository and build it:

```sh
git clone https://github.com/Unsupervisedcom/pi-native.git
cd pi-native
xcodebuild -project PiNative.xcodeproj -scheme PiNative \
  -configuration Debug -destination 'platform=macOS' build
```

You can also open `PiNative.xcodeproj`, select the `PiNative` scheme, and run with `⌘R`. See [`docs/build-and-run.md`](docs/build-and-run.md) for troubleshooting and release-build details.

Optional local settings belong in ignored files:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
cp Config/Signing.xcconfig.example Config/Signing.xcconfig
```

Only create these files when needed, and never commit credentials, tokens, signing identities, or local account details.

## Requirements and testing

Observable feature behavior is specified under [`specs/`](specs/) using RFC 2119 requirements. When changing product behavior, update or add the specification before adding requirement-linked tests. Follow the complete workflow in [`docs/requirements-and-testing.md`](docs/requirements-and-testing.md).

Run the bounded unit and integration suite during development:

```sh
scripts/test-unit.sh
```

Focused tests can be passed through to `xcodebuild`, for example:

```sh
scripts/test-unit.sh -only-testing:PiNativeTests/ModelSettingsTests
```

Before submitting a change:

1. Build the app and run the focused tests for the behavior you changed.
2. Run `npx --yes rfc2119 lint` when specifications change.
3. Run `npx --yes rfc2119 check` when requirement semantics or mapped test behavior changes.
4. Verify affected UI directly in the built app. UI automation controls the desktop, so run it only in an appropriate environment; use `scripts/test-ui-related.sh` for UI tests related to changed app files.
5. For behavior involving real Pi RPC events, authentication, provider state, session state, persistence, or process lifecycle, provide real-Pi integration evidence where safely repeatable. Do not present mock-only tests as end-to-end proof.

## Pull requests

A pull request should:

- Explain the user-visible problem and the chosen solution.
- Link the relevant issue.
- Describe tests and direct verification performed, including any gaps.
- Include screenshots or recordings for intentional UI changes, while excluding private user data.
- Keep requirements, tests, and durable documentation aligned with behavior.
- Avoid generated build products, local configuration, unrelated formatting, and drive-by refactors.

## Repository privacy and hygiene

This is a public repository. Before committing, inspect both staged changes and newly added files.

Do not commit:

- Prompts, transcripts, provider responses, credentials, tokens, or private API data.
- Personal filesystem paths, project names, account details, or local session data.
- Private research, exploratory plans, or named third-party design references. Keep exploratory work under the ignored `research/` directory or outside the repository, and refer generically to a “reference app” in tracked material when needed.
- Ad hoc screenshots, recordings, test evidence, or generated reports. Store temporary evidence outside the repository, such as under `/tmp`.

Intentional product assets and reviewed durable documentation may be tracked. In particular, `docs/readme-screenshot.png` is a public product asset, and `docs/code-architecture-walkthrough.html` is intentionally versioned as the browsable form of the Markdown-backed architecture walkthrough. When updating that walkthrough, follow [`docs/code-architecture-walkthrough.md`](docs/code-architecture-walkthrough.md), update its sources and rendered HTML together, and inspect the result before submitting it.

Report security concerns privately as described in [`SECURITY.md`](SECURITY.md), never through a public issue.

## License

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE). Bundled third-party assets retain their own licenses; review [`docs/THIRD_PARTY_LICENSES.md`](docs/THIRD_PARTY_LICENSES.md) before adding or replacing assets.
