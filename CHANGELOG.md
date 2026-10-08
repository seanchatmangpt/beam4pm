# Changelog

All notable changes to beam4pm are documented in this file.

## [Unreleased]

### Added

- Realtime Ash-action OCEL 2.0 capture: closes the v26.10.1 R5 gap where
  `AshEx4pm.Notifier` ingested envelopes into `Ex4pm.Evidence.Store` with no
  push seam to beam4pm's `BeamPM.Ingest.Bridge`. Upstream, `AshEx4pm.Notifier`
  now threads `Application.get_env(:ash_ex4pm, :broadcaster)` into
  `Ex4pm.Stream.Ingest.ingest_envelope/2`'s existing optional `:broadcaster`
  callback (`ex4pm` ingest.ex:129-137). App-side, `scripts/ex4pm_bridge.exs`
  defines `BeamPM.Evidence.Ex4pmBridge` (see
  `docs/ex4pm-realtime-capture.md`): maps each broadcast envelope to a
  `%BeamPM.Types.OcelEvent{}` and forwards it through
  `BeamPM.Ingest.Bridge.ingest/1`, emitting a
  `[:beam4pm, :ex4pm, :envelope, :ingested]` telemetry event per forwarded
  envelope. Attach via `Application.put_env(:ash_ex4pm, :broadcaster, ...)`
  or `BeamPM.Evidence.Ex4pmBridge.attach/0`.
- Caveat (hex consumers): the automatic notifier-driven path requires the
  NEXT `ash_ex4pm` release — the released 26.10.1 notifier passes no
  broadcaster (the bridge itself and its tests run against released hex
  26.10.1 by passing the broadcaster explicitly). This branch keeps the hex
  dep `{:ash_ex4pm, "~> 26.10"}`; dogfooding the unreleased upstream
  notifier change uses a LOCAL, UNCOMMITTED `path: "../ash_ex4pm"` override
  that is not part of this change (release path: upstream publish → bump
  the pin).
- `lib/beam4pm_evidence.ex` moduledoc now carries the division-of-labor
  paragraph (AshEx4pm.Notifier owns Ash-action emission into
  `Ex4pm.Evidence.Store`; `BeamPM.Evidence`'s bridges stay authoritative for
  the engine-telemetry family), including the forward seam naming for the
  bridge above once the upstream broadcaster ships.

## [26.10.8] - 2026-10-08

### Changed

- Version bump to 26.10.8 (fleet campaign).

## [26.10.1] - 2026-10-01

### Added

- `{:ash_ex4pm, "~> 26.10"}` dependency (hex `ash_ex4pm` 26.10.1, which transitively pins `ex4pm == 26.10.1`); brings ~19 new `mix.lock` entries (`phoenix_live_view`, `ash_admin`, `broadway`, `explorer`, among others). No dependency was removed and the `ash_a2a` pin is unchanged.
- Ash-native OCEL evidence wiring (law side): the beam4pm-process-model-pack resource template now renders `extensions: [AshEx4pm]` plus an `ex4pm do object_type ..., attributes: [...]; activity :<name>_created, on: :create end`, projected from the new `bpm:ocelTypeExpr` ladder in the pack ontology (map-typed attributes are skipped with a rendered comment in the generated file, never silently). The projection re-render itself is BLOCKED by a pre-existing ggen_igniter reconciliation deadlock (677 admitted `bpm:RecordType` rows vs 647 rendered files; per-actuation `mix compile --warnings-as-errors` verify + rollback) — see `docs/jira/v26.10.1/RESOLUTIONS.md` R14; the rendered wiring lands with the next successful Ash-leg regeneration.
- `config :ex4pm, wasm_host: false` in `config/config.exs`: beam4pm's `BeamPM.EngineSupervisor` stays the only wasm host, while `Ex4pm.Evidence.Store` (the emission sink) still auto-starts under `:ex4pm`'s own application module.

### Changed

