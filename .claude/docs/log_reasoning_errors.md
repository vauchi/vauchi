<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Reasoning Errors, Wrong Implementations, Tool Misuse — Session Log

Lightweight, append-only log of moments when reasoning, an
implementation, or a tool usage was found to be wrong. Read by future
sessions to avoid repeating the same dead ends — saves tokens by
short-circuiting analysis when a known pitfall is recognized.

## When to append an entry

- **Self-caught**: realized mid-task that a hypothesis or step was wrong
- **User-corrected**: user pointed out a misuse, wrong API, wrong tool
- **Discovery**: while reviewing past work, found a stale claim or buggy fix
- **Tool misuse**: invoked a tool with wrong args / wrong tool for job

If the same kind of entry appears 3+ times → promote a one-liner to
the **Common waste patterns** section of `CLAUDE.md` and reference
it from a rule in `.claude/rules/`. (The previous two-tier model
via `claude-errors-and-misjudgments.md` was retired 2026-05-08:
the E## file sat empty below E30 for weeks while real promotions
went straight from this log to CLAUDE.md.)

## Format

```markdown
### YYYY-MM-DD — short summary
- **What**: what I did or claimed
- **Trigger**: how it was caught (self / user / CI / review)
- **Root cause**: 1 line — why I was wrong
- **Lesson**: behavioral change going forward
- **Recurrence**: 1 (or N if cumulative)
```

Keep entries terse — they exist to be skimmed quickly across sessions.
If an entry needs more than ~6 lines, it probably belongs in a problem
record or design doc.

## Pruning

- Entries older than 6 months that never recurred → delete (noise)
- Entries promoted to E## → delete here, add a one-line back-reference
  to the E## entry

---

*New entries below this line. Newest first.*

### 2026-06-07 — Used `git diff A...B` to judge "is this branch merged"

- **What**: For 4 "gone" branches (remote deleted) flagged by
  `branch-health` as unmerged/RECOVER, I ran `git diff origin/main...<branch>
  --stat`, saw a non-empty net diff, and told the user they had unmerged
  commits. User said "check again." `git cherry origin/main <branch>` showed
  every commit marked `-` (patch-id already in main) — all 4 were
  squash-merged, hence safe to delete.
- **Trigger**: User correction ("check again if it is really unmerged").
- **Root cause**: `git diff A...B` = `diff $(merge-base A B) B` — it shows
  everything B added since the fork point and does NOT subtract what A
  independently merged. So squash-merged branches (different SHA, same
  content) still show a non-empty 3-dot diff. Wrong tool for the question.
- **Lesson**: To decide "is this branch's work in main", use
  `git cherry origin/main <branch>` (patch-id: `-` = in main, `+` =
  unmerged) or grep main for a distinctive symbol — never the 3-dot diff.
  Note `branch-health`'s "gone/unmerged" is reachability-based and
  false-positives on every squash-merge.
- **Recurrence**: 1

### 2026-05-08 — Token audit started at file-layer when cost lived in behavior

- **What**: User asked "how to reduce tokens?" I opened with file-level
  measurements (CLAUDE.md, `.claude/rules/`, MEMORY.md) and presented
  ~880 tokens of session-start savings as the result. User pushed
  back: "this is marginal no?" Reframing pulled the actual data —
  hook telemetry showed ~2 M wasted tokens / 22 days dominated by
  excessive re-read. The whole first pass was nibbling at the
  smaller rock.
- **Trigger**: User correction after the marginal result was presented.
- **Root cause**: Optimized at the layer that was easy to count (file
  bytes) rather than the layer where cost accumulates (per-call
  tool outputs × sessions × time). Did not sample empirical waste
  before starting.
- **Lesson**: For any token-cost audit, the FIRST step is to sample
  where the tokens go. The hook telemetry at
  `_private/docs/reference/error-ledger.jsonl` already has the
  category counts. The CLAUDE.md "Common waste patterns" section
  now codifies this as "Wrong-layer audit"; this entry is the
  worked example behind it.
- **Recurrence**: 1

### 2026-04-20 — Used GNU-only `grep --exclude=` in alpine-CI shell script

- **What**: After fixing the `check-claude-md` orphan-detector, I used
  `grep --exclude="$name"` to prevent a file from matching itself. Works
  locally (GNU grep). In CI the job runs in `alpine:3.21`, whose default
  `grep` is BusyBox — `--exclude` is unrecognized, the recursive search
  silently short-circuited, and *all 18 docs* were reported orphan on
  pipeline 2464648339.
- **Trigger**: User escalation ("fix this!!!!") after the pipeline went
  red again with a worse failure than the original.
- **Root cause**: Did not apply `portable-shell.md` rules before writing
  a shell script that runs on alpine. Verified the fix only against the
  host's GNU grep.
- **Lesson**: For any shell script that runs in `alpine:*` CI images,
  test inside the same image (`docker run --rm -v "$PWD":/work -w /work
  alpine:3.21 sh -c '...'`) before pushing. `portable-shell.md` lists
  the GNU-vs-BSD gotchas but BusyBox is a third dialect — when the CI
  image is alpine, trust only options listed in `grep --help` on that
  image (or switch to a portable two-step: `grep -rl` + `grep -v`).
