# Feature Workflows

## Attachments

- [AttachmentSupport.swift](http://127.0.0.1:43117/open?path=PiNative/AttachmentSupport.swift&line=1) accepts picker, pasteboard, and drag/drop input.
- Supported images are decoded and sent as base64 RPC image content; formats Pi cannot send directly are normalized to PNG.
- Other readable regular files remain path references—contents are not silently inlined.
- Attachment-only prompts receive useful fallback text, and missing/folder inputs produce visible errors.

## Promote to Project

- [PromoteToProject.swift](http://127.0.0.1:43117/open?path=PiNative/PromoteToProject.swift&line=1) splits filesystem policy (`PromoteToProjectService`), progress state (`PromoteToProjectWorkflowModel`), and modal UI.
- Project name is slugged under the configured project folder; normalized and symlink-resolved paths must remain inside that root.
- Non-empty folders are reused only when their `.pinative/promote-to-project.json` marker matches project, destination, and source session.
- Writes are create-if-missing, making retries non-destructive.
- Output can include `README.md`, project plan/log, `AGENTS.md`, `promoted-chat.md`, and optional `git init`.
- On success, [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1) registers/reuses the project, starts a context-rich project chat, archives the source Quick Chat, and cleans its runtime.

## Pinning and archiving

- Pin/archive flags are PiNative metadata; the underlying Pi session file is retained.
- Pinned chats are promoted to a global sidebar section.
- Archived chats disappear from normal lists and can be restored from the right pane.
- Working or queued chats cannot be archived until stopped/completed.
