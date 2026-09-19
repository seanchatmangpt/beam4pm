# Cleanup and Merge Plan: beam4pm

## Current State (as observed 2026-09-17)

| Path | Type | Git status summary | Last commit | Size |
|---|---|---|---|---|
| `/Users/sac/beam4pm` | Canonical repo (candidate) | 10 modified/typechanged, 9 untracked; branch `main` @ `ace23e5`, 1 commit ahead of `origin/main`, not pushed | `ace23e5` 2026-09-14 "Add HDDL solve coverage for ferroplan facades/wrapper, bump ferroplan submodule, add Hex package metadata" | 6.7G |
| `/Users/sac/beam4pm_ws2` | Independent repo (own `.git`, not a worktree of the above) | 268 deleted, 1 modified, 1 modified-submodule (270 total); branch `feat/pro-ocpm-simulation-tenancy` @ `626f85e5`, exactly in sync with `origin/feat/pro-ocpm-simulation-tenancy` (0 ahead/0 behind) | `626f85e5` 2026-08-31 "docs: add docs/README.md index linking all four Diataxis quadrants" | 233M |
| `/Users/sac/tmp_beam4pm_work/beam4pm` | Independent repo (own `.git`) | Clean, 0 changes | `8f011d3` 2026-08-30 "feat(ws3-rev): manufacture recovery evidence" — branch `ws3rev`, exactly in sync with `origin/automation/ws3-rev-20260830-1623-fortune5-runtime-value` | 21M (whole `tmp_beam4pm_work/`) |
| `/Users/sac/.scratch-beam4pm-docker-test` | Backup/scratch copy — no `.git` directory at all | N/A (not a git repo) | N/A | 2.9G |

Notes on evidence gathered:
- `git worktree list` run inside `/Users/sac/beam4pm` returns only `/Users/sac/beam4pm ace23e5 [main]` — no registered git worktrees of the canonical repo exist anywhere (no `.claude/worktrees`, no sibling `-worktrees`/`-wt` dirs under `/Users/sac`). This family is four independent filesystem copies, not a worktree tree.
- `beam4pm` has 7 remote-tracked feature branches plus `main`, all fetched from `origin` (`https://github.com/seanchatmangpt/beam4pm.git`), and is the only copy with unpushed local work.
- `beam4pm_ws2`'s three local branches were checked individually via real `git branch -r --contains` / ahead-behind counts: `feat/pro-ocpm-simulation-tenancy` (checked out) is identical to its origin tracking branch (0 ahead/0 behind); `main` is identical to `origin/main` (at the older `489fe2b`); `ws2work` (11 commits ahead of `main`, no upstream) has its tip commit reachable from `origin/feat/ws2-close-productization-loops-20260831` — so no committed history in `beam4pm_ws2` is unique. The only unique content is its 270-file uncommitted working-tree diff.
- `tmp_beam4pm_work/beam4pm` is fully clean and its checked-out branch tip is identical to an already-pushed `origin/automation/...` branch.
- `.scratch-beam4pm-docker-test` has no `.git`, so no commit/branch comparison is possible by git; it is a plain snapshot (Dockerfile/.dockerignore layout suggests a container-build test scratch, matching the pattern of the "gemma" scratch copy already deleted manually).
- Divergence check via real `git merge-base --is-ancestor`: `626f85e5` (ws2 HEAD) is NOT an ancestor of beam4pm-canonical's `main`/`origin/main` — the two repos' `main` lines have diverged since ws2 was cloned; beam4pm-canonical's `main` contains a v26.9.12 integration-merge train (`293d26f`, `8d648b5`, `c34e275`, etc.) absent from ws2's log.

## What "merged" should look like

`/Users/sac/beam4pm` is canonical going forward: it is the only copy with unpushed local commits, has by far the richest branch set (7 feature branches + main vs. 2-3 elsewhere), its `main` is the most historically advanced (contains the v26.9.12 integration-merge train neither other repo has), and it is the most recently and actively touched copy (dirty in-progress work, last touched 2026-09-17 vs. Aug 30-31 for the others).