- **Recurrence**: 1

### 2026-04-20 — Fixed justfile recipe, forgot the CI had its own inlined copy

- **What**: `lint:claude-md` CI job failed on MR 360 flagging
  `just-commands-reference.md` as orphan. Fixed the `check-claude-md`
  recipe in `justfile` (include `.claude/docs/` as search root), pushed,
  expected CI to pass. CI didn't even re-run because my change didn't
  touch the paths in the job's `rules: changes:` filter — and the CI
  script is a copy-paste of the recipe inlined directly in
  `.gitlab-ci.yml`, not a `just check-claude-md` call.
- **Trigger**: Self-caught by reading `.gitlab-ci.yml` after the new
  push failed to produce a pipeline.
- **Root cause**: Assumed the CI invoked the just recipe. Didn't grep
  `.gitlab-ci.yml` for the failure message before "fixing" the recipe.
- **Lesson**: When a CI job fails, first `grep` the failing string in
  `.gitlab-ci.yml` — inline scripts are a common pattern here. Before
  claiming a CI fix is done, verify the job's `rules: changes:` filter
  will actually trigger on the committed paths.
- **Recurrence**: 1

### 2026-04-20 — Auto-link regex matched its own marker inside commit bodies

- **What**: Wrote a regex to strip a previous auto-generated "## Related
  MRs (auto-linked)" section from MR descriptions before re-writing it.
  The regex matched the FIRST occurrence — but the literal text
  "## Related MRs (auto-linked)" also appeared in the commit body of
  the very feature that introduced the marker. Result: the description
  was silently truncated mid-sentence after the first match.
- **Trigger**: Self-caught while inspecting the resulting MR description.
- **Root cause**: Section markers chosen from natural prose — easy to
  collide with documentation about the marker itself.
- **Lesson**: Use machine-only markers (HTML comments) for any region a
  script needs to find/replace inside human-edited content. Treat
  prose-shaped markers as user-visible labels only.
- **Recurrence**: 1

### 2026-04-27 — "Local verification" of CI script meant `--help`/`--list`, not the real flag combo

- **What**: Fixed `mutation:nightly` failure by moving `--jobs $(nproc)`
  from a GitLab variable into `before_script` (so bash would actually
  evaluate `$(nproc)`). Claimed local verification by running
  `cargo mutants --jobs '$(nproc)' --help`, `cargo mutants --list
  --in-place --exclude-re theme.rs`, and a stubbed-shell simulation.
  Pushed to `core!673`, which merged. The next scheduled pipeline
  failed in ~10s with `error: the argument '--in-place' cannot be
  used with '--jobs <JOBS>'` — cargo-mutants 26.x rejects that
  combination, and we need `--in-place` to keep
  `include_bytes!("../../../themes/...")` resolving.
- **Trigger**: User pointed it out: "this means you have not tested
  the script locally before push."
- **Root cause**: `--help` and `--list` only exercise argument parsing.
  Many tools (cargo-mutants among them) defer flag-conflict checks
  until the action actually runs, so flag-incompatibility doesn't
  surface in either probe. The shell-substitution simulation also
  passed because it never invoked the real binary.
- **Lesson**: For a CI fix, run the real command with the same flag
  set the CI job will use, for at least one real iteration. Ctrl-C
  after the parse/startup phase is fine — flag-conflict errors
  surface in seconds. Captured as auto-memory
  `feedback_local_verification_real_flags.md` and as a soft hook at
  `.claude/hooks/check-ci-yaml-tested.sh` (blocks `git push` of CI
  yaml unless the command line carries `CLAUDE_CI_TESTED=...`).
- **Recurrence**: 1

### 2026-05-04 — Trilogy MRs already landed via different SHAs; opened MR for ghost work

- **What**: At session-init the bootstrap reported three feature
  branches (relay/feat/version-changed-at-env-override,
  e2e/docs/f11-smoke-ignore-update-f13,
  _private/problem/ohttp-gateway-decap-unsupported-2026-05-04)
  each "1 commit ahead of origin/main." Treated them as a
  trilogy of open work needing MRs. **After `git fetch` two of
  the three were already merged**: relay's commit became the
  HEAD of relay/main (same SHA), and `_private`'s F13 record had
  been committed directly to main with a different SHA but
  identical content. The "ahead/behind" snapshot at the start
  of the session was already stale by the time I read it.
- **Trigger**: Self-caught after running `git fetch origin` for
  the pre-MR rebase, when ahead/behind flipped from `0 1 / 0 1`
  to `0 0 / 3 1` for those two repos.
- **Root cause**: The session-init bootstrap caches branch
  state at session start. It can be 30+ minutes stale by the
  time I read it. Auto-merge / direct-to-main pushes flip the
  state under us with no warning.
- **Lesson**: Before assuming a "1 commit ahead" branch is
  unmerged work, run `git -C <repo> fetch origin` AND
  `git -C <repo> cherry origin/main <branch>`. The former
  refreshes ahead/behind; the latter detects squash-merged or
  duplicate-SHA content (`-` markers = content already on main,
  even with different SHA). `git rev-list --left-right --count
  origin/main...HEAD` alone misses the squash-merge case.
