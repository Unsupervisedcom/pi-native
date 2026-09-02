# Data & Persistence

## App-local model

- `Project` contains a stable app-local ID, folder path, sessions, and current Git totals.
- `Session` contains sidebar metadata, optional Pi session path, pending first prompt, pin/archive flags, and cached `[TranscriptItem]`.
- `ConversationKey(projectID, sessionID)` is the stable routing key for runtime state and callbacks.
- These types and their persistence logic live together in [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1).

## Two persistence layers

- **Pi owns canonical sessions:** JSONL files under `~/.pi/agent/sessions/--<encoded-project-path>--/`.
- **PiNative owns UI continuity:** project bookmarks, selected project, pane settings, promotion settings, standalone chats, per-project session metadata, and cached transcripts in `UserDefaults`.
- At startup, project sessions are merged by Pi session `filePath`: disk supplies current name/date/count; PiNative supplies stable local ID, pin/archive state, and cached transcript.
- New sessions begin app-local with a `pendingInitialPrompt`; after `new_session`, Pi's resolved `sessionFile` is written back through a keyed callback.

## Why cache transcripts?

- The center pane can render immediately while Pi starts or hydrates.
- A transient process/session error does not erase visible history.
- Drafts and transcripts remain isolated because each chat keeps its own runtime model.
- Transient startup failure notices are filtered before persistence.

## Lifecycle safeguards

- Session-generation tokens reject stale async hydration results.
- Process-generation tokens reject events from replaced clients.
- Runtime callbacks capture `ConversationKey`, never ambient selection.
- Archiving preserves session files and cache; runtime cleanup only removes the live process/model.
