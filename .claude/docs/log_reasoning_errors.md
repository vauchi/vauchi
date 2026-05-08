<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Reasoning Errors, Wrong Implementations, Tool Misuse — Session Log

Lightweight, append-only log of moments when reasoning, an
implementation, or a tool usage was found to be wrong. Read by future
sessions to avoid repeating the same dead ends — saves tokens by
short-circuiting analysis when a known pitfall is recognized.

## How this differs from `claude-errors-and-misjudgments.md`

| | `log_reasoning_errors.md` (this file) | `claude-errors-and-misjudgments.md` |
|---|---|---|
| Granularity | Quick, one-off entries | Distilled patterns (E##) |
| When to add | Anytime an error is caught | When a pattern recurs |
| Format | Lightweight prose | Structured (root cause → prevention → test guard) |
| Lifecycle | Append; promote after 3+ similar entries | Permanent reference |

## When to append an entry

- **Self-caught**: realized mid-task that a hypothesis or step was wrong
- **User-corrected**: user pointed out a misuse, wrong API, wrong tool
- **Discovery**: while reviewing past work, found a stale claim or buggy fix
- **Tool misuse**: invoked a tool with wrong args / wrong tool for job

If the same kind of entry appears 3+ times → promote to a numbered
entry in `claude-errors-and-misjudgments.md` and reference it from a
rule in `.claude/rules/`.

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
