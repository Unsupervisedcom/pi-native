# PiNative Smoke Test Plan

This checklist is for agent-assisted manual verification of PiNative’s **basic app
functionality**. It includes real `pi --mode rpc` checks where mock tests are least
representative, but it is not only a parallel-runtime checklist.

Use this when a change touches chat lifecycle, composer behavior, navigation, shell
layout, attachments, Promote to Project, or anything where “the app feels weird” is a
plausible failure mode.

## What this plan covers

| Area | Specs | Manual focus |
|---|---|---|
| Launch and chat readiness | REQ-003, REQ-005 | Existing chats load, composer is usable immediately, catastrophic Pi failures are visible. |
| Core chat send loop | REQ-003, REQ-005 | Type, Enter submit, user message appears, Pi replies, composer clears, transcript stays at bottom. |
| Conversation navigation | REQ-003 | Quick Chat creation, project/chat row selection, transcript restoration, draft isolation, pinned/archived expectations. |
| Active work and parallel chats | REQ-003 | Switching while running, concurrent Quick/project turns, per-chat running indicators, scoped Stop. |
| Composer attachments | REQ-001 | Paste, drag/drop, and `+` picker for image and file-reference attachments. |
| Composer prompt history | REQ-008 | Empty-only Up recall, Up/Down traversal, attachment fidelity, edit behavior, and per-chat isolation. |
| Promote to Project | REQ-002 | Basic Quick Chat promotion smoke, modal progress, handoff, source archive, and deeper safety/error paths. |
| Shell chrome | REQ-004 | Sidebar toggles, right pane, titlebar controls, center content remains usable. |
| Release distribution | REQ-006 | Separate release checklist; not part of routine live-Pi smoke unless validating a release. |

## Test modes

### Mode A — Routine real-Pi smoke

Use this for most branch verification. It requires real Pi and exercises user-visible
chat behavior.

- Real `pi --mode rpc`.
- No mock response env vars.
- Existing local projects/chats are allowed and useful.
- Screenshots are required for pass/fail evidence.

### Mode B — Focused feature pass

Use this when a branch touches a specific area:

- Attachments: add the attachment scenarios.
- Prompt history: add Scenario 2A.
- Promote to Project: add the promotion scenarios.
- Shell layout: add the shell scenarios.
- Release work: use the release distribution checklist section.

### Mode C — Debug/mock tests

Automated mock/unit tests still matter, but they do not replace Mode A. Use them for
repeatability after manual verification catches the real-Pi behavior.

## Prerequisites

- `pi` is installed and configured on this Mac.
- PiNative builds successfully in Debug.
- Network/model credentials are available for the configured Pi model.
- The tester can capture the PiNative window by `CGWindowNumber`.
- For attachment checks, have a small PNG/JPG and a small readable text/PDF file handy.
- For Promote to Project, know a temporary project name/path that can be safely created.

Do **not** set these during Mode A real-Pi testing:

```sh
PI_NATIVE_MOCK_RPC_RESPONSE
PI_NATIVE_TEST_RPC_STALL
PI_NATIVE_TEST_PI_EXECUTABLE
```

## Agent-assisted smoke procedure

There is intentionally no checked-in live-smoke automation script. This repo will be public, and local Accessibility/screenshot helpers are environment-specific. An agent running this checklist should create any temporary helpers under `/tmp`, avoid committing evidence artifacts, and report exactly which scenarios were covered.

From the repo root:

```sh
xcodebuild -project PiNative.xcodeproj \
  -scheme PiNative \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pinative-smoke-derived-data \
  build CODE_SIGNING_ALLOWED=NO

pkill -x PiNative || true
open -n /tmp/pinative-smoke-derived-data/Build/Products/Debug/PiNative.app
```

Capture the commit under test:

```sh
git rev-parse --short HEAD
```

## Interaction procedure

Prefer Accessibility-driven interaction over raw screen coordinates:

- Use exposed accessibility identifiers such as `sidebar.newChatButton`, `project.row`, `composer.textEditor`, `arrow.up`, `stop.fill`, and transcript identifiers.
- Select rows by accessibility description/text when possible.
- Set composer text through the accessibility text area rather than clipboard-and-click when possible.
- If a hover-only control must be clicked, derive its current frame from Accessibility attributes first; do not hardcode absolute screen coordinates.

## Screenshot procedure

Capture the actual PiNative window, not a fixed screen region.

```swift
// /tmp/pinative_window_info.swift
import CoreGraphics
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    if owner == "PiNative" {
        let id = w[kCGWindowNumber as String] as? Int ?? 0
        let title = w[kCGWindowName as String] as? String ?? ""
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        print("\(id)\t\(bounds)\t\(title)")
    }
}
```