For every other path:

- **`/Users/sac/beam4pm_ws2`** — independent clone, not a worktree. All three branch tips are either identical to an origin branch or (for `ws2work`) reachable from a different already-pushed origin branch — no commit here is unique or at risk. It does have 270 uncommitted working-tree changes (268 deletions under `docs/reference/types/`, plus edits to `ggen.lock` and the `vendor/ggen-marketplace` submodule pointer) found nowhere else. MANUAL REVIEW REQUIRED: a human must decide whether that mass deletion was intentional cleanup worth preserving or an accidental/stray checkout state before this directory can be deleted — no automated cherry-pick applies since no unique commits exist, only an unresolved working-tree diff.
- **`/Users/sac/tmp_beam4pm_work/beam4pm`** — independent clone, clean working tree, HEAD already fully present on an origin branch. Nothing to merge or cherry-pick; safe to delete automatically.
- **`/Users/sac/.scratch-beam4pm-docker-test`** — not a git repo; a plain 2.9G snapshot copy. Git gives zero signal on uniqueness here. MANUAL REVIEW REQUIRED: a human spot-check (file-listing diff against canonical) before deletion, since there is no commit history to lean on.

## Commands to run (in order), once approved

```bash
# 1. Land beam4pm-canonical's own unpushed commit first
cd /Users/sac/beam4pm
git log origin/main..main --oneline   # should show exactly ace23e5
git push origin main

# 2. tmp_beam4pm_work/beam4pm -- clean, fully pushed, safe to remove automatically
rm -rf /Users/sac/tmp_beam4pm_work

# 3. beam4pm_ws2 -- committed history is safe; the 270-file working-tree diff is NOT.
#    MANUAL REVIEW REQUIRED before anything here:
#      cd /Users/sac/beam4pm_ws2 && git status --short
#      # EITHER commit + push what's wanted (git checkout -b review/ws2-docs-types-cleanup;
#      #   git add -A && git commit -F <message-file>; git push origin review/ws2-docs-types-cleanup)
#      # OR discard if accidental (git checkout -- . && git clean -fd -- human must choose this)
#    Only once the working tree is clean by explicit human choice:
#    rm -rf /Users/sac/beam4pm_ws2

# 4. .scratch-beam4pm-docker-test -- no git ancestry to verify; spot-check manually first.
#    MANUAL REVIEW REQUIRED:
#      diff <(cd /Users/sac/.scratch-beam4pm-docker-test && find . -maxdepth 2 | sort) \
#           <(cd /Users/sac/beam4pm && find . -maxdepth 2 | sort) | less
#    Once confirmed nothing unique is present:
#    rm -rf /Users/sac/.scratch-beam4pm-docker-test
```

## Open questions

- `beam4pm_ws2`'s 268 deleted `docs/reference/types/*.md` files: git cannot tell whether this was deliberate restructuring or an accidental clean/bad checkout — user must inspect and decide.
- `.scratch-beam4pm-docker-test` has no `.git`; whether any file in it is unique can only be settled by manual file-level diff, not git tooling.
- beam4pm-canonical's object store contains commit objects for `626f85e5` (ws2 HEAD) and `15b50779` (ws2work HEAD) even though no local/remote branch there points to them (`git cat-file -e` succeeded, `git branch -a --contains` found nothing) — likely leftover from a previously fetched-then-pruned ref; not traced further since it doesn't affect this cleanup plan, but noted for a future git-gc/prune pass.
- `main` and `ws2work` inside `beam4pm_ws2` were confirmed safe by ancestry but weren't independently checked for their own working-tree diffs — not needed, since only the checked-out branch in a non-worktree clone can carry a working-tree diff at a time.

Full document written to `/Users/sac/beam4pm/docs/jira/v26.9.17/cleanup-merge-plan.md`. No files were deleted, merged, or modified — only read-only `git`/`du`/`ls`/`find` commands were run, and one `docs/jira/v26.9.17/` directory plus this one markdown file were created.

