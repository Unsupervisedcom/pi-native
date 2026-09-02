# REQ-004: Shell Chrome Layout

## Overview

PiNative's shell chrome must keep sidebars, titlebar controls, and center chat content stable during collapse, expand, and resize operations. The shell should own horizontal region layout consistently so the chat header, transcript, and sidebars do not compensate for each other with hardcoded offsets.

This spec intentionally keeps automated coverage narrow for this visual shell refactor. Most detailed layout polish should be verified during implementation with visual checks. Automated coverage should focus on one regression test that toggles both sidebars and confirms center content remains visible and usable.

## Requirements

### REQ-004.1: Sidebar toggle regression coverage

1. Toggling the left sidebar and right sidebar MUST keep the center chat content visible and usable without hiding it behind collapsed sidebar regions.

## Manual acceptance criteria

- The app shell should lay out the left sidebar, center content, and right sidebar as sibling regions owned by a single shell container.
- Left and right sidebar collapse should use the same implementation pattern and feel visually symmetric.
- The titlebar toolbar controls should remain anchored to the macOS traffic-light row independently of sidebar visibility and center content state.
- The left-sidebar controls and right-sidebar collapse control should appear on the same titlebar line as shell-level toolbar controls.
- Changing sidebar visibility should only change which toolbar controls are shown or enabled, not the toolbar's vertical alignment or titlebar anchoring.
- The chat header and chat transcript/composer should be laid out as one vertical center stack.
- The chat header should share the same center-region horizontal bounds as the transcript/composer area.
- Collapsing or expanding sidebars should preserve the chat stack's centered alignment within the remaining center region.
- Sidebar collapse and expand animations should preserve visible content continuity without exposing blank, clipped, or stale interactive regions.
- The shell layout should remain predictable at narrow window widths without auto-collapsing sidebars unexpectedly.

## Implementation notes

- A shared side-pane wrapper is the preferred way to achieve symmetric sidebar behavior.
- The titlebar controls may use one full-width titlebar accessory or coordinated left/right titlebar accessories as long as the visible toolbar row behaves as one shell-level system.
- The automated test should exercise both left and right sidebar toggles in one flow and assert that a representative center chat element remains visible/clickable after each toggle.
- The chat stack should use a fixed centered max-width content column.
- The right pane's mode title/back controls should remain inside the right pane body.
- The right toolbar icon should disappear when the right pane is hidden rather than acting as a persistent open affordance.
- When the left sidebar is hidden, New Chat should remain available in the titlebar toolbar.
- Narrow windows should not auto-collapse sidebars; sidebar visibility should remain user-controlled.
- Detailed pixel alignment, animation quality, and toolbar polish should be verified manually during implementation rather than encoded as brittle automated tests.

## Non-goals

- This spec does not require changing sidebar row content, project selection behavior, or Promote to Project behavior.
- This spec does not require a specific light-mode palette.
- This spec does not require replacing right-pane mode content.
- This spec does not require detailed automated tests for each visual alignment rule.
