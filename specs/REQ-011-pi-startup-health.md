# REQ-011: Pi Startup Health

## Overview

PiNative must locate the user’s supported Pi installation, verify that it can start a minimal RPC session, and make a failed or attention-blocked startup immediately recoverable without requiring a chat to fail first.

## Requirements

### REQ-011.1: Pi discovery

1. When one Pi-dependent feature can use the resolved Pi installation, every Pi-dependent feature MUST be able to use that installation.
2. When Pi is installed through an npm-compatible global installation path configured by the user’s login shell, PiNative MUST resolve and use that installation rather than relying only on Finder’s inherited PATH.
3. When Pi was installed by the official installer and the login shell does not resolve it, PiNative MUST resolve and use the installer’s Pi executable.
4. When Pi is installed in an NVM Node version directory, PiNative MUST successfully start Pi using that NVM-managed Node version.

### REQ-011.2: Startup diagnosis

1. When PiNative launches, it MUST run a bounded, non-destructive Pi RPC health check.
2. When the health check cannot resolve or launch Pi, exits before responding, times out, reports an RPC failure, or requests interactive attention, PiNative MUST expose a global recovery state that describes the problem.
3. When the health check successfully receives an RPC state response without an interactive-attention request, PiNative MUST clear any global Pi recovery state.
4. When any live Pi conversation requests interactive attention after startup, PiNative MUST expose the same global recovery state while preserving that conversation’s chat-local explanation.

### REQ-011.3: Recovery

1. When a global Pi recovery state is active, PiNative MUST show a prominent bottom-of-window status bar with the problem description followed by a `Resolve in Terminal` action.
2. When the user invokes `Resolve in Terminal`, PiNative MUST open Terminal using the same resolved Pi invocation, or invoke `pi` from the user’s login shell when no invocation is resolved.
3. After the user successfully invokes `Resolve in Terminal` for a global Pi recovery state and then returns to PiNative, PiNative MUST run a new health check and update the status bar from that result.
4. When PiNative becomes active without a successful `Resolve in Terminal` invocation for the current global Pi recovery state, PiNative MUST leave that recovery state visible.

## Manual acceptance criteria

- With a working Pi installation made available by NVM, pnpm, Yarn, Bun, a custom npm prefix, or the official installer, launch PiNative and confirm the chat and model workflows start successfully.
- With no resolvable Pi executable, confirm the status bar remains visible on a new chat and on a non-chat destination, and it does not overlap the composer or panes.
- Select `Resolve in Terminal`, complete any Pi setup or authentication, return to PiNative, and confirm the next active-scene health check removes the status bar.
- Inspect the recovery state in light and dark appearances for a polished, prominent presentation.

## Non-goals

- Health checking does not submit a model prompt or prove that a provider can complete a billable turn.
- PiNative does not install, upgrade, or modify Pi automatically.
