---
id: b4p-f5-03-ash-a2a-qualification-captures-regenerate
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "ash_a2a → beam4pm: regenerate the qualification/gym_bridge A2A/OCEL captures on the landed v26.9.17 line so beam4pm's plan-execute-conform closure stops honestly skipping"
standing: BLOCKED
branch: (ash_a2a) chore/qualification-captures-v26.9.17
worktree: ~/ash_a2a-wt/captures
created: 2026-09-17T21:40:00Z
source: beam4pm ontology.ttl admission facts for the plan-execute-conform loop (reads qualification/gym_bridge/*.json; honestly skips when absent)
depends: b4p-f5-01, b4p-f5-02
---

Read `_CONTEXT.md` first. beam4pm's cross-repo closure evidence — the loop
"real HDDL plan → real A2A dispatch → real HTTP POST →
`BeamPM.OcelIngest.Router` → real 201-confirmed echoes → OCEL rebuild →
`BeamPM.PowlConformance`" — is only as real as the capture files, and the
only producer is the ash_a2a-side end-to-end test. Today's captures predate
the v26.9.17 harden/stress line (and the two defects ticket b4p-f5-01
fixes touch exactly the admission/actuation path the captures walk).

## Scope

1. In ~/ash_a2a, after b4p-f5-01/02 land: build `native/hddl_cli`
   (`cargo build --release --locked` — required in any fresh checkout),
   run the end-to-end A2A → beam4pm-ingest test, and regenerate
   `qualification/gym_bridge/*.json` (both `reference_ocel_events.json` and
   `deviant_ocel_events.json` flavors) against a beam4pm running the
   **reconciled ferroplan pin** (b4p-f5-05) so the captured plan verdicts
   are post-wave-6, not pre-fix.
2. Commit the captures in ash_a2a (they are that repo's artifact), then
   copy/refresh beam4pm's `qualification/gym_bridge/` copies verbatim with
   provenance (source SHA of both repos in the commit message).
3. In beam4pm, run the closure test that today honestly skips — it must now
   run for real, and any conformance verdict change versus the old captures
   must be explained in the ticket History (expected: verdict-flip class
   from the engine hardening, cf. `_CONTEXT.md`).

## Gates

- ash_a2a: e2e test green; captures committed and pushed.
- beam4pm: the plan-execute-conform closure test executes (not skips)
  against the new captures, `mix test` green; provenance SHAs recorded.
- No hand-edited capture bytes: any need to touch a capture by hand is a
  `REFUSED_*`, recorded, not papered over.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
| 2026-09-18T16:55:00Z | PARTIAL_ALIVE | beam4pm `main @ 22fa4aa` working tree (captures) + ash_a2a @ 9ff219d | Captures regenerated TODAY on the v26.9.17 hex line: e2e producer 1 test/0 failures (ERC-001-1789759137116: 18 ref + 5 deviant 201-accepted), beam4pm consumer closure ran for real (ERC-002-1789759169643: deviation detected, alignment_cost 1, log_fitness 0.909, missing clean_house) — the loop no longer honestly skips. OCEL-v2-generosity falsified via 9 live probes + freshness diff. REMAINING for full close: re-run producer+consumer against a beam4pm RUNNING the reconciled ferroplan pin (chore/ferroplan-pin-bump @ 53e31a3, staged in worktree pending beam4pm main checkout availability — note the gym loop's HDDL actually comes from ash_a2a's hddl_cli, which is already on the post-merge 9ff219d line; the pin-coupling clause needs an honest re-read when the bump lands) | scope 2 commit-in-ash_a2a of captures (captures are regenerated artifacts in beam4pm; decide whether ash_a2a also vendors a copy) |
