# Changelog

## 2026-09-02


### Added

- Added inline steering for active conversations, including ordered per-chat pending messages, attachment support, rejection recovery, and retryable replay after Stop without duplicate delivery.

### Changed

- Scoped official release credentials to a dedicated GitHub environment and replaced the stored temporary-keychain password with a fresh per-run value.

## 2026-09-01


### Fixed

- Kept the Pi recovery status bar visible and actionable on smaller displays by allowing the app window to fit within the available screen height.
- Kept unresolved Pi recovery alerts visible until the user starts the Terminal recovery flow, and refined the status bar with aligned text, an adjacent compose-blue action, and a pointing-hand hover cursor.
- Restored reliable conversation navigation UI coverage, including transcript restoration, startup-ready model and effort selectors, broad sidebar row selection, and correct hidden/visible trailing-control behavior.

## 2026-08-31


### Fixed

- Corrected Pi executable discovery documentation and exposed distinct accessibility targets for project sidebar controls.
- Pending Changes now clearly identifies its initial Git-loading state and consistently replaces prior project status when reviewing another project.
- Prevented Pending Changes from briefly showing one project's summary while another project loads.
- Interactive Pi questions raised by live conversations now activate the global Terminal recovery bar while preserving the originating chat’s explanation. Shell layout UI tests no longer depend on the user’s local Pi configuration.

### Removed

- Removed dormant shell navigation and unused interface components.

## 2026-08-20

### Added

- Added flexible Pi installation discovery, a bounded startup RPC health check, and a global recovery bar that opens Pi in Terminal for installation, setup, or authentication issues.

## 2026-08-19

### Changed

- Disabled PostHog's automatic exception/crash tracking; PiNative now only reports its own sanitized `pi_load_failed` and `handled_exception` diagnostic events. Simplified the product-analytics specification into five broad, testable requirements. Added a local `Config/Secrets.xcconfig.example` template for the PostHog project token and wired `POSTHOG_PROJECT_API_KEY` into official release builds via a GitHub Actions secret.
- Made Apple signing-team configuration maintainer-supplied for local and CI release builds.

## 2026-08-18

### Added

- Added optional privacy-conscious product analytics and crash diagnostics.

### Changed

- Improved unit-test execution limits and reporting.

### Removed

- Removed an unused terminal integration dependency while retaining the Terminal pane placeholder.

## 2026-08-17

### Added

- Added a Developer ID signed and notarized DMG release workflow with checksums and draft GitHub Releases.

## 2026-08-11

### Added

- Added automatic sidebar titles for newly created chats after their first completed response.

### Changed

- Improved test organization and CI reporting for unit and UI coverage.

### Fixed

- Improved Pi RPC event ordering, session restart behavior, and automatic-title cleanup.

## 2026-08-04

### Added

- Added CI validation for requirements, unit tests, and macOS builds.
- Added independent Pi runtimes for simultaneous conversations.

### Fixed

- Improved project-promotion safety and conversation handoff behavior.

## 2026-07-22

### Added

- Added project promotion, sidebar pinning, and composer attachments.

### Fixed

- Improved chat startup, switching, and transcript persistence reliability.

## 2026-07-07

### Added

- Added the native three-pane workspace, project diffs, browser pane, plugins, and bundled code typography.

### Fixed

- Improved Pi RPC command handling, session persistence, and navigation reliability.

## 2026-06-23 through 2026-07-06

### Added

- Created the initial macOS application.