## Merge Execution Log (2026-09-17)

Evaluation/merging pass executed per user instruction: no deletion performed (deletion is
handled by a separate pass); only additive `git` commits/pushes. Re-verified current state
before acting; all real commands, real output.

### Actions taken

1. **`/Users/sac/beam4pm` `main` pushed to `origin/main`.** Fast-forward, no conflicts:
   `293d26f..ace23e5 main -> main`. Verified `origin/main` now == local `main`
   (`ace23e584e89ecc52775b9155ef9592df67d90a3`, 0 ahead / 0 behind).

2. **Three local-only canonical branches discovered and pushed to `origin`** (found during
   re-verification — not listed in the original plan, since it only compared branches across
   the 4 repo copies, not canonical's own unpushed local branches):
   - `feat/ocel-evidence-architecture` -> new branch on origin @ `8ef5de174faa89b5368d1c41f9502c186674eabe`
   - `release/v26.9.10` -> new branch on origin @ `91c83abcb9a1191a5d4421110e35995a61a5fc63`
   - `worktree-wf_8afd29ab-933-4` -> new branch on origin @ `7aa4f6485203b5f2f6db7ab118092d02c01670e7`
   - (`integration/htn-fond-hddl` was also locally upstream-less, but re-verified as byte-identical
     to `origin/integration/htn-fond-hddl` already — `12ed60bbc9c102af109176fdde4f9a72c0328ed3`
     both directions via `git merge-base --is-ancestor`. Nothing to push, no action taken.)
   All three pushes were plain `git push origin <branch>` creating brand-new remote refs — no
   existing origin ref was touched or overwritten.

3. **`/Users/sac/beam4pm_ws2`'s 270-file uncommitted working-tree diff preserved, not decided.**
   Re-verification found the diff was **larger/different in kind** than the original plan
   described (plan said "268 deletions under `docs/reference/types/`"; real breakdown of the
   268 deletions is **235 under `docs/reference/types/*.md`, 16 under `lib/*.ex`, 17 under
   `test/*.exs`** — i.e. real Elixir source and test modules were also staged for deletion, not
   just per-type docs — plus the 1-line `ggen.lock` change already noted). The canonical repo
   still has all 593 files under `docs/reference/types/` present, so this deletion is
   uncorroborated anywhere else and its intent could not be confirmed.
   - Per the "preservation over guessing" instruction: created a new branch
     `review/ws2-docs-types-cleanup-20260917` from `beam4pm_ws2`'s current HEAD (`626f85e5`,
     the original `feat/pro-ocpm-simulation-tenancy` branch, untouched at that SHA), committed
     the entire diff verbatim as one commit `c8af985381be08d2a72808f7cd0b32788ae54072`
     ("chore(review): preserve uncommitted working-tree state as-is for human review" — commit
     message explicitly states no judgment was made on intent), and pushed it:
     `review/ws2-docs-types-cleanup-20260917 -> origin` (new branch, confirmed via
     `git ls-remote`: `c8af985381be08d2a72808f7cd0b32788ae54072`).
   - `feat/pro-ocpm-simulation-tenancy` itself is untouched (still `626f85e5`, still exactly
     `0 ahead / 0 behind origin/feat/pro-ocpm-simulation-tenancy`).
   - `beam4pm_ws2`'s working directory now sits on `review/ws2-docs-types-cleanup-20260917`
     with a clean tree for the outer repo (the only remaining item is the submodule note below).
   - No decision was made about whether to fast-forward/cherry-pick this into `main` or discard
     it — that judgment call is left open below.

