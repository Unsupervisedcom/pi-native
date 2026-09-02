# PiNative Code Architecture Walkthrough

This is the maintenance entry point for the Markdown-backed architecture presentation:

- Rendered presentation: [`code-architecture-walkthrough.html`](code-architecture-walkthrough.html)
- Slide sources: [`code-architecture-walkthrough/`](code-architecture-walkthrough/)

The presentation is intentionally organized as a small set of high-level tabs rather than one long architecture document. Each slide should remain concise enough to walk through with a new developer while sharing a screen.

## Instructions for an agent refreshing the walkthrough

1. Read `AGENTS.md` and inspect the current working tree before changing the walkthrough.
2. Trace current behavior from source rather than trusting older architecture notes. At minimum, inspect app startup, `AppModel`, shell views, the conversation model, RPC client, attachments, promotion, side panes, tests, specs, CI, and release scripts.
3. Update the short Markdown slides under `docs/code-architecture-walkthrough/`. Preserve the high-level progression: Overview, Features, App Navigation, Data & Persistence, Chat Architecture, Chat Message Lifecycle, Transcript & Composer, Feature Workflows, Supporting Surfaces, Quality & Delivery, and Change Map.
4. Keep statements current and distinguish shipped behavior, deliberately limited behavior, dormant code, and planned work.
5. Every source-file reference should use the local walkthrough server's validated Xcode endpoint with a repo-relative path:

   ```text
   http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1
   ```

   Xcode registers an `xcode:` scheme, but current Xcode rejects `xcode://open?url=file:…` local-file URLs. The walkthrough server invokes `/usr/bin/xed` instead.
6. Render the slides with Pi's global `html_report` tool:

   ```text
   output: docs/code-architecture-walkthrough.html
   title: PiNative Code Architecture Walkthrough
   dir: docs/code-architecture-walkthrough
   open: true
   ```

7. Preserve/reapply the presentation-specific sidebar treatment in the generated HTML: large **PiNative** masthead, **Code Architecture** subheader, title-case slide names, with later sections grouped under Core Architecture/Product Workflows/Engineering, and active-section highlighting. The generic report renderer otherwise exposes numeric Markdown filenames.
8. Start the local viewer and open the report:

   ```sh
   node scripts/serve-code-architecture-walkthrough.mjs
   ```

9. Inspect the rendered HTML in a browser, verify the left navigation and representative source links open the expected files in Xcode, then run relevant documentation/build checks. Update `docs/README.md` and the date below if the structure changes.

Last source review: **2026-08-05**
