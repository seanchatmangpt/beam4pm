---
id: b4p-p2-ocel-validate-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: ocel validate (Küsters & van der Aalst 2025) surfaced in BeamPM.Dfcm and cross-validated vs RF3Ocel on the n05/n13/n14 falsifier fixtures"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p2 (branch parity/ocel-validate). Read _CONTEXT.md.
1. `autofde ocel validate --help`; run it for real on
   qualification/fixtures/{positive-self-authored,n05-o2o-dangling,n13-duplicate-object-id,n14-undeclared-event-type}.ocel.json
   AND the gym_bridge captures.
2. Add BeamPM.Dfcm.ocel_validate/1 wrapper + @spec + doctest.
3. Cross-validation: for each fixture, record lab verdict vs BeamPM.RF3Ocel
   run_opts verdict (oracle binary native/rf3-ocel-oracle/target/release/
   rf3-ocel-oracle; build if missing). Same accept/refuse boundary? Name
   every divergence and attribute it (spec version vs implementation).
4. Tests green in test/beam4pm_dfcm_test.exs idiom.
Gates: real runs (command+exit); cross-validation table; ledger row.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/ocel-validate @ 8ba9480 | 6 lab runs + 6 oracle runs: 3 MATCH (positive/n05/n13), 2 attributed divergences — D1 law coverage (OCPQ Def.2 string universe vs RF3 declared-membership), D2 capture-format schema — both pinned as permanent tripwires. ocel_validate/1 added; tests 13/0 + dfcm 16/0; gate 50/43; admissions +3 lockstep (renderer not runnable in worktree — sync at integration). Remaining: D1 upstream spec decision | coordinator integration |
