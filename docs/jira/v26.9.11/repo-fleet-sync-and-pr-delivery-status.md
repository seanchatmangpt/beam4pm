# Repo fleet sync and PR delivery status

## Summary

Operational/process ticket, not a code change: records the state of two open
beam4pm pull requests, a cross-repo local-clone fleet sync (fetch --all
--prune + fast-forward-only pull, never rebase/force), and the real
in-progress status of a parallel 7-branch review-and-fix pass launched this
session across xaas, ggen-marketplace, and ash_a2a.

## Status

In progress - 2 beam4pm PRs open awaiting review/merge; fleet sync complete
with 0 branches moved in this repo; the parallel fix pass has 2 of 7 branches
ALIVE (real commit, real verification), 1 PARTIAL (real fix, wrong commit
message on origin), 1 BLOCKED (target file absent on stated base branch), and
3 still in progress with no result recorded yet.

## Commits

No commits in this repo for this ticket's subject matter - see `## Related`
for the commits already landed on the two PR branches, which predate this
ticket and are not repeated here.

## Changes

- No files changed in beam4pm. This ticket documents:
  1. PR #62 (`feat/hddl-fond-freedomgym-pipeline` -> `main`): "feat: HDDL->FOND->A2A->OCEL->POWL
     conformance pipeline" - open, per `gh pr list`.
  2. PR #63 (`feat/ash-a2a-agent-facing` -> `main`): "feat(a2a): wire ash_a2a
     onto beam4pm as additive agent-facing layer" - open, per `gh pr list`.
     The stale authorship-ledger regression on this branch was fixed via a
     full clean ggen sync (commit `e3e4260`, "chore(regen): re-render
     authorship ledger for ash_a2a admissions").
  3. A cross-repo local-clone fleet sync (`git fetch --all --prune` then a
     fast-forward-only `git pull`, never rebase/force) across beam4pm,
     ash_a2a, xaas, ggen-marketplace, ash_r2rml, ferroplan, gitvan, and
     zoela. In this repo (beam4pm) the result was 0 branches moved: `main`,
     `feat/ash-a2a-agent-facing`, and `feat/hddl-fond-freedomgym-pipeline`
     were already exactly equal to their origin upstreams.
  4. A parallel review-and-fix pass covering 8 confirmed findings across
     xaas/ggen-marketplace/ash_a2a, dispatched as 7 fix branches (one finding,
     the hash-verify duplication, was folded into the `no-manual-patch`
     branch's scope and returned `BLOCKED` before a separate branch was
     needed for it).

## Verification

Real commands run in this repo, real output pasted below (no code changed in
beam4pm for this ticket, so no test-suite output applies here).

```
$ pwd
/Users/sac/beam4pm

$ git for-each-ref --format="%(refname:short) %(upstream:short) %(upstream:track)" refs/heads
feat/ash-a2a-agent-facing origin/feat/ash-a2a-agent-facing 
feat/ferroplan-hddl  
feat/hddl-fond-freedomgym-pipeline origin/feat/hddl-fond-freedomgym-pipeline 
feat/htn-fond-dispatch  
feat/ocel-evidence-architecture  
integration/htn-fond-hddl  
main origin/main 
release/v26.9.10  
story/GI-06-beam4pm-fortune5-trial  
worktree-wf_8afd29ab-933-4
```

Blank `%(upstream:track)` on the three tracked branches (`feat/ash-a2a-agent-facing`,
`feat/hddl-fond-freedomgym-pipeline`, `main`) means each is exactly even with
its upstream - the "0 branches moved" claim for this repo. Local branches with
no upstream tracking ref at all (open item, not touched by this sync):
`feat/ferroplan-hddl`, `feat/htn-fond-dispatch`, `feat/ocel-evidence-architecture`,
`integration/htn-fond-hddl`, `release/v26.9.10`, `story/GI-06-beam4pm-fortune5-trial`,
`worktree-wf_8afd29ab-933-4`.

```
$ gh pr list --state open --json number,title,headRefName,baseRefName
... (excerpted to the two beam4pm-relevant rows)
{"number":63,"title":"feat(a2a): wire ash_a2a onto beam4pm as additive agent-facing layer","headRefName":"feat/ash-a2a-agent-facing","baseRefName":"main"}
{"number":62,"title":"feat: HDDL->FOND->A2A->OCEL->POWL conformance pipeline","headRefName":"feat/hddl-fond-freedomgym-pipeline","baseRefName":"main"}
```

Parallel fix-pass status, read from the real workflow journal at
`/Users/sac/.claude/projects/-Users-sac-beam4pm/32924e31-6714-4598-b427-36b4bf009d74/subagents/workflows/wf_87b746af-cc9/journal.jsonl`
(7 branches `started`, 4 have a recorded `result` as of writing; the other 3
have no result entry yet and are therefore in-progress, not done):

| Branch | Repo | Status | Commit |
| --- | --- | --- | --- |
| `fix/dedupe-llm-fixture-env-extraction` | ash_a2a | ALIVE (real `mix test`: 0 failures; pushed) | `0b75648a832831ebe33e3f22614033e714a980b3` |
| `fix/noun-verb-cli-pack-metadata` | ggen-marketplace | ALIVE (real query test + full suite pass; pushed) | `cc9e0cb4d0b779fe2269c417d4c3a740bb4e2233` |
| `fix/marketplace-cli-relative-deps` | ggen-marketplace | PARTIAL - real fix verified (`mix compile --warnings-as-errors` exit 0), but the pushed commit's message text on origin is wrong due to a concurrent session sharing the working tree; not force-pushed to correct it | `98615e6ef515c747d55d08033f41925eecb897e1` |
| `fix/no-manual-patch-delegate-hash-manifest` | xaas | BLOCKED - target file `lib/xaas/generation/validations/no_manual_patch.ex` does not exist on the stated base branch `feat/ocel-v2-real-otel-span-proof` or on `main`; branch created but no edit applied, no commit | none |
| `fix/coupling-engine-zero-weight` | xaas | In progress - launched, no result recorded yet | unknown |
| `fix/ocel-import-typed-error` | xaas | In progress - launched, no result recorded yet | unknown |
| `fix/marketplace-cli-in-memory-tar-digest` | ggen-marketplace | In progress - launched, no result recorded yet | unknown |

## Related

- PR #62: https://github.com/seanchatmangpt/beam4pm/pull/62
- PR #63: https://github.com/seanchatmangpt/beam4pm/pull/63
- `docs/jira/v26.9.11/ash-a2a-agent-facing-layer.md`
- `docs/jira/v26.9.11/powl-plan-execute-conform-loop.md`