```sh
win=$(swift /tmp/pinative_window_info.swift | awk 'NR==1{print $1}')
screencapture -x -o -l"$win" /tmp/pinative-smoke-01.png
```

Save screenshots under `/tmp/pinative-smoke-XX.png` and include them in the final
summary.

---

# Core smoke scenarios

Run these for most meaningful app changes.

## Scenario 1 — Launch, initial selection, and existing chat readiness

1. Launch PiNative with real Pi.
2. Observe the initial selected project/chat or New Chat state.
3. Select a pre-existing project chat, ideally one with real saved transcript history.
4. Immediately click/focus the composer and type a short unsent draft.
5. Wait 5–10 seconds for any Pi startup/session hydration/model refresh to finish.
6. Capture a screenshot.

Pass criteria:

- The selected sidebar row, chat header, transcript, and composer all refer to the same chat.
- Available transcript content appears; a known non-empty chat is not blank.
- Composer is focusable before session loading completes.
- Typed draft does not disappear during hydration.
- Model and effort controls are visible and usable unless a catastrophic per-chat Pi error is shown.
- If Pi startup fails catastrophically, visible red feedback appears and composer disables for that chat.

## Scenario 2 — Basic send loop with Enter

1. In an existing chat, type:
   `manual smoke test: reply with exactly OK`
2. Press Enter.
3. Wait for Pi to reply.
4. Capture a screenshot.

Pass criteria:

- Enter submits instead of silently doing nothing.
- The user message appears in the transcript.
- Pi reply appears in the same transcript.
- Composer clears after submit.
- Transcript reveals the bottom/current turn.
- Sidebar row title/summary may update, but selection and transcript do not jump to another chat.

## Scenario 2A — Empty-only prompt history

1. In a chat with several prior user messages, leave the composer empty and press Up repeatedly.
2. Press Down repeatedly until the composer clears after the newest recalled prompt.
3. Type a non-empty draft and press Up; then clear it, add an attachment without text, and press Up again.
4. Recall a prompt, edit it, press Up, and confirm the edit remains instead of being replaced.
5. Switch to a chat with different prior prompts, clear its composer, and press Up.

Pass criteria:

- Empty-only Up recall traverses the selected chat newest-to-oldest and clamps at the oldest prompt.
- Down traverses toward newer prompts and clears after the newest.
- Recalled text and attachment chips match the original prompt.
- Text and attachment-only drafts are never replaced by history.
- Editing ends browsing, and prompts from another chat never appear.

## Scenario 3 — Draft isolation and transcript restoration across chats

1. Select Chat A.
2. Type an unsent draft: `draft belongs to chat A`.
3. Select Chat B.
4. Verify Chat B does not show Chat A’s draft.
5. Type `draft belongs to chat B` without sending.
6. Switch back to Chat A.
7. Switch back to Chat B.
8. Capture screenshots for both chats.

Pass criteria:

- Drafts never leak between chats.
- Returning to a chat restores its transcript near recent content, not the top of a long chat.
- Header, selected row, transcript, running state, and composer draft remain internally consistent.
- Re-selecting the same chat does not replace a visible transcript with an empty transcript.

## Scenario 4 — Sidebar row hit targets and project-row behavior

1. Click a project row, not a nested chat row.
2. Confirm it opens the most recently updated visible, unpinned, unarchived chat in that project.
3. Click several chat rows at left/center/right non-control points.
4. Hover rows so trailing controls appear, then click non-control row areas again.
5. Capture a screenshot after representative clicks.

Pass criteria:

- Project rows select the project’s normal visible chat.
- Archived chats are not selected by project-row click.
- Pinned chats are not selected by project-row click.
- Hidden hover controls do not create dead row-selection zones.
- Visible trailing controls remain controls; clicking them should not accidentally select/archive the wrong row.

## Scenario 5 — Quick Chat basic flow

1. Click the global New Chat action.
2. Confirm the new-chat surface appears with a projectless composer, normally showing `Choose project`.
3. Submit:
   `quick chat smoke test: reply with one short sentence`
4. Wait for Pi reply.
5. Switch to a project chat.
6. Switch back to the new Quick Chat row.
7. Capture a screenshot.

Pass criteria:

- Global New Chat opens a projectless Quick Chat composer.
- A new session row appears in the Quick Chats section after the first prompt is submitted.
- User message and Pi reply appear in the Quick Chat transcript.
- Composer clears after submit.
- The Quick Chat remains selectable after switching away and back.
- The Quick Chat transcript does not appear under any project chat.

