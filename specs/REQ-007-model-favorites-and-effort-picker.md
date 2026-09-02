# REQ-007: Model Favorites and Effort Picker

## Overview

PiNative's model list can become very large when a broad provider such as OpenRouter is configured. Users need a durable favorites list so the composer model menu remains small and intentional, while Settings remains the place to search and curate the full catalog.

This spec states observable product behavior. It does not prescribe the storage mechanism, view-model names, or whether the model catalog is hydrated by an existing conversation runtime or a dedicated Pi RPC process.

## Terms

- **Available model:** a model returned by Pi's available-model catalog for the current Pi configuration.
- **Favorite:** a provider/model pair the user has selected for inclusion in the composer model menu.
- **Model identity:** the pair of Pi provider ID and model ID. Display names are not durable identity.
- **Current conversation:** the conversation whose composer contains the control being used.
- **Unavailable favorite:** a persisted favorite whose provider/model pair is absent from Pi's current available-model catalog.

## Requirements

### REQ-007.1: Models settings section

1. Settings MUST include a Models section.
2. The Models section MUST show the models available from Pi.
3. The Models section MUST show a favorite control for each listed available model.
4. The Models section MUST provide a way to remove an existing favorite.
5. The Models section MUST show whether each listed model is currently a favorite.
6. The Models section MUST show a loading state while the available-model catalog is loading.
7. The Models section MUST show an empty state when Pi returns no available models.
8. The Models section MUST show an error state when the available-model catalog cannot be loaded.
9. The Models section MUST display favorite models in a dedicated Favorites section.
10. The Favorites section MUST appear above the remaining available models.
11. A favorite model MUST NOT also appear in the remaining available-model list.

### REQ-007.2: Model search

1. The Models section MUST provide model search.
2. Search MUST match a case-insensitive substring of a model's provider ID, model ID, or display name.
3. Searching MUST preserve each displayed model's favorite state.
4. Clearing search MUST restore the unfiltered model list.

### REQ-007.3: Favorite persistence and seeding

1. Model favorites MUST persist across app relaunches.
2. When PiNative starts with no saved favorites value or with a saved empty favorites list, it MUST seed favorites with Pi's configured default provider and model.
3. Seeding the initial favorite MUST NOT require the user to open the Models settings section.
4. A duplicate favorite MUST NOT appear more than once in the favorites list.
5. An unavailable favorite MUST remain visible in the Models section with an unavailable indicator.
6. An unavailable favorite MUST NOT be selectable from the composer model menu.
7. PiNative MUST prevent removal of the only remaining favorite.

### REQ-007.4: Composer model menu

1. The composer model menu MUST show only available favorite models.
2. The composer model menu MUST NOT show non-favorite models when favorites exist.
3. The composer model menu MUST include a Select Favorites action below its model choices.
4. Choosing Select Favorites MUST open Settings to the Models section.
5. Choosing an available favorite model MUST switch the current conversation to that model.
6. Choosing a model in one conversation MUST leave the selected model in every other conversation unchanged.
7. The composer MUST reject prompt submission while the current conversation has no selected model.

### REQ-007.5: Separate effort menu

1. The composer MUST present model selection and effort selection as separate menus.
2. The effort menu MUST show the effort levels that Pi reports for the current conversation.
3. Choosing an effort level MUST switch the current conversation to that effort level.
4. Choosing an effort level in one conversation MUST leave the selected effort level in every other conversation unchanged.
5. The effort menu MUST show an unavailable state when Pi does not report effort levels for the current conversation.

## Manual acceptance criteria

- The Models settings section should feel like a native macOS settings pane, with aligned rows, readable provider metadata, and deliberate favorite affordances.
- Search should remain responsive with a large OpenRouter catalog.
- Favorite rows should be visually distinct without making unfavorited rows feel disabled.
- The composer model menu should remain compact even when Pi exposes hundreds of models.
- Select Favorites should be visually separated from model choices so it is not mistaken for a model.
- Model and effort controls should have distinct labels and predictable keyboard/accessibility behavior.
- Model and effort changes should preserve the running-state and per-conversation isolation guarantees from `REQ-003`.

## Implementation notes

- Persist favorites using provider and model ID, not display name alone.
- Treat Pi's configured default provider and model as the initial favorite only when no saved favorites value exists.
- Refresh the full catalog for Settings without making every visible conversation runtime fetch the same large catalog unnecessarily.
- Keep runtime-local model and effort state consistent with the parallel-runtime architecture.
- Use a deterministic ordering for favorites and search results.

## Non-goals

- This spec does not require editing Pi provider authentication from PiNative.
- This spec does not require custom provider or custom model management.
- This spec does not require per-project model defaults.
- This spec does not require drag-to-reorder favorites.
- This spec does not require syncing PiNative favorites back into Pi's global configuration.
