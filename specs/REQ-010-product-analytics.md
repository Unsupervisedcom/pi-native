# REQ-010: Product Analytics

## Overview

PiNative reports pseudonymous, content-free product interaction and health
diagnostic events to its configured PostHog project. Analytics are enabled by
default when configured, and users can disable them from Settings.

## Event contract

When analytics are configured and enabled, PiNative reports these events, each
with exactly its listed fixed properties and no others:

| Event | Outcome | Fixed properties (enumerated values) |
| --- | --- | --- |
| `app_opened` | The app launches. | None. |
| `chat_started` | A user creates a new chat. | None. |
| `prompt_submitted` | A user submits a prompt in a new or existing chat. | None. |
| `settings_opened` | A user opens Settings. | None. |
| `right_pane_opened` | A user opens a built-in right-pane tool. | `pane`: `review`, `browser`, `plugins`, `archivedChats`. |
| `pi_load_failed` | Pi terminally fails to start or load a chat session. | `stage`: `process_start`, `session_load`. `failure_kind`: `process_lifecycle`, `request_timed_out`, `invalid_response`, `write_failed`, `launch_failed`, `unknown`. `is_project_chat`: `true`, `false`. |
| `handled_exception` | PiNative surfaces a handled user-visible Pi operation failure other than a start or session-load failure. | `area`: `model_selection`, `effort_selection`, `prompt_submission`, `extension_ui_response`. `failure_kind`: `request_timed_out`, `invalid_response`, `write_failed`, `unknown`. |

## Requirements

### REQ-010.1: Event delivery

1. When analytics are configured and enabled, PiNative MUST report the applicable event from the event contract, with exactly its documented fixed properties and enumerated values, when its documented outcome occurs.
2. PiNative MUST report exactly one `pi_load_failed` event per terminal Pi start or session-load failure, regardless of whether an automatic retry was attempted.

### REQ-010.2: User control

1. A user MUST be able to enable or disable analytics from Settings and have that preference persist across app launches.
2. While a user has disabled analytics, PiNative MUST NOT report analytics events.

### REQ-010.3: Privacy

1. PiNative-defined analytics event properties MUST NOT include prompt text, attachment names or contents, local filesystem paths, session identifiers, project identifiers, model names, provider names, raw exception text, or user account identifiers.

### REQ-010.4: Automatic exception tracking disabled

1. PiNative MUST NOT emit PostHog automatic exception (`$exception`) events.

### REQ-010.5: Unconfigured operation

1. When the PostHog project key is absent or invalid, PiNative MUST continue to operate without reporting analytics events.

## Manual acceptance criteria

- Launch a configured build, start a chat, submit prompts in a new and existing
  chat, open Settings and a right-pane tool, and confirm the matching events
  arrive with only their documented fixed properties and enumerated values.
- Induce a terminal Pi start/load failure, including a scenario with an
  automatic retry, and confirm exactly one sanitized `pi_load_failed` event
  arrives. Induce a handled Pi operation failure and confirm a sanitized
  `handled_exception` event arrives. Neither event should contain
  user-generated or local-workspace data.
- Disable analytics in Settings, repeat an interaction, and confirm no event
  arrives. Relaunch, confirm the preference persists, re-enable analytics, and
  confirm reporting resumes.
- In a non-production test build without an attached debugger, force a
  supported crash and relaunch PiNative; confirm PostHog receives no
  `$exception` event.

## Non-goals

- Identifying users or associating analytics with Pi, provider, or account identities.
- Capturing prompt text, attachment metadata, project/session metadata, terminal
  output, browser content, or actions taken within an open right-pane tool beyond
  the fact that it was opened.
- Reporting unhandled process crashes (Mach exceptions, `SIGSEGV`, `SIGABRT`,
  `SIGBUS`, `NSException`) as PostHog `$exception` events. This is an
  intentional privacy tradeoff: PiNative's own sanitized `pi_load_failed` and
  `handled_exception` events remain the only supported health diagnostics.
- Session replay, automatic exception tracking, raw handled-exception capture,
  logs, feature flags, surveys, experiments, or source-context upload.
