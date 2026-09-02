# REQ-012: Pending Changes Summary

## Overview

PiNative provides a compact Pending Changes surface for checking a project's Git
working-tree state without leaving the app. It is a status summary: users can
see which project it describes, its changed paths and aggregate counts, and
whether the project is clean or Git could not be read.

## Requirements

### REQ-012.1: Project-targeted opening

1. Opening Pending Changes from a project-specific control MUST display the Git status summary for that project.
2. Opening Pending Changes from a project chat's context-menu action MUST NOT change the selected conversation.

### REQ-012.2: Status summary and outcomes

1. For a project with pending Git work, Pending Changes MUST show available branch context, each changed or untracked path with its Git status, and aggregate file, addition, and deletion counts that include staged, unstaged, and untracked work.
2. Pending Changes MUST show distinct no-project, initial-loading, clean-working-tree, and Git-failure states instead of presenting any of those states as a populated status summary.
3. When the targeted project changes, Pending Changes MUST NOT present a previously loaded project's status summary as the current project's summary while the new result is loading.

### REQ-012.3: Refresh

1. Activating Refresh MUST replace the displayed status result with a newly read result for the same project.

## Non-goals

- Hunk, file-content, or patch review.
- Staging, unstaging, applying, reverting, approving, or rejecting changes.
- Continuous filesystem watching.
- A net `HEAD`-to-working-tree total that deduplicates files represented in both staged and unstaged status.
- Exact visual styling, layout, animation, or iconography.