## Scenario 6 — Basic Promote to Project smoke

1. Start from the projectless Quick Chat created in Scenario 5.
2. Open Promote to Project from the Quick Chat header/subtitle or row action.
3. Enter a temporary project name, for example `PiNative Smoke Promote <timestamp>`.
4. Confirm the destination preview points under the configured Settings project folder.
5. Run promotion.
6. When promotion completes, click Open Project or the equivalent handoff control.
7. Capture screenshots of the modal progress and final promoted project chat.

Pass criteria:

- Promote is available for a projectless Quick Chat and not presented as a project-chat action.
- The modal accepts only a project name for the basic happy path.
- Destination preview is understandable before running promotion.
- Progress clearly shows pending/running/completed/skipped/failed states.
- Inputs are disabled while promotion is running.
- Success creates or reuses the destination as a PiNative project.
- A new project-scoped chat opens with promoted context from the source Quick Chat.
- The source Quick Chat is archived or otherwise removed from the normal Quick Chats list while remaining recoverable.

## Scenario 7 — Project-scoped New Chat basic flow

1. Use a project row’s visible New Chat control or the project picker to create a new chat in the current project.
2. Confirm the new-chat composer is bound to the intended project.
3. Submit:
   `project chat smoke test: reply with one short sentence`
4. Wait for Pi reply.
5. Switch to another chat, then switch back.
6. Capture a screenshot.

Pass criteria:

- A project-scoped new chat opens without breaking existing Quick Chat or project chat runtimes.
- A new session row appears under the intended project.
- User message and Pi reply appear in the project chat transcript.
- Composer clears after submit.
- The project chat remains selectable after switching away and back.
- The project chat transcript does not appear in Quick Chats.

## Scenario 8 — Shell chrome and center usability

1. With a chat selected, toggle the left sidebar hidden/shown.
2. Open the right pane using the app’s toolbar/shortcut, then close it.
3. If available, switch right-pane modes such as Review/Browser/Plugins.
4. Resize the window narrower and wider.
5. Capture screenshots with sidebars hidden and visible.

Pass criteria:

- Center chat content remains visible and usable after each sidebar toggle.
- Composer is not hidden behind sidebars or titlebar regions.
- Header, transcript, and composer stay aligned as one centered stack.
- Titlebar controls remain anchored and visually stable.
- Right-pane controls do not retarget or stop the active chat.

---

# Active work and parallel runtime scenarios

Run these for chat lifecycle/runtime changes and periodically for regression checks.

## Scenario 9 — Navigate while one chat is running

1. Select Chat A.
2. Send a command-backed slow prompt, for example:
   `Use the shell to run exactly \`sleep 45; echo A_DONE\`, and do not reply until that command finishes.`
3. As soon as Chat A shows Stop/running state, select Chat B.
4. Capture a screenshot while Chat A continues.

Pass criteria:

- Chat B becomes selected immediately.
- Chat A remains visibly marked as working in the sidebar.
- Chat B’s composer is usable.
- Output from Chat A does not append to Chat B.

## Scenario 10 — Two chats running concurrently

1. While Chat A is still running, create/select Chat B and send:
   `Use the shell to run exactly \`sleep 30; echo B_DONE\`, and do not reply until that command finishes.`
2. After at least 5 seconds, capture a screenshot while both are running.
3. Wait for one chat to finish; capture another screenshot.
4. Wait for both to finish.

Pass criteria:

- Both chats can run at the same time.
- Both rows show independent running indicators while active.
- Completion clears only the completed chat’s indicator.
- Each transcript contains only its own user messages and Pi output.

## Scenario 11 — Stop selected chat only

1. Start a command-backed slow prompt in Chat A, for example `sleep 45; echo A_DONE`.
2. Switch to Chat B and start a separate command-backed slow prompt, for example `sleep 45; echo B_DONE`.
3. After Chat B shows Stop/running state and before its command finishes, press Stop.
4. Return to Chat A.
5. Capture screenshots before and after Stop.

Pass criteria:

- Chat B promptly leaves running state.
- Chat B composer becomes usable for a later prompt.
- Late Chat B output does not keep appending after Stop.
- Chat A continues and can complete normally.

## Scenario 12 — New Chat while work is active

1. Start a command-backed slow prompt in Chat A, for example `sleep 45; echo A_DONE`.
2. Click New Chat while Chat A is running.
3. Submit a prompt in the new chat. For a Quick Chat check, leave it projectless; for a project-chat check, bind it to the current project first.
4. Capture screenshots before and after submission.

Pass criteria:

- New Chat opens without being blocked by Chat A.
- Chat A remains marked running.
- New chat can be created and used.
- Output from Chat A does not append to the new chat.