- **Recurrence**: 1

### 2026-05-04 — Deleted local branch with unmerged MR-bound commit

- **What**: After opening _private!1132, ran a batched cleanup
  that deleted the local `tidy/work-board-2026-05-04-housekeeping`
  branch alongside other already-merged branches. The MR was
  still OPEN — the commit was on origin (pushed) but not yet on
  origin/main, so deleting the local branch lost it from local
  history. Recovered via `git fetch origin <branch> && git
  switch -c <branch> origin/<branch>` (origin still had it).
- **Trigger**: Self-caught when `git pull --ff-only origin main`
  said "Already up to date" — meaning the commit hadn't reached
  main yet, contradicting the assumption that it was safe to
  delete.
- **Root cause**: Conflated "MR opened (commit pushed)" with "MR
  merged (commit on main)." Sequence-of-events conflation —
  branches are safe to delete only after their MR lands and
  origin/main advances past their tip.
- **Lesson**: Before `git branch -D <feature>`, verify ONE of:
  (a) MR state via `glab mr view <num>` shows `merged`, OR
  (b) `git cherry origin/main <feature>` returns ALL `-`
  markers (no `+`). The cleanup audit's `branch-health` output
  is a snapshot from `glab mr list` and lags merge events; do
  not trust its `RECOVER`/`DELETE` recommendations without a
  per-branch verify when an MR was opened in the same session.
- **Recurrence**: 1

### 2026-05-04 — Killed mid-flight SSH push, created hung process

- **What**: First `git push` invocation went into background and
  appeared to hang. Killed the SSH child process (`kill 3253080`)
  and retried. The kill orphaned the remote receive-pack
  transaction — gitlab held the connection waiting, which made
  subsequent retries also stall on SSH negotiation. Eventually
  resolved by `pkill -9 -f "ssh.*gitlab.com"` and re-running
  with verbose logging, which revealed the pre-push hook was
  running 137 e2e tests (~7min). The push itself wasn't hung —
  the hook was.
- **Trigger**: Self-caught after the third stall when ps
  showed the SSH child holding zero CPU.
- **Root cause**: Conflated "command not producing output" with
  "command stuck." Long-running pre-push hooks (just check,
  test, fmt, clippy) produce no output until they finish. The
  pipe `2>&1 | tail -30` buffers everything until the head
  exits, so even progress lines didn't appear.
- **Lesson**: Before killing a `git push`, redirect to a file
  with `>/tmp/push.log 2>&1` and `tail -f /tmp/push.log` to see
  real-time progress. Use `SKIP_TESTS=1 git push` for
  docs/tidy MRs where the test suite isn't relevant. Look at
  `scripts/hooks/pre-push` for available bypass envs
  (`SKIP_TESTS`, `_SKIP_FMT`, `_SKIP_CLIPPY_TEST`,
  `ALLOW_MERGED_BRANCH`) before killing the process.
- **Recurrence**: 1

### 2026-05-08 — Path-override lockfile churn leaked into a release-bump commit

- **What**: After bumping core 0.49.0 → 0.50.0 in `core/Cargo.toml`,
  ran `just setup-path-overrides` to compile-test a downstream
  consumer (`linux-gtk`). When staging the bump commit, `git -C
  core diff Cargo.lock` showed the path-override-induced lockfile
  churn alongside the real version bump (10 lines vs. the expected
  4 `[[package]] vauchi-*` entries). Caught by reading the diff
  before staging — `just clean-path-overrides` reverted the noise.
- **Trigger**: Self-caught when the Cargo.lock diff was larger than
  expected.
- **Root cause**: Conflated "verify the change works on a downstream
  repo" with "no side effects on the upstream repo's working tree."
  `setup-path-overrides` rewrites consumer `Cargo.toml` /
  `Cargo.lock` AND can perturb the upstream `Cargo.lock` via patch
  resolution.
- **Lesson**: When bumping versions and validating downstream
  consumers in the same flow, order matters: (a) bump core's
  `Cargo.toml` + `Cargo.lock`, commit, THEN (b) `just
  setup-path-overrides` to validate consumers, THEN (c) `just
  clean-path-overrides` before any further core commit. Or commit
  the bump immediately, then validate separately.
- **Recurrence**: 1

### 2026-05-08 — Inflated survey count drove a wrong volume argument

- **What**: Reasoned over an Explore-agent survey claiming "1037
  `get_string()` call sites in core" while scoping a CI gate
  (problem record `2026-05-08-locale-key-coverage-ci-wiring`).
  Used the number as the load-bearing justification for adding the
  gate. Empirical count: **62** total — `vauchi-app` 48,
  `vauchi-cabi` 4, `vauchi-platform` 10. Off by ~16×.
- **Trigger**: Self-caught at the investigation phase when running
  `bash locales/scripts/check-locale-key-coverage.sh` against
  `core/vauchi-app/src/` returned only 47 candidates / 8 unique
  literal keys, not the 1000+ implied by the survey.
