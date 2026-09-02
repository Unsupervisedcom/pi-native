# Agent Instructions — pinative

## Product north star

PiNative's purpose is to be a **highly polished, detail-obsessed, beautiful native
macOS GUI for Pi**. Not a prototype-grade wrapper, not "good enough" — a GUI that feels
as considered and refined as best-in-class native Mac apps (see `research/plans/` for the
current reference bar being used for UI parity work).

This is the tie-breaker for UI/UX decisions. When a choice is between "faster to
build, visibly less polished" and "more work, matches native Mac craft," default to
the latter unless there's a concrete reason (deadline, unresolved product direction,
throwaway prototype code) to take the shortcut — and if you do take the shortcut, say
so explicitly and note it as a known gap rather than letting it pass as final.

Concretely, this means:

- Prefer custom-drawn, hand-tuned interactions (dividers, hover states, collapse
  animations, focus rings) over stock component defaults when the stock default is
  visibly rougher than the reference bar we're aiming for.
- Motion, spacing, and color should be deliberate, not incidental. If something looks
  "close enough," it isn't done.
- Reuse SwiftUI/AppKit semantic colors and existing centralized theme tokens (`AppTheme`,
  `ShellPalette`, and related palettes) instead of embedding raw color values in feature
  views. When no existing token expresses the intended role, extend the centralized
  theme first, then reference that semantic token from the view.
- UI automation should verify that elements appear and user-visible behaviors work, not
  assert exact colors, pixel values, opacities, or other visual styling. Evaluate visual
  polish through direct visual inspection instead of brittle UI-test thresholds.
- Functional correctness (RPC wiring, process lifecycle, session handling) matters as
  much as visuals — polish includes reliability and responsiveness, not just pixels.
- It's fine to stub functionality behind a clearly-labeled placeholder while shell
  polish is being built out, as long as the placeholder itself is visually considered
  rather than a bare "TODO" label.

Re-read this before making structural UI decisions (layout mechanisms, component
libraries, interaction patterns), and reference it explicitly in plan docs under
`research/plans/` when it changes the recommended approach.

## Scope discipline

- Keep changes strictly within the user-requested scope.
- For test-only refactors, modify only tests and required build/project metadata.
- Do not update docs, specs, changelogs, generated reports, or UI unless explicitly
  requested or necessary to complete the requested behavior or build.
- Report unrelated stale references and reviewer findings; do not fix them
  automatically.
- Do not use Playwright for non-UI changes.
- Visual verification applies only when the requested change directly affects rendered
  UI; incidental or out-of-scope findings do not trigger visual work.

## Running/debugging workflow

- After making app code changes, always build and run the latest app so the user can immediately inspect the result.
- During implementation, run focused unit/integration/process tests first through `scripts/test-unit.sh`; this script uses the `PiNativeUnitTests` scheme and excludes `PiNativeUITests`. Do not invoke the full `PiNative` test scheme, `scripts/test-ui.sh`, or any PiNative XCUITests/UI automation while iterating on code, specs, 2119 judgments, or review fixes.
- PiNative unit/integration test commands should use `scripts/test-unit.sh`, which enforces a 60-second overall suite timeout plus a 30-second per-test timeout and streams each test start/pass/fail plus a slowest-first summary. No suite invocation should run longer than 60 seconds and no individual unit test should take longer than 30 seconds. If a unit test times out or hangs, stop that run, identify the suspect test from the script output/log, investigate and fix the hang, then rerun the focused test without waiting for user intervention. The outer command timeout should remain 60 seconds unless the user explicitly authorizes a longer run.
- Never run UI automation or any test that controls the user's app/desktop without the user's explicit confirmation immediately before the run. When confirmed, run it only at the final pre-push stage and only after focused/unit/integration tests pass, the app has been built and launched, and the user has completed any required manual UI/live-Pi verification. For pre-push agent automation, use `scripts/test-ui-related.sh` so the UI test bundle compiles and only UI tests related to changed app files execute; do not run the full `scripts/test-ui.sh` or full deterministic UI suite unless the user explicitly asks. The user may run the full UI suite manually outside the agent workflow.
- If the app was launched from Xcode and Xcode is paused on `SIGTERM` / `mach_msg2_trap` / `NSViewBridgeErrorCanceled`, normal `open` or `pkill` may keep hitting the stale suspended debug process. First stop the run from Xcode (`⌘.`) or quit Xcode if it is wedged; then relaunch the fresh DerivedData build. If verifying from the agent while Xcode is wedged, identify the fresh direct-run window by `CGWindowNumber` rather than assuming the first PiNative window is current.

## Real Pi integration verification

- Mock-only tests are not sufficient evidence for behavior that depends on Pi RPC events, real session state, subprocess lifecycle, authentication, persistence, or provider behavior.
- For those paths, add an integration test using a real Pi session whenever it can be run safely and repeatably; never describe mocked coverage as proof that the real workflow works.
- The agent must still perform every feasible automated and live verification itself first. If the available test path does not exercise a real Pi session, explicitly disclose that gap and prompt the user to perform a specific manual real-Pi workflow before the feature is considered verified or is merged/pushed.