4. **`/Users/sac/beam4pm_ws2/vendor/ggen-marketplace` submodule — found dirty, NOT touched.**
   New discovery during re-verification (not in the original plan at all): the submodule's own
   working tree (a separate clone of `ggen-marketplace`, currently at
   `20a8732b9e55c4a5673ac2845e4d47a9b4d8ec7d`, vs. canonical `beam4pm`'s submodule pointer at
   `7abe147e14b7325336b158cc0829d83528e24668` — different versions) has **11,017 staged
   deletions and 28 untracked files**, entirely uncommitted. This is inside the submodule's own
   `.git`, not something a superproject commit can capture (a superproject commit can only move
   the submodule *pointer*, not commit changes *inside* it). Left completely untouched — no
   `git add`, no `git commit`, no `git checkout` inside the submodule. This is far too large and
   ambiguous to guess about and needs its own dedicated human review.

5. **`/Users/sac/tmp_beam4pm_work/beam4pm`** — re-verified clean, `ws3rev` branch still exactly
   `0 ahead / 0 behind origin/automation/ws3-rev-20260830-1623-fortune5-runtime-value`. No
   unique content, no action needed (deletion out of scope for this pass).

6. **`beam4pm_ws2`'s `ws2work` and `main` branches** — re-verified: `ws2work` tip (`15b50779`)
   confirmed still reachable from `origin/feat/ws2-close-productization-loops-20260831` via
   `git branch -r --contains`; `main` (`489fe2ba`) confirmed `489fe2ba` behind 532 on
   `origin/main` (plain stale local branch, no unique commits). No unique content in either;
   no action needed.

7. **`/Users/sac/.scratch-beam4pm-docker-test`** — no longer exists on disk (already removed by
   the separate, user-run deletion pass — `manual-scratch-cleanup-plan.json` and
   `scratch-cleanup-receipt.affidavit.json` dated 2026-09-17 12:41-12:43 were found alongside
   `tmp_beam4pm_work/`, consistent with that other process having already handled it). No git
   action was possible or needed here; this item is moot.

### Still open (for the separate deletion pass / further human review)

- **Decide `review/ws2-docs-types-cleanup-20260917`'s fate.** The 268 deletions (235
  docs/reference/types + 16 lib/*.ex + 17 test/*.exs) plus the `ggen.lock` line and the
  submodule pointer are now safely preserved as commit `c8af9853` on a pushed branch. A human
  needs to look at that diff and decide: (a) merge/cherry-pick it into `beam4pm_ws2`'s `main`
  or into canonical `beam4pm`'s `main` if the deletions are confirmed intentional restructuring
  work that hasn't landed anywhere else yet, or (b) discard the branch (out of scope for this
  pass — deletion is handled separately) if it's confirmed to be a stray/bad checkout state.
  Once a decision is made and acted on, `/Users/sac/beam4pm_ws2` itself becomes safe to remove
  (no unique content will remain outside git).
- **`vendor/ggen-marketplace` submodule inside `beam4pm_ws2`** (11,017 staged deletions + 28
  untracked files, uncommitted, at commit `20a8732b9e55c4a5673ac2845e4d47a9b4d8ec7d`) needs its
  own dedicated human review — this is a large, unexplained mass-deletion inside a *vendored
  dependency* clone, not application content, and was deliberately left untouched rather than
  guessed at. Whether this submodule state should even be inspected further (vs. simply
  considered disposable vendor-clone noise once `beam4pm_ws2` itself is handled) is itself an
  open question.
- **Dangling unreferenced commit objects in canonical `beam4pm`'s object store**
  (`626f85e5`, `15b50779` — carried over from the original plan doc, unchanged by this pass):
  still not traced further; a candidate for a future `git gc`/prune review, not urgent.
- **Once `review/ws2-docs-types-cleanup-20260917` is resolved (previous item)**, the following
  become safe to delete in the separate deletion pass, exactly as the original plan already
  concluded: `/Users/sac/tmp_beam4pm_work` (clean, fully pushed, re-confirmed above) and, after
  that resolution, `/Users/sac/beam4pm_ws2` itself. `/Users/sac/.scratch-beam4pm-docker-test` is
  already gone and needs no further action.