- **Root cause**: Treated an agent's bullet-pointed summary number
  as ground truth without running the 30-second `rg -c
  'get_string\b' core/vauchi-app/src --type rust` that would have
  produced the real number. The summary phrasing
  ("1037 get_string() calls used 1037 times across core") looked
  too specific to be wrong.
- **Lesson**: Survey-style numbers from agent reports get the same
  treatment as plan-doc claims under `verify-before-acting.md`:
  if a number is going to load-bear a recommendation, run the
  smallest concrete count yourself before building on it. Counts
  are especially prone to drift between "calls" / "call sites" /
  "unique keys" / "matches in any file" — confirm what the
  number actually represents.
- **Recurrence**: 1

### 2026-05-08 — Recommended wiring a script based on its header, not its behavior

- **What**: While planning the same `locale-key-coverage` gate,
  recommended wiring `locales/scripts/check-locale-key-coverage.sh`
  into CI based on the script's header comment ("Catches missing
  keys BEFORE merge — not at runtime fallback"). The script's
  load-bearing line is:

  ```bash
  if echo "$EN_KEYS" | grep -qFx "$key"; then echo "$key"; fi
  ```

  which **filters out** any candidate not in `en.json`. A
  misspelled key (e.g. `"contact.add_btn_x"` rather than
  `"contact.add_button"`) is dropped from the candidate set
  precisely because it doesn't match `en.json` — the inverse of
  the stated intent. Wiring the script as-is would have shipped
  zero typo detection while looking like a working gate.
- **Trigger**: Self-caught at the investigation phase, while
  reading the script line-by-line to write a CI job spec.
- **Root cause**: Conflated "the script claims to do X" with "the
  script does X". Header comments age more easily than code; a
  three-year-old comment can describe an intent that a later
  refactor inverted.
- **Lesson**: Before wiring an unfamiliar script into CI, read
  the body, not just the header. Run it against a sentinel known
  to fail (a deliberate typo in source → expected ERROR) and
  confirm the script catches it. If it doesn't, the script is
  broken regardless of the header. Same root cause as
  `verify-before-acting.md`: trust the smallest concrete check
  over the docs.
- **Recurrence**: 1

### 2026-05-08 — Inlined a CI fix per-repo instead of fixing the shared template

