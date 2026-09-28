# v26.9.28 — integration release requirements

Cut 2026-09-28 from the observed state of `origin/*` (85 remote branches) merged into one
integration head. Standing: `PARTIAL_ALIVE` — the merge is done and pushed; the gates listed
under R1 are RED on this head, and nothing here claims otherwise. Toolchain note: this cut was
made in a container with ggen 26.8.28 and OTP 25 only, so `mix test`/`rebar3 eunit` were not run.

## Evidence base (observed on the integration head)

| Gate | Result | Note |
|---|---|---|
| `gate_lint_truth.sh` | PASS | 110 files, 0 findings |
| `gate_engine_dispatch_check.sh` | PASS | 44 wire ops, 0 findings (1 engine blocked on absent sources) |
| `gate_authorship_check.sh` | **FAIL** | 124 findings: 121 `REFUSED_UNADMITTED`, 2 `REFUSED_MANIFEST_MALFORMED`, 1 `REFUSED_SHA_DRIFT` |
| `gate_m2_check.sh`, `roundtrip_check.sh`, `mix test`, `rebar3 eunit` | NOT RUN | need ggen sync + OTP 28 / Elixir 1.19 |

The 121 unadmitted files are the hand-authored v26.9.28 runtime landed by the
`runtime/v26.9.28-*` branches: `lib/beam_pm/research_runtime/*` (42) and
`lib/beam_pm/ferroplan_bridge/*` (39) with their tests (29), plus eight top-level
`lib/beam4pm_{economic_isa,frontier_evidence,ppcx_production_boundary}` sources and tests. None of
those branches touched `ontology.ttl`.

## Requirements

**R1 — Source-authority closure (blocking).** Every unmarked file under a manufactured root is
either manufactured by ggen from `ontology.ttl` + pack templates, or admitted as a
`bpm:HandAuthoredSource` (path, kind, principal, reason, acceptance command, sha256, expiry,
sunset plan). Additionally: `schema/beam4pm_hand_authored_source.tsv` carries merge damage at
`lib/beam4pm_ocel.ex` / `test/beam4pm_ocel_test.exs` (two rows text-merged); it is GENERATED and
must be repaired only by `rm -f ggen.lock && ggen sync run`. Acceptance:
`bash scripts/gate_authorship_check.sh --exercise` PASS.
*Constraint discovered:* admitting the 121 files as debt exceeds the pack's per-kind ceilings
(`hand_authored_qualification` 50 with 41 admitted; `native_engine_facade` 7 with 7 admitted), and
ceilings live in the vendored pack, so this needs either a pack release that raises them / adds a
lib-module kind, or template manufacture of the runtime families.

**R2 — Branch disposition is recorded and honest.** Merged: 34 branches (all dependency,
runtime, release, legacy-court, equilibrium-kernel, closed-loop, celonis-court, GALL 024-028 and
checkpoint-004 lines). Not merged, with cause: `dependabot/hex/ash*` (mix.lock conflict —
superseded by `fix/v26926-main-ash-resolution`; re-resolve with `mix deps.update`),
`fix/ws2-dfcm-scheduled-recovery` (workflow conflict), pre-v26.9.18 branches that conflict on
`ggen.lock`, `ontology.ttl`, `native/ferroplan`, `vendor/ggen-marketplace` pins
(`codex/dfcm-fond-hddl`, `feat/htn-fond-dispatch`, `feat/errc-closure`, `feat/fortune5-*`,
`release/v26.9.10`, `integration/htn-fond-hddl`, `feat/ocel-evidence-architecture`,
`feat/ash-a2a-agent-facing`, `feat/frontier-release-process-contract`,
`feat/planning-closure-validator-projections`), doc-only stale lines (`review/ws2-docs-types-cleanup`,
`automation/post-llm-governed-runtime`, `gall/v26.9.18-final-specs`, `backup/*`). Each needs an
owner decision: rebase forward or retire.

**R3 — Release court.** `.github/workflows/release-v26.9.28.yml` (hourly re-evaluation, exact
`ggen_igniter`/`ash_a2a` 26.9.28 upstream resolution) is kept from the integration head over the
older release-branch copy. Acceptance: workflow green on the exact head; version aligned in
`mix.exs` and `src/beam4pm.app.src` (26.9.28, already true).

**R4 — GALL 024-028 process-intelligence courts execute.** `scripts/gall_process_intelligence_024_028.exs`
and `.github/workflows/gall-004-independent-observer.yml` run on the head with receipts under
`docs/jira/v26.9.28/receipts/`. Acceptance: receipts exist with `subject_sha` = head.

**R5 — Determinism and wire identity.** After R1's regeneration: `gate_m2_check.sh` and
`roundtrip_check.sh` PASS, then full `just verify`, `mix test`, `rebar3 eunit` on OTP 28 /
Elixir 1.19.

**R6 — Standing truth.** `docs/jira/README.md` lists this program at `PARTIAL_ALIVE`; promote only
when R1-R5 receipts exist. `gate_lint_truth.sh` stays green.
