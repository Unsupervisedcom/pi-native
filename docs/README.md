# Project Documentation

This directory contains durable implementation notes for PiNative. For the
product north star / craft principles that should guide decisions here, see
`AGENTS.md` at the repo root.

- [Code Architecture Walkthrough](code-architecture-walkthrough.html) — visual, source-linked tour of features, navigation, persistence, Pi communication, chat lifecycle, and supporting surfaces. See the [walkthrough maintenance notes](code-architecture-walkthrough.md) when refreshing it.
- [Native Shell Architecture](native-shell-architecture.md) — deeper layout, navigation, pane-state, runtime-ownership, and transcript-grouping details not repeated in the walkthrough.
- [Build & Run](build-and-run.md) — Xcode setup, command-line builds, internal DMGs, and stale-build troubleshooting.
- [Requirements and Testing](requirements-and-testing.md) — RFC 2119 workflow, CI gate, and automated test commands.
- [Smoke Test](smoke-test.md) — agent-assisted real-Pi verification scenarios for behavior that mocks do not fully cover.
- [Third-Party Licenses](THIRD_PARTY_LICENSES.md) — licenses for bundled assets that differ from this project's MIT license.

Keep this `docs/` directory focused on decisions, architecture, and implementation references that describe how the app currently works and should stay accurate as it evolves. Record only durable outcomes here; keep exploratory planning outside the tracked repository.
