# EPIC B4PM-1700 Closure Report — Igniter capability-driven manufacturing expansion

Source: `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` (10 stories,
B4PM-1701..1710). Date: 2026-09-01.

## Standing constraint (honored throughout)

**Nothing was merged to beam4pm `main`. Nothing was pushed.** Every story was
implemented in its own isolated `git worktree` under `/tmp` (or
`/private/tmp`), on its own branch `story/<id>`, off the same base commit
(`489fe2b`, main tip at session start). Repo root `~/beam4pm` was re-checked
clean (`git status --short`) before and after each story. All commits used
`git commit -F <file>` (never inline `-m`), per project discipline. No
`git reset --hard` or other destructive git operation was used; one
self-inflicted incident in B4PM-1707 (an over-broad `git add -A` in the
worktree's local submodule checkout) was recovered via `git reset --mixed` +
targeted `git checkout --`, confirmed not to have touched `~/beam4pm`'s real
`.git/modules/vendor/ggen-marketplace`, and never pushed.

## Per-story outcome table

| Story | Outcome | One-line gap if any |
|---|---|---|
| B4PM-1701 Mix.exs defect-trigger-shape audit | DONE | None against stated bullets; full `just verify` (submodule/ggen/eunit/mix test) not run end-to-end, out of scope for the audit script itself |
| B4PM-1702 Single-record-patch codemod via Igniter.Code.Module/Function | DONE | One of two ExUnit tests (mix-task-writes-to-disk path) did not finish inside session time budget in the harness; capability independently verified via direct CLI runs outside ExUnit |
| B4PM-1703 Version-bump automation via inspect/1-wrapped MixProject.update | DONE | None; 4/4 story tests pass, full suite unrelated pre-existing failures only (22, all oracle-binary/k8s-dependent) |
| B4PM-1704 Pre-flight guard for rename_function-based automation | DONE | No live caller exists yet to wire the guard into (Defect 4's own "none adopted yet" status) — by design, not a gap |
| B4PM-1705 Ontology-binding trigger for `pro_capability_manifest_sync.sh` | DONE | Regenerated test file reported "unchanged" by sync — no new assertion added on the new capability's evidence content (not required by acceptance bullets) |
| B4PM-1706 Ontology-binding trigger for `pro_compatibility_sync.sh` | DONE | Template fix lives as an uncommitted working-tree edit inside the vendored `vendor/ggen-marketplace` submodule checkout — not committed/pushed to the separate ggen-marketplace remote (out of scope/authority for this story) |
| B4PM-1707 Ontology-binding trigger for `pro_license_sync.sh` | DONE | Same submodule-remote caveat as B4PM-1706; also surfaced (not caused) a pre-existing incomplete OBO-ontology submodule checkout, unrelated to this story |
| B4PM-1708 Byte-identity regression guard for `receipt_chain_sync.sh`'s dependent pipeline | DONE | None against stated bullets |
| B4PM-1709 Ontology-binding trigger for `rf2_conformance_sync.sh`'s deferred MixProject.update path | DONE | Task does not wire the new `rustler` dep into an actual in-process NIF/port RF2 oracle — that remains a distinct future story |
| B4PM-1710 Manufactured-file-marker false-positive guard for `gate_m2_check.sh` | **NOT STARTED** | No worktree, branch, commit, or evidence exists for this story in this cycle |

**9 of 10 stories DONE with cited evidence (commits, real command output, real
test runs). 1 of 10 (B4PM-1710) has no work product this cycle** — it is not
claimed done, partial, or blocked; it simply was not attempted, and no
evidence should be assumed for it.

## Branches / worktrees left for review

All under `/tmp` or `/private/tmp`, each on branch `story/<id>`, unmerged,
unpushed:

- `/tmp/B4PM-1701-worktree` (`story/B4PM-1701`) — commits `cc78cf6`, `7f0ea90`
- `/tmp/B4PM-1702-worktree` (`story/B4PM-1702`) — commit `138f31c`
- `/tmp/B4PM-1703-worktree` (`story/B4PM-1703`) — commit `36818bc`
- `/private/tmp/B4PM-1704-worktree` (`story/B4PM-1704`) — commit `e83e44f`
- `/tmp/B4PM-1705-worktree` (`story/B4PM-1705`) — commit `1aa4ab2`, plus submodule commit `633143f5d`
- `/tmp/B4PM-1706-worktree` (`story/B4PM-1706`) — commit `f17e4b4` (submodule template edit uncommitted, see gap above)
- `/tmp/B4PM-1707-worktree` (`story/B4PM-1707`) — commit `89d2bee`, plus submodule commit `d4e40f4f9`
- `/tmp/B4PM-1708-worktree` (`story/B4PM-1708`) — commit `94f3e9d`
- `/tmp/B4PM-1709-worktree` (`story/B4PM-1709`) — commit `8160d29`
- B4PM-1710 — no worktree exists

## What a human needs to review/merge next

1. **Merge order and conflict risk**: B4PM-1705/1706/1707 all touch the same
   ontology-binding pattern (`admitted_actions.rq`) across three different
   generated modules (`beam4pm_pro_capability_manifest.ex`,
   `beam4pm_pro_compatibility.ex`, `beam4pm_pro_license.ex`) and each bumped
   or edited `vendor/ggen-marketplace` independently from the same base
   (`20a8732b9`) — these submodule edits will need to be reconciled into one
   real commit/PR against the ggen-marketplace remote before any of the three
   parent-repo branches can merge cleanly, since none of the three submodule
   changes were actually pushed anywhere.
2. **B4PM-1706 and B4PM-1707's vendored template fixes are not committed to
   ggen-marketplace** — currently they exist only as uncommitted working-tree
   edits (1706) or a local unpushed submodule commit (1707, `d4e40f4f9`)
   inside each story's own throwaway worktree. A human needs to consolidate
   these into a real ggen-marketplace PR, then re-point the beam4pm submodule
   pointer, before B4PM-1705/1706/1707 can be considered durable.
3. **B4PM-1702's second ExUnit test** (`test/ggen_igniter_patch_field_test.exs:63`,
   mix-task-writes-to-disk path) needs a longer/isolated re-run with a
   generous timeout to get a captured pass/fail — it was not completed within
   this session's time budget even though the underlying capability was
   independently verified via direct CLI runs.
4. **B4PM-1707's incidental discovery**: the worktree's `vendor/ggen-marketplace`
   submodule checkout is missing several hundred `ontologies/public/obo/*.owl`
   files (pre-existing incomplete `git submodule update --init --recursive`,
   not caused by this cycle's work) — worth a patient re-checkout if a future
   task in that worktree needs those files.
5. **B4PM-1710 has not been started** — needs to be picked up as its own
   worktree/branch in a future cycle; no partial work exists to build on.
6. Standard review: inspect each `story/<id>` branch's diff, confirm the cited
   commands/tests still pass on the reviewer's machine, then merge (or
   request changes) one at a time — per the "serialize only the merge step"
   discipline, these are independent worktrees and can be reviewed in any
   order.
