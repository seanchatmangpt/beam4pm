---
id: b4p-f5-09-fortune5-trial-closure
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "CROWN: Fortune-5 trial closure — beam4pm on the reconciled engine, real A2A/OCEL loop evidence, SLO/evidence surfaces visible in ~/xaas"
standing: BLOCKED
branch: story/fortune5-trial-v26.9.17
worktree: (beam4pm main checkout)
created: 2026-09-17T21:40:00Z
source: beam4pm FORTUNE5_* docs (blocks catalog 26.7.31, control matrix, workflow pattern coverage) + prior story/GI-06-beam4pm-fortune5-trial + xaas OcelForwarder surface
depends: b4p-f5-01, b4p-f5-02, b4p-f5-03, b4p-f5-06, b4p-f5-08
---

Read `_CONTEXT.md` first. This is the crown ticket of the set: everything
else exists so this one can run for real. "Ready for Fortune 5 customers in
~/xaas" means a single evidenced trial: the hardened engine behind the
facades, the real agent loop producing the evidence, and xaas able to see
it over its lawful surface — no mocks, no honest skips.

## Scope

1. **Engine line**: ferroplan pin reconciled (b4p-f5-05) and verdict-flip
   audited (b4p-f5-06); facades ontology-fresh (b4p-f5-07). The trial runs
   `hddl_solve`/`fond_policy` on at least: one deterministic HTN fixture
   (solve), one retry-loop FOND fixture (strong-cyclic policy with a
   goal-reaching choice set — post-FOUND_BUG_2 semantics), one dead-end
   fixture (real `NoPlan` + `FP_*` stage code). Verdicts recorded with the
   engine commit SHA.
2. **Agent loop line**: ash_a2a defects landed (b4p-f5-01/02), captures
   regenerated (b4p-f5-03) — the plan → A2A dispatch → OCEL ingest →
   conformance loop executes end-to-end in the trial, against the released
   beam4pm (b4p-f5-08), not a dev path-dep.
3. **xaas line**: run (or drive from) `Xaas.Telemetry.OcelForwarder`'s
   consuming side so the trial's OCEL events land where a Fortune-5
   deployment's evidence plane would read them; produce the SLO evidence
   bundle the FORTUNE5 control matrix names for the runtime tier (latency
   numbers honest about the CommandBus tail-latency disposition from
   b4p-f5-02 — bounded or fixed, never hidden).
4. **Receipt**: a trial report under `docs/jira/v26.9.17/` with commands +
   exits, engine/dependency SHAs, verdicts, capture provenance, SLO table,
   and the falsifiers attempted (kill-an-engine-mid-op →
   `engine_restarted` restart path exercised; revoked-authority mid-flight
   → refusal; garbage admission → typed refusal). A trial report without
   attempted falsifiers is not a closure.

## Gates

- All dependency tickets' gates green (no waivers; a waived dependency
  closes this as BLOCKED with the reason).
- The end-to-end loop executes with zero honest-skips in beam4pm's
  closure test.
- Trial report committed; standing for this ticket set's README index
  updated to the observed state — `ALIVE` only if every line above ran
  against the exact admitted subjects in the closing session.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
