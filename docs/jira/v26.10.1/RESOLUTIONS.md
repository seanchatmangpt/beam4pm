# v26.10.1 RESOLUTIONS (coordinator decisions from wave-1 evidence)

- R1 mix.exs/mix.lock/app.src/version/deps.get = coordinator-owned. Dep line
  `{:ash_ex4pm, "~> 26.10"}` after `{:ash_ai, ...}`; version bump to 26.10.1 via task.
- R2 NO explicit `notifiers:` entries — `AshEx4pm.Transformers.Persist` auto-injects
  `AshEx4pm.Notifier` (persist.ex:142-166 supersedes the package README).
- R3 Emission wiring = law-side: `beam4pm_ash_resource.ex.eex` renders
  `extensions: [AshEx4pm]` + `ex4pm do object_type :<name>, attributes: [...scalar...];
  activity :<name>_created, on: :create end` for ALL 647 resources. `:create` only
  (reads don't mutate). Non-scalar attribute types are skipped with a rendered comment,
  never silently. Type ladder = `bpm:ocelTypeExpr` facts in ontology.ttl (2026-09-05
  precedent: type ladders are ontology facts, not template code).
- R4 BRCE gate flags ZERO records this change (actor model for the 647 ETS resources is
  an operator cut; gating any of them refuses the generated 1294-fixture roundtrip which
  creates without actors). Gate contract proven by direct `Ex4pm.Evidence.BRCE.execute/4`
  falsifier test (admit/deny/raise paths). Seam recorded here; flagging = follow-up.
- R5 Bridge policy: W3 investigates deps/ex4pm for an ingest telemetry/broadcaster seam;
  if one exists, `BeamPM.Evidence.Ex4pmBridge` forwards ash-action envelopes into
  `BeamPM.Ingest.Bridge.ingest/1`. If none exists, stores stay disjoint + documented.
  Engine-op evidence chain (3-evidence pin) must remain untouched.
- R6 `config :ex4pm, wasm_host: false` — beam4pm's `BeamPM.EngineSupervisor` stays the
  only wasm host; `Ex4pm.Evidence.Store` (the notifier's sink) still auto-starts via
  `:ex4pm`'s own application mod.
- R7 NO dep removals (all have live call sites; `:req` stays — igniter pins it non-optional).
- R8 ash_a2a pin `80b77e2` untouched (ref bump out of scope; hex-publish mode BLOCKED
  upstream: newest ash_a2a on hex is 26.9.22, lacks Replan).
- R9 Submodule template edit authorized in `vendor/ggen-marketplace/...` with a byte
  mirror to `~/ggen-marketplace/packs/...`; upstream PR + submodule bump = operator cut.
- R10 Test execution serialized (ports 4210/4211; Bandit boots with app). Wave-2 lanes
  compile/format only (`mix test --no-run` allowed, no runs). Wave 5 lane V1 runs the
  entire dynamic ladder alone.
- R11 HandAuthoredSource admissions + SHA refresh happen at integration (need final
  bytes). Baseline at HEAD: gate_authorship 47 findings (42 unadmitted + 5 sha-drift),
  pre-existing. Target: no growth; admit lib/beam4pm_evidence.ex + new test files.
- R12 scripts.md untouched (no new sync script lands).
- R3 (AMENDED 2026-10-01 after regen attempt) — law-side landed: `bpm:ocelTypeExpr`
  ladder + `?ocel_type_expr` weak-optional projection + template wiring live in the
  PACK (vendor + ~/ggen-marketplace mirrors, byte-identical; domain-template comment
  reworded too). Projection render BLOCKED: see R14. Emission live-tests are dormant
  with a self-skip gate + always-on law-side tripwires
  (test/beam4pm_ash_ex4pm_emission_test.exs).
- R14 (NEW 2026-10-01) — Ash-leg projection FROZEN at 647 by a pre-existing
  reconciliation deadlock surfaced by this upgrade: root ontology graph yields 677
  bpm:RecordType rows (30 aloop_* admitted after the Sep-23 sync) while projection +
  .ggen_igniter manifest hold 647; ggen_igniter 26.9.15 ReconcileReactor runs a
  terminal `mix compile --warnings-as-errors` after every actuation AND ROLLS BACK on
  failure (System.cmd hardcoded, reconcile_reactor.ex:641-665; no CLI/env bypass;
  AR-9 made the reactor unconditional), so neither resources-then-domain nor
  domain-then-resources can pass its intermediate verify on growth. Coordinator
  witnessed both typed refusals + rollbacks live (/tmp/regen-coord.log,
  /tmp/w1_regen_main.log). Fix is upstream (growth-aware reconciliation in
  ggen_igniter, or an atomic multi-recipe step in scripts/igniter_sync.sh). Until
  then NO Ash-leg regen of any kind can land at HEAD. The 30 aloop records stay
  unrendered (pre-existing drift, unchanged by this change).
- R15 (NEW 2026-10-01, wave-3 discovery) — CONCURRENT-ACTOR INTERFERENCE: a
  second session (rider-class; identity unknown) mutated this checkout
  mid-mission (~12:28-12:38 and again during repairs): switched mix.exs to
  `{:ash_ex4pm, path: "../ash_ex4pm", override: true}` (dogfooding unreleased
  upstream notifier broadcaster work in ~/ash_ex4pm — `M lib/ash_ex4pm/notifier.ex`
  + `?? test/ash_ex4pm/broadcaster_test.exs` there), added a CHANGELOG
  [Unreleased] realtime-capture block, created scripts/ex4pm_bridge.exs,
  docs/ex4pm-realtime-capture.md, test/beam4pm_ex4pm_realtime_bridge_test.exs,
  deleted tmp_probe/ontology_merged.ttl. ADJUDICATION: the actor's artifacts are
  coherent upstream-first work and are PRESERVED; the dep line is RESTORED to
  the hex form `{:ash_ex4pm, "~> 26.10"}` (mission + release-workflow lock greps
  + hex.build refuse path deps + W10 packaging proof); their doc/caveat claims
  about the override being current were reworded to local-uncommitted-dogfooding
  posture. Their bridge test is hex-compatible by construction (passes the
  broadcaster explicitly). Standing risk for waves 4-5: the actor may strike
  again; every wave re-verifies mix.exs:88 is the hex tuple before trusting
  downstream evidence. SECOND STRIKE confirmed (13:07-13:11, wave-4 window):
  6 more unchartered paths — M scripts/ingest_telemetry.exs (Ingest.Bridge
  rewritten to a bounded ETS buffer + :ingest_buffer_cap, self-identified
  "SOAK-1"), scripts/ex4pm_soak.exs (lane S2),
  test/beam4pm_ex4pm_soak_correctness_test.exs,
  test/beam4pm_ingest_bridge_buffer_cap_test.exs, bench/ex4pm_bridge_bench.exs
  (lane S4), notes/ex4pm-realtime-audit.md (lane L5). ADJUDICATION: same R15
  posture — preserved, NOT adopted into this change's commits (actor-owned;
  they stay uncommitted in the working tree for their owner). Wave-5 dynamic
  failures in those files/scripts are actor-class, reported not repaired.
  R11 scope note: THIS change's admission batch = 4 mission test files +
  lib/beam4pm_evidence.ex + SHA refresh for the 3 W7 files; the actor's 2
  test files remain their owner's admission debt (gate delta accounting
  must attribute them separately).
- R13 Beam4pm version -> 26.10.1; CHANGELOG entry + release workflow use 26.10.1.