## Repo layout conventions

- `docs/` — durable documentation: how the app currently works (architecture,
  standing decisions, feature reference). Should stay accurate as the app evolves.
- Root `TODO.md` — legacy backlog; do not add or update tasks there.
- Track requested work only in the active session's task list. Update a durable plan, spec, issue, or other project record only when the user explicitly asks.

## Naming discipline

If a plan or note references a third-party app used as a design/UX reference, do not
name that app anywhere in this repo or in any git commit (message or diff) — this repo
will be open-sourced later and commit history is not something we can cleanly scrub
afterward. Use a neutral description ("the reference app") in anything tracked by
git. Keep any named screenshots/recordings used for research untracked and outside the
repo (e.g. under `/tmp`), never added to git. See `research/plans/native-shell-parity-milestone.md`
for the current example of this in practice.

## Licensing

This project is MIT-licensed (see `LICENSE`, copyright Unsupervised, Inc.). Bundled
third-party assets (e.g. Maple Font) keep their own licenses — see
`docs/THIRD_PARTY_LICENSES.md` before assuming an asset can be relicensed as MIT.

<!-- 2119:begin -->
## Requirements workflow (2119)

This repository enforces spec-driven testing with [2119](https://www.rfc-editor.org/rfc/rfc2119).
When a fix exists on GitHub before it is published to npm, run the GitHub checkout directly because the GitHub package is not currently npx-runnable:
`tmp=$(mktemp -d); git clone --depth 1 https://github.com/Unsupervisedcom/2119.git "$tmp/2119" && (cd "$tmp/2119" && npm install --silent && npm run build --silent) && node "$tmp/2119/dist/cli.js" <command>; rc=$?; rm -rf "$tmp"; exit $rc`.

**When planning a feature**, write or update a spec in `specs/` first. Every
requirement is a numbered item under a `### REQ-NNN.M` heading with exactly one
RFC 2119 keyword, stating an observable outcome — not an implementation
mechanism. Every requirement must map to a plausible user action, product lifecycle, or runtime failure that can actually occur; do not specify and test every theoretically possible state merely because it can be imagined. Scope requirements in proportion to likelihood and impact, and leave unreachable, purely hypothetical, or negligible-risk edge cases out unless concrete product behavior makes them relevant. For small UX/product features, keep the requirement set deliberately coarse: prefer a handful of broad, observable requirements that match user-visible behavior over many narrowly sliced micro-requirements. Split a requirement only when the obligations are independently high-risk, independently observable, or require materially different test evidence; do not create separate requirements just because implementation has separate steps. Run `npx rfc2119 lint` after editing specs, or the GitHub checkout command above with `lint` when npm is behind. **Before writing tests
against a new spec**, dispatch a fresh-context reviewer to critique the draft
requirements themselves: outcome-stated, individually testable, appropriately coarse, and one obligation
each. A flawed requirement steers the whole implementation wrong.

**When implementing**, every MUST/SHALL requirement needs at least one test
annotated with a comment containing its ID, e.g. `// 2119: REQ-001.2.3` (the
marker line must start with a comment leader). Write tests that would genuinely
fail if the requirement were violated — including its negative space: what the
requirement forbids needs a rejection test, not just what it allows. A
fresh-context reviewer judges each test's honesty; tautological or over-mocked
tests will be rejected.

**Reviewer diversity**: use reviewer models from different providers, routinely
or as periodic `npx rfc2119 review --audit` sweeps — adversarial audits of
passing verdicts. Audit especially the challenging or high-consequence
requirements; a single model family shares blind spots.

After implementing a feature or fix, run its focused relevant tests to verify the changed behavior. Do not run the full `rfc2119 check` suite merely to finish an individual task.

Pure file moves and test-file refactors that preserve test bodies and requirement
markers do not require fresh judgment reviews. If a path-only refactor makes verdicts
stale, report that fact; do not dispatch reviews or broaden the task without user
approval. Keep requirement-driven tests split into focused files by behavior or
integration boundary; avoid shared feature test files that carry annotations for an
entire feature unless the tests are genuinely inseparable.

**Immediately before pushing changes**, run `npx rfc2119 check`, or the GitHub checkout command above with `check` when npm is behind. It must exit 0 before the push. Also run the check when the user explicitly requests it or when requirement semantics or test behavior change. If it
reports pending judgment reviews, run `npx rfc2119 review --dispatch`, or the GitHub checkout command above with `review --dispatch`, and
dispatch each instruction file in `.2119/reviews/` to a fresh-context subagent
(never review your own work in the same context). CI runs the same check, so
treat it as a required pre-push gate rather than running it after every task or local change.
<!-- 2119:end -->