- **What**: Hit a stale-clone failure mode in `lint:locale-key-
  coverage` across linux-gtk → ios → android tighten MRs and
  shipped three near-identical inline `before_script` rewrites
  (always-fetch+reset on `../locales`) before discovering the
  shared template `scripts/ci-templates/content-fetch.yml`
  carried the same anti-pattern in `.clone-locales` /
  `.clone-themes`. The template's `pull --ff-only 2>/dev/null
  || true` silently fails on shallow clones and `2>/dev/null`
  hides it. core/.gitlab-ci.yml extends the template (15+
  references) and inherits the bug; linux-gtk / ios / android
  inline because their CI configs don't include
  `content-fetch.yml`. Fixing only the inlines left core
  exposed; fixing only the template left the inlines untouched.
  The right move is both, in two commits — but the *order*
  matters: fix the template first so future inlines start from
  a working baseline, then fix the leaves. I fixed leaves
  first because the leaves were what was failing in CI, then
  noticed the template afterwards.
- **Trigger**: Self-caught after the third inline copy, when
  the user asked "what is next? think intuitively and counter-
  intuitively" — the question forced an audit pass that found
  the shared template.
- **Root cause**: Reactive debugging (fix what's failing now)
  can blind you to where the failure pattern *originates*. Each
  individual leaf fix looks correct in isolation; the template
  is upstream of every leaf and was the actual root.
- **Lesson**: When the same fix appears in 2+ places in one
  session, stop and search for a shared upstream before doing
  the third. `just grep "<the-anti-pattern>"` is a 10-second
  check that prevents 3× the diff and keeps the fix DRY at the
  source. Counter-intuitively, the third copy of "the same
  fix" is a stronger signal than the second — the second can
  be coincidence; the third is a pattern.
- **Cross-ref**: `verify-before-acting.md` ("when a recipe
  fails, debug the recipe; don't bypass it"). Same shape
  one-level-up: when a CI pattern fails, debug the template;
  don't bypass it with inlines.
- **Recurrence**: 1

### 2026-05-08 — Conflated `git pull --ff-only` semantics on shallow clones

- **What**: Initial mental model: `git pull --ff-only` on a
  shallow `--depth=1` clone fails noisily with "fast-forward
  not possible" so the wrapping `2>/dev/null || true` swallows
  a single specific error. Actual behaviour observed: shallow
  pull-ff-only can succeed-as-no-op (returning exit 0) when the
  remote tip has new commits past the shallow boundary, leaving
  HEAD on the cached SHA. The `|| true` then never fires, and
  the job runs against a stale tree without any signal — there
  is no failure to retry on, no warning to grep for, no
  alarming exit code.
- **Trigger**: Investigated after `linux-gtk!120` retried twice
  with the same 19-key failure even though `locales/main` had
  shipped the keys hours earlier.
- **Root cause**: Used a heuristic mental model ("ff-only
  always errors when divergent") instead of running the actual
  command against a shallow repo. The behaviour is more
  permissive than the heuristic suggests; shallow refs let pull
  decide it has nothing to fast-forward and exit 0.
- **Lesson**: For git operations on shallow / cached state,
  mental models drift fast — verify with a small reproduction
  (`git clone --depth=1 ...; git pull --ff-only; git log -1`)
  before relying on error-propagation as a contract. The fix
  pattern that *is* contract-stable across shallow / cached /
  divergent / corrupted state is `fetch + reset --hard
  origin/main`: explicit destination state regardless of
  starting state.
- **Recurrence**: 1

### 2026-05-08 — Resumed an "in progress" claim without checking `git status` was clean against origin

- **What**: `session-init` reported the work board's only "In
  Progress" item was the Windows humble-UI retirement, claimed
  by `@claude-2026-05-08`, and the README still showed `[ ]
  Phase 5`. I read those, made a plan ("extract inline lint to
  sibling script"), wrote the script + CI rewire, pushed two
  branches, opened `vauchi/scripts!343` (ready) and
  `vauchi/windows!86` (Draft), and updated the README — all
  before noticing that `git -C _private status` had said
  "behind 3" the whole time. The 3 unfetched commits were:
  (1) the same-day prior session shipping Phase 5 inline
  via `windows!85`, (2) the close-out commit explicitly
  rejecting the sibling-script form with the rationale
  "5-line one-liner with no external policy state... a fixed
  one-shot find is sufficient", and (3) the graduation to
  `done/`. I duplicated work that had been deliberately
  decided against, then had to close both MRs and delete four
  branches.
- **Trigger**: Self-caught when `git -C _private pull` during
  the work-board update raised a merge conflict against the
  graduated `done/` README path that didn't exist locally.
- **Root cause**: `session-init` *fetches* but does not *pull*
  the `_private` repo, and the dashboard's "LOCAL BRANCHES"
  section only flags non-`main` checkouts — neither surface
  flagged "_private/main is 3 commits behind origin/main".
  The claim on the work board was authored by my prior
  session that very morning; the prior session had also
  closed it out and graduated it. Reading the local README
  showed the pre-close-out state and was wrong; the truthful
  source was `git log origin/main` for the same path.
- **Lesson**: When picking up a same-session claim from the
  work board, the very first move must be `git -C <repo> log
  origin/main -- <record-path>` (or `git -C _private status`
  to spot "behind N") *before* reading the local README.
  The work board entry being marked "In Progress" with a
  same-day claim is a strong signal the record may have
  graduated since the local clone last pulled. Trust
  `git log origin/main` over the local working-tree README,
  always — the rule is in `verify-before-acting.md` ("Before
  implementing a fix from a problem record: grep the actual
  source...") but the tier-1 trigger should be earlier:
  *before reading the record itself*, confirm the local copy
  matches origin.
- **Cross-ref**: `verify-before-acting.md` (problem records
  vs code drift); `self-healing.md` (stale-record handling);
  `multi-repo-awareness.md` ("Branch inspection: ALWAYS check
  all repos" — same shape, different verb).
- **Recurrence**: 1

### 2026-05-16 — Investigated a failing MR without checking for already-prepared revert MRs

- **What**: User asked "fix vauchi/linux-gtk!125" (a Draft MR
  whose test:a11y job had failed). I read the failing-pipeline
  trace, set up a `/tmp/linux-gtk-mr125` worktree, built both
  debug and release binaries (~3 minutes of cargo work), ran the AT-SPI
  suite locally (passed), then retried the CI job (passed —
  apparent flake). Only AFTER all of that did I check the
  user's other open MRs and find `vauchi/linux-gtk!126`
  (revert) and `vauchi/private!1272` (defer docs), both
  authored by the same user, both pipeline-green, both
  explicitly stating the !125 approach was unsafe ("Synchronous
  re-emit triggered a mid-`clicked` sidebar rebuild — Button
  widget destroyed underneath the click signal"). The real
  task was simply to merge the prepared revert + defer, not
  to chase a CI flake.
- **Trigger**: Self-caught when the user sent the second URL
  `vauchi/private!1272` mid-investigation. That URL led to the
  revert MR via the auto-link block.
- **Root cause**: When asked to "fix !N", default reflex was
  to debug the failure rather than first check whether the
  user (or anyone) had already opened a superseding /
  reverting MR for the same problem record. `glab mr list -A`
  scoped to the same author + same touch-area is a 1-second
  query; running it before any build/test work would have
  surfaced the revert immediately.
- **Lesson**: "Fix MR !N" — before any code inspection or
  local repro, check for sibling MRs:
  `glab -R <repo> mr list -A` and grep for the same record
  slug or branch shape. If a `revert:` MR exists from the
  same author, the fix is almost certainly "merge the revert"
  not "debug the original". Same shape applies cross-repo:
  scan `glab -R vauchi/private mr list` for a paired docs MR
  (e.g. problem-record status flip) — the auto-link block at
  the bottom of MR descriptions is the durable connector.
- **Cross-ref**: `verify-before-acting.md` ("Before
  implementing a fix from a problem record: grep the actual
  source"); CLAUDE.md "Subagent budget" (the local build +
  Rust toolchain ran for ~3 min before I read the user's own
  narrative).
- **Recurrence**: 1

### 2026-05-18 — Started a slice already in flight in a parallel session; commit dropped on rebase

- **What**: The user said "another session is auditing slice
  32h". I picked slice 32f as independent work, executed the
  whole file deletion + tests + commit + doc heal end-to-end.
  Then `just git sync` reported `core: pulled main`. The
  parallel session had ALSO shipped slice 32f as
  `93c0f5a9 refactor: retire entire mobile_onboarding.rs (slice 32f)`
  during the same window. My commit `b9c2961a` got rebase-
  dropped as a no-op patch ("patch contents already
  upstream"). The deletion was correct; the duplication of
  work was ~30 minutes of churn.
- **Trigger**: Self-caught when the sync output said `pulled
  main` and the `core` log no longer contained `b9c2961a`.
- **Root cause**: I checked for in-flight work by reading
  the user's narrative ("auditing 32h") and assumed the
  parallel session was on 32h only. But "auditing" is a
  superposition: it can pivot to *any* of the remaining
  slices once the audit finishes. The signal I missed:
  `git ls-remote origin "feature/slice-32*"` would have
  shown the parallel session's branch shape before I picked
  a slice that might collide.
- **Lesson**: Before starting any slice 32X work when a
  parallel session is "auditing" or "investigating" the
  same category of work, query `git -C <repo> ls-remote
  origin "feature/slice-32*"` (and the `_private` mirror)
  to enumerate every in-flight branch. If a matching slice
  branch exists OR if the parallel session might pivot to
  the slice I want, switch to a different slice or to a
  non-slice task (record heals, plan-doc heals, readiness
  audits). The audit's promise was "might pivot to 32l
  partial" — that was the explicit warning that the
  parallel session's scope was fluid.
- **Cross-ref**: 2026-05-04 "Trilogy MRs already landed via
  different SHAs" (same shape — concurrent commits to
  same record converge via patch-equivalence detection).
  This entry adds: the convergence is BENIGN (no data loss,
  git rebase --empty=drop handles it) but the wasted cycles
  are not. The fix is upstream of the collision — pre-flight
  branch-shape query — not downstream cleanup.
- **Recurrence**: 1 (collision recurrence; bootstrap-staleness
  pattern from 2026-05-04 is a sibling, not the same)

### 2026-05-21 — Bulk-sweep regex matched function parameters as struct field assignments

During Phase 2 of wire-identifier-newtypes I wrote a regex
`^(\s+)(sender_id|recipient_id):\s+(.+?),\s*$` to wrap
struct-field expressions with `.into()` so a `String` literal
becomes a `ContactId`. The pattern matched any source line that
looked like a `field: expr,` — including the function-parameter
lines `sender_id: &str,` inside `from_transport(...)` and
`build_shred_senders(...)` in `vauchi-platform/src/lib.rs`. The
sweep produced `sender_id: &str.into(),`, which is a syntax
error — caught immediately by the next `just build`, reverted via
a targeted second pass. ~2 minutes lost.

- **Lesson**: A "field: expr," shape is ambiguous between
  struct literal context and function-parameter context. Any
  sweep that wraps the RHS must guard against the parameter
  case — either by requiring the RHS to look like an *expression*
  (no bare `&str` / `Vec<...>` type-shaped patterns), or by
  inspecting the enclosing block (look back for `(` not `{`).
  The cheapest check: skip the line if the RHS starts with `&`
  or is a single ident that matches a known type name (`&str`,
  `String`, `u32`, ...).
- **Cross-ref**: 2026-05-08 "Recommended wiring a script based
  on its header, not its behavior" — same shape (acting on a
  textual pattern without verifying the structural context).
- **Recurrence**: 1

### 2026-05-25 — Consumer audit checked UniFFI surfaces only, missed the C-ABI/C# binding surface

Slice 32l T3.1 said "delete the dead legacy initiator surface,
0 frontend callers per T0.2". T0.2 enumerated consumers via
`just consumers` (snake_case) + a manual Swift/Kotlin camelCase
pass. I deleted the app-layer `device_link_session.rs`
(`DeviceLinkSession` + `run_initiator_cycle`) on that basis — and
`just check core` failed: `vauchi-cabi`'s `device_link_session.rs`
(`vauchi_device_link_session_*` C ABI) wraps it, and windows
`DeviceLinkBridge.cs` is a live consumer (8 `[LibraryImport]`
calls). The app-layer initiator was **not** dead; only the *mobile
UniFFI* parallel was. Restored the app-layer file, narrowed the
PR to the verified-dead mobile surface (T3.1a), re-scoped the
C-ABI/windows retirement as T3.1b.

- **Lesson**: This repo has **three** binding surfaces, not two:
  UniFFI snake_case (`just consumers`), UniFFI camelCase
  (Swift/Kotlin — the known blindspot), and the **C-ABI / C#**
  surface (`vauchi-cabi` → windows/linux-qt, `[LibraryImport]`
  P/Invoke). A "0 callers" claim that only covers UniFFI is
  unproven for any symbol `vauchi-cabi` re-exports. Before
  deleting an app-layer (`vauchi-app`) type, grep
  `vauchi-cabi/src` for it AND grep windows/linux-qt for the
  `vauchi_*` C entrypoint — not just the mobile bindings.
- **Cheapest guard**: a wide `grep -rn <symbol>` across the whole
  workspace (incl. `vauchi-cabi`, `windows`, `linux-qt`) costs one
  call; the build failure + restore cost ~15 K tokens. Verify the
  plan's "0 callers" premise with the build, which is exactly what
  caught it — running `just check` before the commit was the save.
- **Cross-ref**: feedback `grep_target_symbol_before_designing`
  (plan checkboxes lie) + `verify-before-acting` rule.
- **Recurrence**: 1

### 2026-05-25 — Asserted a failure *mechanism* from a partial trace

- **What**: For the contact-tap "→ My Card" bug I found a real core gap
  (`route_result` had no general `OpenContact → ContactDetail` arm) and
  immediately wrote a confident root-cause narrative — "the mobile mapping
  is broken, so the raw result navigates to My Card" — into the problem
  record AND the RED/GREEN commit messages.
- **Why wrong**: closer reading refuted it. The frontends *do* map
  `OpenContact → ContactDetail` (`CoreAppViewModel.kt:482`,
  `AppViewModel.swift:392`), and `navigate_to_json` is strict serde that
  parses `{"ContactDetail":{...}}` (→ ContactDetail) or errors (→ stays on
  Contacts) — **neither path yields My Card**. The located gap was real, but
  not shown to be the cause of the symptom. I had the symptom and a
  plausible gap and welded them into a mechanism without tracing the full
  path through the consuming frontend code + the parser.
- **Lesson**: locating a code gap ≠ explaining an observed symptom. Before
  writing a *mechanism* into records/commits, trace the full path
  end-to-end (emitter → router → wire → consumer → parser), especially when
  you cannot reproduce (device unavailable). State "found gap X; symptom
  cause unverified," not "X causes the symptom." The fix can be correct
  (core *should* resolve nav) without the mechanism claim being true.
- **Cross-ref**: same family as "Header-comment-as-spec" / "acting on a
  textual pattern without verifying structural context"; also CC-21.
- **Recurrence**: 1

### 2026-06-06 — Graduated records to `done/` and broke inbound links a checker layer couldn't see

- **What**: In MR !1589 I `git mv`-ed 7 problem records into
  `problems/done/`, fixed the inbound links my per-slug greps surfaced,
  and pushed green locally. CI `lint:links` then failed on two inbound
  links in files the branch never touched
  (`investigations/2026-06-01-ddd-precept-audit.md`,
  `planning/done/2026-05-23-track-b-push-to-zero-plan.md`).
- **Why wrong**: two compounding mistakes. (1) My discovery grep carried
  a `grep -v "/problems/<slug>/"` filter intended to drop the record's
  own dir, but it also dropped every *inbound* link whose target path
  contains `problems/<slug>/` — i.e. exactly the links I was hunting.
  (2) The two local guards have overlapping blind spots: pre-push lychee
  scans changed files only, and `audit-graduation-links.sh` checks peer
  records under `problems/` only — neither sees an inbound link from an
  unchanged `investigations/`/`planning/` file. Both passed; CI's
  full-tree scan caught it.
- **Lesson**: for record graduations, the per-slug grep is a discovery
  aid, not a gate. The gate is the full-tree scan CI runs:
  `cd _private && lychee --offline docs/**/*.md docs/*.md`. Run it before
  pushing. Never put a `-v "/problems/<slug>/"` filter on an inbound-link
  grep. (Memory `git_mv_inbound_links` updated with the lychee command.)
- **Cross-ref**: direct recurrence of the `git mv` inbound-link pattern
  (`_private` MR !1261, 2026-05-15, which needed 3 fix commits); same
  "trusted a filtered/narrow check over the full-surface check" family as
  the 2026-05-25 C-ABI consumer-audit blindspot.
- **Recurrence**: 2 (this pattern: inbound-link breakage on `git mv`)

### 2026-06-07 — `just commit-repo` silently dropped new files (uses `git add -u`)

- **What**: Committed a new `Tag` type via `just commit-repo core "..."`.
  The recipe reported "4 files changed, 3 insertions" — actually only the
  tracked `mod.rs`/`main.rs` edits landed; the two *new* files
  (`contact/tag.rs`, `tag_tests.rs`) were never staged. Pushed a broken
  commit: `pub mod tag;` with no `tag.rs`.
- **Why wrong**: `commit-repo` stages with `git add -u` (tracked-modified
  only). It even prints a "NOTE: Untracked files (not staged…)" line that
  I didn't read. Earlier in the same session I *did* `git add` new files
  explicitly for `_private` (ADR, problem record) — so this was an
  inconsistency, not ignorance.
- **Lesson**: for any commit introducing NEW files, `git -C <repo> add
  <files>` first, THEN `just commit-repo`. Always sanity-check the
  recipe's "N files changed" against how many files you actually touched
  before pushing — the mismatch is the tell. Fix here: `git add` +
  `--amend` + `--force-with-lease` (feature branch).
- **Recurrence**: 1

### 2026-06-09 — grep false-negative (unescaped paren) → wrong "Android is clean"

- **What**: While scoping the VauchiPlatform→PlatformAppEngine collapse
  (G1), I ran `for m in "\.sync(" ...; grep -rEl "$m" android/...`. The
  ERE pattern `\.sync(` has an unmatched `(` (group-open), so it matched
  nothing → I concluded "Android calls 0 of the legacy sync/identity
  methods → iOS-only collapse" and wrote that into the problem record.
  Android in fact calls `platform().sync()` (`VauchiRepository.kt:250`).
- **Why wrong**: trusted a single grep's empty result as proof of absence
  without (a) escaping the regex metachar or (b) a second method (literal
  `grep -F` or reading the file). `verify-before-acting` explicitly says a
  "not found" is not proof of absence — I violated it for a load-bearing
  scoping claim that then shaped a problem record.
- **Lesson**: when a grep result drives a scope/architecture claim, use
  `grep -F` (fixed-string) or escape metachars, and confirm with a second
  method before writing it down. Empty results from a hand-built regex are
  the tell — paren/dot/brace in the pattern means re-check. Caught when
  `just consumers VauchiPlatform` later listed the Android handle.
- **Recurrence**: 1

### 2026-06-10 — glab 404 (wrong project slug) misread as "no MR exists" → duplicate MR

- **What**: Verifying whether the _private BLE-checklist branch already had
  an MR, I ran `glab mr list -R vauchi/_private …` and `glab mr view 1666
  -R vauchi/_private`. The project slug is `vauchi/private` (no leading
  underscore), so both returned **404 Not Found**. I read the 404 as "no MR
  exists / 1666 never existed" and created a duplicate MR (!1667) for a
  commit that !1666 had already merged the day before.
- **Why wrong**: a tool error (404 from a wrong identifier) is not the same
  as an authoritative "absent" result — same class as the grep-false-negative
  above, but the tell is an *error string*, not an empty list. `glab` prints
  `ERROR / 404 Not Found` rather than an empty table; I should have treated
  the 404 as "my query is malformed," not "the thing is gone." The remote
  branch still carrying the name + a stale local origin/main ref ("1 ahead")
  both pointed at already-merged work, which a correct slug would have shown.
- **Lesson**: when a CLI lookup returns an error/404 (not an empty success),
  fix the query before drawing a conclusion. For GitLab the canonical slug
  is `vauchi/<repo>` with **no** underscore even though the dir is `_private`
  → project is `vauchi/private`. Confirm "no MR" with the printed MR URL or
  `glab api projects/vauchi%2F<repo>/merge_requests?source_branch=…` before
  creating one. Caught by the user asking me to check what I'd pushed.
- **Recurrence**: 1

### 2026-06-10 — `state=merged` + no merge commit misread as "broken merge"

- **What**: Three test MRs (ios `!525`, macos `!284`, android `!514`) showed
  `state=merged` while `origin/main` still sat at each MR's `base_sha` and the
  merged files were absent. I concluded the merges were "broken / rolled back"
  and warned it was a systemic merge-train failure that would also drop the
  five open MRs. The user corrected me: they were *still merging*. Minutes
  later `origin/main` fast-forwarded to each branch tip (`28a3580` / `3f856b1`
  / `38ba9384`) and every file was present.
- **Why wrong**: a fast-forward merge has **no merge commit** — `merge_commit_sha`
  and `squash_commit_sha` are both `None` by design, and during a merge train
  `main` advances only when the train reaches that MR. So "merged + null merge
  commit + main not advanced yet" is the *normal* transient signature of an
  in-flight FF merge, not a rollback. `merge_error: None` was the tell I
  ignored. I also over-escalated to "systemic, will hit the other MRs."
- **Lesson**: don't diagnose a merge as broken from a single snapshot. If an
  MR is `merged` but main hasn't moved, account for (a) FF merges having no
  merge commit and (b) merge-train latency — re-fetch after a short wait
  before concluding. `merge_error: None` + `detailed_merge_status: not_open`
  means GitLab thinks it's fine; trust that over the absent merge commit.
  Don't raise a systemic alarm from one in-progress data point.
- **Recurrence**: 1

### 2026-06-11 — frontmatter `status:` counted as problem-record status

- **What**: While auditing `_private/`, I grepped `^status:` across all
  `problems/**/*.md` and reported "26 distinct statuses, zero `intake`,
  the canonical lifecycle is fiction" — and logged that as a ranked
  finding. The matches were document frontmatter (investigation.md,
  plan.md: `status: draft|complete|approved`), not record statuses.
  Records keep status in a README table row (`| **Status** | intake |`)
  and follow the canonical lifecycle almost perfectly (44+ intake).
- **Why wrong**: one grep pattern, one source of truth assumed. I
  verified the *count* but not the *provenance* of the matches — never
  looked at which files they came from before drawing the conclusion.
- **Lesson**: before claiming a convention is violated, sample WHERE the
  matches live (`grep -l` first, read one hit). A status field exists at
  two layers here (record vs document); any audit grep must pin the
  layer. Caught self during implementation; correction committed in the
  investigation doc (preserved, not rewritten).
- **Recurrence**: 1
