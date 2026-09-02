# REQ-002: Promote to Project

## Overview

Promote to Project turns a projectless chat into a durable local PiNative project folder, using project-creation defaults from Settings, registering the folder as a project, and routing the user into a new chat in that project after success.

This spec intentionally follows manageable 2119 granularity: the enforced requirements focus on core user workflows and safety invariants, while detailed UI polish, exact step ordering, and implementation mechanics live in manual acceptance criteria and notes.

For these requirements, the normalized project-name slug is the lowercased project name with each maximal sequence of characters outside `a`–`z` and `0`–`9` replaced by one hyphen and leading or trailing hyphens removed. A filesystem tree is unchanged when no descendant entry is created, removed, moved, or renamed and each descendant's type, file contents, and POSIX permissions remain identical. This definition is exhaustive; ownership, timestamps, flags, ACLs, and extended attributes are outside this requirement's scope.

## Requirements

### REQ-002.1: Core promotion workflow

1. A user MUST be able to promote a projectless chat by choosing only a project name in the promotion modal, running the promotion, and landing in a new chat scoped to the promoted project.
2. The workflow MUST create or reuse the destination directory at the Settings default code folder joined with the normalized project-name slug.
3. The workflow MUST reject unsafe destinations, including destinations that resolve outside the chosen code folder, destinations that already exist as files, and non-empty folders whose Promote to Project marker is absent or does not match the promoted destination and source session.
4. When no persisted PiNative default exists, Settings MUST default the project-folder path to `~/Projects` and ensure that folder exists.
5. The workflow MUST leave the Settings default code folder's filesystem tree outside the resolved destination directory unchanged.

### REQ-002.2: Generated project context

1. When project-memory or agent-instructions options are enabled in Settings, the workflow MUST create the corresponding human-readable project context artifacts without overwriting existing files.
2. The workflow MUST always preserve useful source-chat provenance, including session identity, promotion time, transcript availability, and available cached transcript text.

### REQ-002.3: Progress, errors, and retry

1. The modal MUST communicate promotion progress, success, and failure states clearly enough for a user to know what is pending, running, completed, skipped, or failed. [manual]
2. The modal MUST disable promotion inputs while filesystem or project-registration work is running. [manual]
3. After a partial failure, retrying the workflow MUST NOT overwrite existing generated artifacts, duplicate project-log/provenance entries, or register the promoted project more than once.

### REQ-002.4: PiNative handoff

1. Successful promotion MUST add or reuse the destination folder as a PiNative project and display a new chat scoped to that project that starts from the promoted planning context.
2. The source projectless chat MUST be archived after successful promotion while retaining its session file and transcript for later recovery.
3. If promotion fails before a promoted project appears in the sidebar, the modal MUST remain open with an error and without an `Open Project` button.

## Manual acceptance criteria

- The modal should show a derived destination preview that updates as the project name changes.
- The modal should not expose project-creation options other than project name.
- Before promotion starts, the remaining project-creation options should remain editable from Settings.
- As each enabled item completes, its row should change from a spinner to a checkmark.
- Skipped items should be visually distinct from completed items.
- Failed items should show an error icon and concise actionable message.
- After success, the modal should automatically route to a new chat in the promoted project.
- Automatic handoff should dismiss the modal and archive the source Quick Chat without requiring an extra click.

## Implementation notes

- Suggested destination slugging: trim whitespace, lowercase, replace each run of non-ASCII-alphanumeric characters with `-`, and remove leading/trailing `-` characters.
- Suggested promotion marker path: `.pinative/promote-to-project.json`.
- Suggested generated artifacts: `README.md`, `AGENTS.md`, `docs/project-plan.md`, `docs/project-log.md`, and `promoted-chat.md`.
- Existing generated artifact paths should be reported as skipped rather than overwritten.
- Git initialization should be best-effort and skipped when disabled or when the destination is already inside an existing git work tree.
- Tests should cover representative safe and unsafe destination cases rather than every possible filesystem edge case.

## Non-goals

- This spec does not require exhaustive automated coverage of every path normalization edge case.
- This spec does not require per-promotion overrides for the default code folder or context options.
- This spec does not require migrating the source chat session file into the promoted project.
- This spec does not require promotion behavior for chats that already belong to an existing project.
