---
id: g4-igniter-admission-task
dcterms:title: "mix ggen_igniter.hand_authored — the lockstep admission task that retires the hand-in-lockstep ledger stumble every wave agent made"
standing: BLOCKED
---
Worktree: ~/ggen_igniter-wt/g4 (branch feat/hand-authored-admit-task from
current HEAD). Proof scratch:
/Users/sac/beam4pm-worktrees/wt-g4-proof (branch scratch/g4-proof from
beam4pm parity/integration @ 70e2662 — it carries the wave's +11
admissions + raised ceilings). Read _G-CONTEXT.md.
Author a mix task (admit/list/check verbs) that performs the whole
hand-authored-source admission lawfully: validate capability-object fields
per the pack's gates 050/060/070 laws (sha256, expiry, sunset plan, kind
vocabulary, ceilings), append the ontology individual, run the sync render,
run the gate. PROOF: on wt-g4-proof, revert the wave's +11 admissions to
the pre-wave state (git), then re-admit them THROUGH THE TASK and reach the
same gate state (authorship gate PASS, counts matching parity/integration's
64/57) — proving the task replaces the hand lockstep. ggen_igniter's own
tests green; version bump per house rules.

## History

- 2026-09-19 | BLOCKED -> ALIVE | ggen_igniter feat/hand-authored-admit-task (from d018ed4; task+tests+CHANGELOG 26.9.18 committed this session) | proof in wt-g4-proof (scratch/g4-proof @ 70e2662, vendored pack at f2ae5382e): gate baseline PASS 64/57 -> revert 36b0ed9 (47/40, 17 REFUSED_UNADMITTED) -> all 17 wave rows re-admitted THROUGH `mix ggen_igniter.hand_authored admit` (sha256s match wave digests; qualification 50/50, facade 7/7 AT CEILING) -> render via task (force-scaffold + FM-PACK-008 re-lock + restore; TSV/MD/GATE-TEST/LOCK byte-identical to 70e2662) -> gate PASS 64/57 via script AND task `check`; 8 refusal falsifiers + dry-run/no-render typed-refused | ggen_igniter `mix test`: 957 tests 0 failures; task file 26/26 | receipt: /Users/sac/ggen_igniter-wt/g4/WAVE-RECEIPT.md | remaining: `force: true` retirement of the 3 pack templates (pack edit + re-lock, out of scope); `update` verb for drifted re-admission; render dance tested on real consumer only.
| 2026-09-19T00:30:00Z | ALIVE | ggen_igniter feat/hand-authored-admit-task @ 9858ac0 (26.9.15 -> 26.9.18) | mix ggen_igniter.hand_authored (admit/list/check): validates all 050/060/070 laws pre-write, appends, renders (force-scaffold -> re-lock -> sync -> restore), typed REFUSED_* exits, --dry-run. PROOF on wt-g4-proof @ 70e2662: baseline 64/57 -> revert to 47/40 (gate REFUSED 17 findings) -> all 17 rows re-admitted THROUGH the task, sha256s match wave digests, ceiling arithmetic observed to 50/50 + 7/7 AT CEILING, renders byte-identical to 70e2662, final gate PASS 64/57 via shell AND task. 8 typed-refusal falsifiers; 2 real falsifiers (inline block terminators, no-trailing-newline) fixed as tripwires. ggen_igniter 958/0. 産面 hand lines this session: 0 | igniter release = operator cut |
