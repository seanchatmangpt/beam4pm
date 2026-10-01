# WAVE-RECEIPT — v26.10.1 ash_ex4pm adoption (5 waves × 10 agents)

Date: 2026-10-01. Operator order: "launch 10 agents in one message to upgrade
beam4pm to use https://hex.pm/packages/ash_ex4pm. Refactor anything out of
date. Launch 5 waves of 10 agents" (default-agent, all waves).

## Identity

- Subject: seanchatmangpt/beam4pm, base fee843a2 → integrated on main @
  cab7a3a0 (per-lane work landed via the concurrent-session merges
  7bad16ab..d7d9b329 — see R15 — plus this wave's admission commit).
- Wave shape: W1 survey ×10 (read-only) → resolutions → W2 write ×10 →
  W3 audit ×10 → W4 adversarial ×10 → coordinator repairs → W5 verify ×10
  (1 dynamic ladder + 9 static) → integration.

## What landed

- `{:ash_ex4pm, "~> 26.10"}` (hex 26.10.1, exact-pins ex4pm == 26.10.1);
  version bump 26.9.30 → 26.10.1 (mix.exs + app.src via version_bump task);
  lock purely additive (+19 packages, 0 pins moved: ash 3.33.11, ash_a2a git
  80b77e2, a2a 0.3.0, wasmex 0.15.1, postgrex 0.22.4).
- `config :ex4pm, wasm_host: false` (beam4pm stays sole wasm host;
  Ex4pm.Evidence.Store auto-starts as the emission sink).
- Law-side emission wiring in the pack (vendored + ~/ggen-marketplace
  mirror, byte-identical): `bpm:ocelTypeExpr` scalar ladder,
  `?ocel_type_expr` weak-optional projection, resource template renders
  `extensions: [AshEx4pm]` + create-only `ex4pm` block + named skip comments
  (no explicit notifiers — R2); domain-template comment reword.
- Tests: ex4pm runtime aliveness (store alive, ingest/dedup/refusal),
  adoption-seam qualification (always-on law-side tripwires + dormant live
  bodies), BRCE gate contract falsifiers (admit/deny/raise/zero-receipts).
  18/18 mission tests green (V1 ladder, one narrow arity repair).
- Docs: CHANGELOG [26.10.1] + [Unreleased] (realtime capture, actor's),
  README bullet, reference-doc AshEx4pm section — all post-repair truthful
  (frozen-projection posture named, R14 cited). Release workflow
  release-v26.10.1.yml (fails closed until ash_a2a ≥ 26.9.30 ships; publish
  env set on deps.update + hex.build).
- R11 admissions: 4 files admitted + 3 digests refreshed; ceiling
  hand_authored_qualification 50 → 54; TSV/md/gate-test re-rendered via the
  Rust ggen leg. Gate authorship: 48 findings, ZERO naming mission files
  (baseline 47 + actor-owned debt).

## Standing (typed)

- R14 **BLOCKED (upstream, pre-existing)**: Ash-leg projection frozen at 647 —
  root graph admits 677 records; ggen_igniter 26.9.15 ReconcileReactor's
  per-actuation `mix compile --warnings-as-errors` + rollback deadlocks any
  growth ordering. No CLI/env bypass (verified against source). Fix is
  upstream (growth-aware reconciliation or atomic multi-recipe step).
  Consequence: manufactured-line ratio for THIS change ≈ 0% (honest); the
  86 law-side pack lines render 647 resources the moment R14 clears.
- R8 BLOCKED (pre-existing): hex-publish mode needs ash_a2a ≥ 26.9.30 on hex
  (latest 26.9.22).
- R15: a concurrent operator session interfered twice (path-override dep,
  then a 6-artifact SOAK/realtime wave), then integrated both streams onto
  main. Their artifacts preserved-not-adopted where mission-scoped; their 3
  test files + notes/ + research/erc remain their uncommitted debt. The
  realtime-broadcaster work is upstream-first in ~/ash_ex4pm (uncommitted).
- Full suite (V1, natives built): 1697 tests, 18 failures — 0 mission-class;
  9 environment (rf4 oracle + lab venv), 9 pre-existing (proven at base),
  16 skips (pre-existing classes). Baseline 1164/0/52 does not reconcile
  with HEAD (stale receipt); V1's numbers supersede.

## Falsifiers that fired (courts > pre-thinking)

- W3 audit: 4 defects in coordinator-written emission test (compile-breaking
  interpolation, refute contradicted by template comment, invalid ExUnit
  skip return, wrong metadata field) — all repaired.
- W4 V2 mutation battery: 3 vacuous assertions proven vacuous → re-anchored
  (render-line finder with comment exclusion, structural OPTIONAL match);
  W5 V5 re-proved 4/4 mutations caught post-fix.
- W4 V4: release-workflow gates incoherent vs mix.exs publish mode →
  require_version ash_a2a 26.9.30 + BEAM4PM_HEX_PUBLISH on update/build.
- Reactor rollback witnessed live twice (both typed refusals, logs kept).
- Admission digest: hand-copied 66-char sha caught by the gate's
  MANIFEST_MALFORMED check; fixed programmatically from disk truth.

## What the operator did not write

Everything above: 50 lane dispatches, all resolutions, all repairs, the
receipt. Operator keystrokes this session: the original order only. The
concurrent session (operator-side) authored the realtime-capture stream and
the final merge integration.

## Residue

- vendor/ggen-marketplace: dirty with the 5 wave pack edits; pointer moved
  by the concurrent session to 637b561c (dangling-pin CI fix). Upstream
  PR for the 5 edits + pointer bump = operator cut (~/ggen-marketplace
  mirror holds byte-truth).
- Actor's untracked notes/ + research/erc + 3 test files: their session's.
- Lane build roots deleted (~5.9 GB reclaimed; only canonical _build kept).
