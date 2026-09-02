# Overview

## The one-sentence architecture

PiNative is a native SwiftUI/AppKit shell that owns projects, navigation, presentation, and cached UI state while a separate `pi --mode rpc` subprocess owns agent execution, providers, tools, and canonical Pi session files.

```text
SwiftUI shell → AppModel → one PiConversationModel per chat
                              ↓
                         PiRPCClient actor
                              ↓ JSONL over stdin/stdout
                         pi --mode rpc
```

## Start with these five files

- [PiNativeApp.swift](http://127.0.0.1:43117/open?path=PiNative/PiNativeApp.swift&line=1) — process entry point, window scene, app commands, and shutdown.
- [MainWindowView.swift](http://127.0.0.1:43117/open?path=PiNative/MainWindowView.swift&line=1) — three-region shell and modal routing.
- [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1) — app-level source of truth and runtime registry.
- [PiConversationModel.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationModel.swift&line=1) — one chat's lifecycle, transcript, composer, and Pi event interpretation.
- [PiRPCClient.swift](http://127.0.0.1:43117/open?path=PiNative/PiRPCClient.swift&line=1) — subprocess and JSON-RPC transport boundary.

## Ownership rule

- `AppModel` answers **which project/chat/surface is active?**
- `PiConversationModel` answers **what is happening in this chat?**
- `PiRPCClient` answers **how do commands and events cross the process boundary?**
- Views render observable state and keep only ephemeral presentation state locally.