- Version bump to 26.10.1.
- Ash change emission (package capability; beam4pm's generated-resource wiring dormant until the R14 deadlock clears): emission is post-commit and fire-and-forget — `AshEx4pm.Notifier` (auto-registered by `AshEx4pm.Transformers.Persist` from `extensions: [AshEx4pm]` alone) hands each envelope to `Ex4pm.Stream.Ingest.ingest_envelope/1` → `Ex4pm.Evidence.Store`; refusals are logged and never block the committing change. The store's aliveness, ingest/dedup/refusal behavior, and the BRCE gate contract (`AshEx4pm.Changes.BrceGate` over `Ex4pm.Evidence.BRCE.execute/4`) are pinned by tests. No resource is BRCE-gated in this release — flagging resources is a follow-up.

## [26.9.30] - 2026-09-30

### Changed

- Version bump to 26.9.30 (Hex dry-run publish readiness); package files now include `native/graphlaw` (wasm + `.sha256` pin).

## [26.9.28] - 2026-09-28

### Added

- Fail-closed plan admission by default: `config :beam4pm, :admission_mode` defaults to `:required` — unadmitted plans are refused `{:error, {:admission_missing, _}}`; per-call opt-outs are `admission: :skip`, `graphlaw_court: false`, `graphlaw_gate: false` (commits `2a437a7e`, `82438aee`).
- Wasm engines supervised under `BeamPM.EngineSupervisor`: started only when the artifact exists, the sha256 pin (`native/graphlaw/graphlaw_wasm.wasm.sha256`) verifies, and the engine's `capabilities` reports the expected `abi_version` (ABI handshake).
- `BeamPM.ActionModel.from_pddl/2`: derives a plan-admission spec from PDDL domain/problem text (STRIPS + typing); negated plain atoms are admitted via `pre_not`/`goal_not` — previously typed `{:error, {:unsupported, _}}` (commit `6955b894`).
- `BeamPM.GraphlawAdmission.admit_policy/3` and `BeamPM.ReplanRouter.load_policy/4`: independent strong-cyclic FOND policy admission via the graphlaw court; `load_policy/4` runs the court by default in `:required` mode.
- `BeamPM.Dfcm.allocate_options/2` now delegates cascade allocation to the external certified `cmca` CLI (`autofde cmca allocate`); a CLI refusal returns a refused map with reason `{:cmca_allocate_failed, detail}` instead of silently substituting the uniform fallback (commit `0f304857`).
- `Beam4PM.CastleCapabilityIntake`: runtime-readable CASTLE capability donor registry (EX4PM admitted only as a process-execution kernel behind PROCESS_COORDINATION ownership); authority ceiling `:construct`, no actuation path (commit `cf418a79`).
- `scripts/graphlaw_wasm_fetch.sh`: installs a checksum-verified `graphlaw.wasm` release asset (or `--from` a local build) and writes the sha256 pin; exit 2 when the release asset is missing.

## [26.9.10] - 2026-09-10

### Integrated

- Merged `feat/ocel-evidence-architecture` into `release/v26.9.10` off `main`
  (this merge transitively subsumed `integration/htn-fond-hddl`,
  `feat/ferroplan-hddl`, and `feat/htn-fond-dispatch`, all already ancestors
  of it — one clean, conflict-free merge).
- HTN/FOND dispatch (`htn_plan`/`fond_policy`) and ferroplan HDDL/FOND
  planning work.
- OCEL v2 evidence architecture: all 79 native-engine ops across the four
  engine facades (`petgraph`, `tract`, `rust4pm`, `ferroplan`) are
  telemetry-hooked (GATE EVIDENCE COVERAGE: 79/79, 0 findings). Of those 79
  hooked ops, 4 are exercised end-to-end by a real running test this pass
  (the `rust4pm.ocel_new` evidence-chain path plus its sibling checks) — full
  end-to-end exercise of the remaining ops is a disclosed follow-up, not
  claimed complete here.
- `vendor/ggen-marketplace` submodule advanced to the release marketplace
  commit plus one required follow-up: a reviewed ceiling raise
  (`AuthorshipKind_hand_authored_qualification`, 27 -> 30) needed because the
  merged work legitimately added 3 new admitted hand-authored qualification
  files.
- Fixed a real gap in `ggen-verify-pack`'s materialization: `ggen sync run`
  (no `--dry-run`) now completes cleanly, producing `VERIFICATION.md`,
  `scripts/verify-evidence.sh`, `scripts/produce-*.sh`, and
  `receipts/EVIDENCE_NOTE.md` for the first time in this consumer. Getting
  there required resolving real `FM-WRITE-005` silent-clobber refusals and
  `evidence_fresh`/`output_count_regression` gate trips by deleting stale
  generated files, re-emitting real `ver:Check` evidence bound to the new
  graph hash, and disclosing three `ver:AcceptedShrink` facts against the
  specific crashed/partial receipts — no ceiling or force-flag was used to
  route around a check.
- Fixed `scripts/gate_evidence_coverage_check.sh`'s static-grep pattern to
  recognize both the old per-op literal-atom `:telemetry.execute` call shape
  and the marketplace-merged template's new generic per-engine-op shape
  (semantically equivalent at runtime, different static text).

### Verified this pass

- GATE AUTHORSHIP, GATE ENGINE DISPATCH, GATE EVIDENCE COVERAGE, GATE
  LINT-TRUTH: all real-run PASS, 0 findings.
- `rebar3 eunit`: 3100/3100 passing (run twice against the fully materialized
  tree).
- `mix test`: 1073 tests, 11 failures, 57 skipped — matching the documented
  pre-existing RF2/RF3-oracle-environment baseline exactly; zero new
  regressions in the final state.

### Known open item

- GATE M2 (the destructive delete-regenerate-diff determinism check) was run
  once this pass and its own regenerate-step `mix test` run hit an async OTel
  span-export timing assertion
  (`BeamPM.EvidenceChainTest` `rust4pm.ocel_new ...`) before reaching any
  content-diff comparison. Its EXIT-trap safety net restored the pre-delete
  backup, so the working tree was unaffected, but GATE M2 has **not** yet
  confirmed byte-identical determinism for this state and should be re-run
  independently (it is destructive and outside `just verify`).
