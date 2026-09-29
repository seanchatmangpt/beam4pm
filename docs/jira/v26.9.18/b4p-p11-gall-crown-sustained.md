---
id: b4p-p11-gall-crown-sustained
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "crown: self-sustaining GALL work loop sustained 300s unattended, every cycle receipted and projected as OCEL v2 evidence (v26.9.18 §49, repository-local closure)"
standing: ALIVE
---
Worktree: ~/beam4pm-worktrees/gall-v26.9.18 (branch feat/gall-swf-v26.9.18).
Composes the admitted `BeamPM.GallOcel` projection/conformance machinery with a
real in-process lifecycle driver `scripts/gall_crown_run.exs` (hand-authored
manufacturing-time infrastructure, outside the gate's manufactured roots;
status disclosed, not hidden).

## What sustains itself

The loop manufactures its own successor checkpoints: cycle 1 runs the genesis
checkpoint (no dependencies); every later cycle creates
`urn:gall:checkpoint:beam4pm:crown-NNNN` `gall:dependsOn` the promoted
predecessor. The frontier condition (standing UNKNOWN ∧ all dependencies
ALIVE, PRD §11.1) is evaluated against the loop's own graph state — no
external feed, no operator input between start and deadline. Each cycle
performs a REAL lifecycle, and every projected event names a thing that
actually happened: run dir created, candidate file written, digest computed,
receipt sealed, standing transitioned. Observation, never subject success:
all events carry `authority: none`; in-process run/epoch/lease/worker are
observed subjects, not external XaaS/ZCode integrations.

## Sustained-run evidence (2026-09-19T06:32:22Z → 06:37:22Z)

- exit 0; `outcome: sustained_deadline`; wall **300.143s** (≥ 300 required)
- **1794 cycles**, all promoted: `standing_counts: {ALIVE: 1794}`
- **21528 events** = 12 per cycle × 1794 (full lifecycle minus repair_created;
  **zero verification failures — no repair ever needed**)
- final full-trace conformance `BeamPM.GallOcel.check/1` → `:ok`
- OCEL v2 envelope (`objectTypes/eventTypes/objects/events`):
  `~/gall-crown-runs/v26.9.18-crown/ocel_v2.json`,
  sha256 `3628725798f4144df97c52ef24901fffcbb05a968e4dcfe9e2010a94a9161f31`
- event histogram (independent audit): every one of the 12 lifecycle event
  names exactly 1794×; objects: checkpoint/run/epoch/lease/candidate/receipt
  1794 each, worker 1, verifier 1
- event-time span 06:32:22.316Z → 06:37:22.277Z = 299.96s
- digest chain audit: 5 random cycle receipts re-hashed independently —
  `candidate_sha` == sha256(candidate.json bytes) in all cases; verifier pass
- exact subject binding: run against base `242982d129797c0c7a0a361a8538d6b2e918d321`
  (the driver commit itself); base_sha embedded in every checkpoint and receipt

## Falsifiers attempted (iterate loop before the sustained run)

1. smoke round 1: CaseClauseError — genesis checkpoint never executed, so the
   frontier re-selected it forever. Fix: cycle 1 runs genesis; successors only
   after predecessor ALIVE.
2. smoke round 2: KeyError crown-0002 — graph update-syntax on a map lacking
   the fresh successor + successor id numbering skipped. Fixed both.
3. smoke round 3: `Enum.frequencies/2` does not exist (finish phase). Fixed.
4. smoke round 4: clean — 30 cycles, exit 0, conformance :ok, honest
   PARTIAL_ALIVE (cycle cap bound before deadline).
5. launch falsifier: first 300s launch died at shell redirect (parent dir
   absent) — relaunched after mkdir; run verified live before going unattended.

## Replay

```
cd ~/beam4pm-worktrees/gall-v26.9.18
GALL_CROWN_DURATION=300 GALL_CROWN_MAX_CYCLES=2500 GALL_CROWN_PACING_MS=160 \
  GALL_CROWN_ROOT=$HOME/gall-crown-runs/<id> mix run scripts/gall_crown_run.exs
```
Bounds are explicit (柵): duration 300s, cycle cap 2500, per-cycle pacing
160ms; whichever bound binds first ends the run and is typed in summary.json
(`sustained_deadline` vs `cycle_cap_before_deadline`).

## Gates

| gate | result |
|---|---|
| `bash scripts/gate_authorship_check.sh` | PASS — 51 admitted (44 debt), 0 findings; driver adds no root file |
| `BeamPM.GallOcel.check/1` full 21528-event trace | `:ok` |
| smoke suite (4 rounds) | final: exit 0, 30/30 ALIVE |
| authorship SHA-drift | no admitted file touched |

## Scope ceiling (typed honestly)

ALIVE is the **repository-local, in-process** closure (PRD §6 permits this
tier). NOT claimed: external ZCode worker invocation, live XaaS
Run/Epoch/Lease server, cross-repo composition — those §49 steps remain
PARTIAL_ALIVE at best and are owned by the xaas/zcode-cli slices.

## History

| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-19T06:40:00Z | ALIVE | feat/gall-swf-v26.9.18 @ 242982d | gate PASS 51/44 0 findings; smoke 4 rounds → 30/30 exit 0; sustained 300.143s / 1794 cycles / 21528 events, conformance :ok, exit 0 | external-worker + cross-repo §49 steps (xaas/zcode-cli slices) |