---

# Attachment scenarios

Run when composer/attachment code changes, or before a release.

## Scenario 13 — Image attachment workflows

Use a small PNG or JPG.

1. Paste an image into the composer.
2. Verify an image attachment chip appears.
3. Send with short text: `describe this image briefly`.
4. Repeat with drag/drop of an image file.
5. Repeat with the composer `+` picker selecting an image file.
6. Capture screenshots with chips visible and after send.

Pass criteria:

- Paste, drag/drop, and `+` picker all create visible image chips.
- Attachment-only drafts are sendable.
- Sending does not convert image attachments into file-reference text unexpectedly.
- Pi receives enough image context to respond appropriately, subject to model capability.

## Scenario 14 — File-reference attachment workflows

Use a small readable text/PDF file.

1. Paste a Finder file into the composer.
2. Verify a file attachment chip appears.
3. Send with text: `acknowledge this attached file path`.
4. Repeat with drag/drop.
5. Repeat with the composer `+` picker.
6. Try a missing/unreadable file if practical.

Pass criteria:

- Paste, drag/drop, and `+` picker create visible file chips.
- File attachments are sent as file references, not hidden full-content paste.
- Attachment-only file drafts are sendable.
- Missing/unreadable files produce a visible attachment error instead of a broken chip.

---

# Promote to Project scenarios

Run when projectless chat, Settings project folder, or promotion code changes.

## Scenario 15 — Projectless chat promotion happy path

1. Create or select a projectless Quick Chat.
2. Have a short transcript with at least one user message and Pi reply.
3. Open Promote to Project.
4. Enter only a project name.
5. Run promotion.
6. Capture progress and final state screenshots.

Pass criteria:

- Destination preview is understandable and derived from Settings default code folder plus project name.
- Modal communicates pending/running/completed/skipped/failed steps clearly.
- Inputs are disabled while promotion runs.
- Success adds or reuses the destination as a PiNative project.
- A new project-scoped chat opens with promoted planning context.
- Source Quick Chat is archived but recoverable with session/transcript retained.

## Scenario 16 — Promotion safety/error path

1. Try promotion with an unsafe destination shape if practical: existing file, non-empty unmarked folder, or path outside allowed code folder.
2. Capture the error state.
3. Retry after correcting the issue.

Pass criteria:

- Unsafe destination is rejected before destructive writes.
- Error is concise and actionable.
- Retry does not overwrite existing generated artifacts or duplicate project registration/log/provenance.

---

# Release distribution checklist

Use this only when validating a release artifact, not during routine Debug app testing.

## Scenario 17 — Release DMG verification

1. Download the latest release `.dmg` from GitHub Releases on a clean/disposable Mac user account.
2. Confirm release notes identify version, macOS 14+ requirement, and Pi as an external prerequisite.
3. Confirm checksum information is present.
4. Open the DMG.
5. Drag `PiNative.app` to Applications.
6. Eject the volume.
7. Launch from `/Applications`.
8. Run signing/notarization checks:

```sh
spctl --assess --type open --context context:primary-signature -vv PiNative-<version>.dmg
codesign --verify --deep --strict --verbose=2 /Applications/PiNative.app
```

Pass criteria:

- DMG contains `PiNative.app` and Applications target with polished Finder presentation.
- Volume name identifies PiNative and version.
- Launch does not require disabling Gatekeeper or stripping quarantine.
- Signing/notarization checks pass.
- Release workflow artifacts and notes match the release being validated.

---

# Required final summary

After running any subset of this plan, report exactly what was covered.

```md
## Manual PiNative Verification

Commit: <hash>
Mode: real pi --mode rpc / mock / release artifact
Date: <date>

| Scenario | Result | Evidence |
|---|---|---|
| Launch/readiness | Pass/Fail/Skipped | /tmp/pinative-smoke-01.png |
| Basic send loop | Pass/Fail/Skipped | /tmp/pinative-smoke-02.png |

Prompts/files used:
- ...

Notes:
- Selected row/header/transcript/composer mismatches: none / describe
- PiNative or Pi errors: none / describe
- Deferred scenarios: ...
```

## Minimum recommended subsets

For a chat/runtime branch:

- Scenarios 1–12.

For a composer/attachment branch:

- Scenarios 1–3 and 13–14.

For a shell-layout branch:

- Scenarios 1–8.

For a Promote to Project branch:

- Scenarios 1–3 and 6, plus 15–16 for the deeper Promote pass.

For a release branch:

- Scenario 17, plus a quick real-Pi launch/send check from Scenarios 1–2 after install.
