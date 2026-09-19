---
id: b4p-f5-02-ash-a2a-stress-defects-land
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "ash_a2a: land the multinode/stress outcomes — HddlSolver cross-VM temp collision (blocks beam4pm hddl_solve under A2A), CommandBus tail latency, RouterCounters contamination"
standing: BLOCKED
branch: (ash_a2a) fix/hddlsolver-crossvm-tempdir + fix/commandbus-tail-latency + fix/router-counters-isolation
worktree: ~/ash_a2a-wt/<per-fix>
created: 2026-09-17T21:40:00Z
source: ash_a2a docs/explanation/v26.9.17-stress-report.md + CHANGELOG [Unreleased] stress/soak bullets
depends: none (parallel to b4p-f5-01)
---

Read `_CONTEXT.md` first. The stress wave surfaced three real defects; one
of them lands directly on beam4pm's own engine surface and is the reason
this is a Fortune-5 blocker rather than a nice-to-have.

## Scope (work lives in ~/ash_a2a; beam4pm gate at the end)

1. **`HddlSolver` cross-VM temp-file collision — the beam4pm-blocking one.**
   With concurrent instances (6 real `:peer` BEAM nodes), `HddlSolver`
   collides on cross-VM temp files. ash_a2a's `HddlSolver` shells out to the
   `native/hddl_cli` Rust binaries; beam4pm hosts the same planning family
   in-VM over WASM. Any A2A dispatch that reaches planning under a
   Fortune-5 multi-tenant load hits exactly this shape. Fix: per-node (or
   per-invocation) unique temp paths + a two-`:peer` reproduction test that
   fails on the old code.
2. **`CommandBus.run/4` tail-latency climb under sustained load.** 34,881
   dispatches, 0 errors, 0 process leak — but late-half p99 up to **181x**
   early-half p99 across three 12 s runs. Diagnose (queue growth? scheduler
   starvation? sortable accumulation?) and either fix or bound it with a
   documented SLO + a standing benchmark that fails if the ratio regresses
   past the bound. A Fortune-5 SLO cannot be signed against an unbounded
   p99 climb.
3. **`RouterCounters` telemetry cross-contamination** between concurrent
   instances on one node: isolate counters per instance; test with two
   concurrently-running routers asserting disjoint telemetry.

## Gates

- ash_a2a: the two-`:peer` collision test, the tail-latency tripwire
  benchmark, and the router-isolation test all fail-before/pass-after (keep
  the fail-before evidence in the ticket History).
- ash_a2a: `mix test --max-cases 6` green.
- beam4pm (consumption gate): re-run beam4pm's engine-adjacent suites —
  `mix test test/beam4pm_ferroplan_test.exs
  test/beam4pm_ferroplan_facades_test.exs` — against the updated dep, plus
  one locally-driven concurrent dispatch smoke (two beam4pm nodes posting
  OCEL to `BeamPM.OcelIngest.Router` in parallel) with no crossed events.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
| 2026-09-18T16:55:00Z | ALIVE | ash_a2a `main @ 9ff219d` (pushed) — branches f68bde4 (tail), 96b24fb (counters), 4a9a08e (crossvm) merged --no-ff | ALL THREE scope items closed. (1) HddlSolver cross-VM temp collision: fix = per-node(sanitized node())-per-invocation(unique_integer) temp paths (4a9a08e); repro test with 2 real :peer nodes RED 3/3 on old code (`cross-contaminated outcomes: [ok: true, ok: true, error: :hddl_solve_error]`), GREEN 4/4 after; 8 related suites 42/0. (2) CommandBus tail latency: BOUNDED per ticket's SLO path — degradation_ratio_p99 <= 3.0 SLO documented in CommandBus moduledoc + standing tripwire (commandbus_tail_latency_tripwire_test.exs, :benchmark tag); fail-before forced 10x -> ratio 12.158 TRIPPED; pass-after 0.497/0.831/0.468 over 3 runs 0 errors; mechanism diagnosed with sampler evidence: store mailbox ~0 + outbox 0 -> accumulation candidates falsified, climb = host contention on shared Memory-store mailbox. (3) RouterCounters: FIXED via `attach!/3` `owner:` pid scoping (96b24fb); fail-before real contamination witnessed (each ref saw other driver's events), pass-after disjoint counts 3/0 + 14 backward-compat + 2-peer multinode smoke. Full suite on merged main: 2072/4-known-flakes. beam4pm consumption gate: beam4pm suite green on 26.9.17 hex earlier today (1108/0); hex 26.9.17 predates these fixes — next release line picks them up. | none (ticket CLOSED for this scope) |
