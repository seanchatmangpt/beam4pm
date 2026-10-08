# Script-local modules reference (reference)

beam4pm ships hand-authored capability scripts under `scripts/` that
define modules at runtime via `Code.require_file/1` — they are not part of
the compiled `:beam4pm` application and are only available after the
defining script is loaded. The doctrine behind this placement is explained
in `../explanation/why-the-ingest-bridges-live-in-scripts.md`; this page is
the index.

## The two ingest bridges

Covered in full API detail in `ingest-and-bridge-api.md` (same directory):

- `BeamPM.Ingest.Bridge` — `scripts/ingest_telemetry.exs`
  (`:telemetry` -> bounded ETS OCEL buffer)
- `BeamPM.Evidence.Ex4pmBridge` — `scripts/ex4pm_bridge.exs`
  (ash_ex4pm broadcaster -> same buffer)

## Other script-local modules

Verified by scanning `defmodule` lines across `scripts/*.exs`:

| module | script | purpose |
|---|---|---|
| `Beam4PM.Dogfood.Capture` | `dogfood_selfmine.exs` | dogfood self-mining capture |
| `Beam4PM.EcosystemMine` | `ecosystem_process_mine.exs` | ecosystem self-mining |
| `Beam4PM.DiscoverReport` | `discover_report.exs` | discovery report generation |
| `Beam4PM.Script.ActuationSelfmine` | `actuation_selfmine.exs` | actuation self-mining |
| `BeamPM.Gall.Observer004` | `gall_checkpoint_004_observer.exs` | gall checkpoint observer |
| `BeamPM.Soak.Ex4pmSoak` | `ex4pm_soak.exs` | realtime ingest soak runner |
| `GallCrown` | `gall_crown_run.exs` | gall crown run driver |
| `BeamPM.Gall.ProcessIntelligence` | `gall_process_intelligence_024_028.exs` | gall process intelligence |
| `Check` | `ingest_telemetry_check.exs` | ingest self-test (real telemetry, real assertions) |
| `BeamPM.GallSemanticWorkObserver` | `gall_semantic_work_observer.exs` | semantic work observer |
| `Beam4PM.OfflineBundleCheck` | `offline_bundle_check.exs` | offline bundle check |
| `B4pm1704.RenameFunctionPreflightGuard` | `rename_function_preflight_guard.exs` | rename preflight |
| `Die` | `rust4pm_ocel_examples_wasm.exs` | rust4pm WASM example driver |
| `PM4PyExamplesWasm` | `pm4py_examples_wasm.exs` | pm4py WASM example driver |
| `Beam4PM.RevenueSuiteDemo` | `revenue_suite_demo.exs` | revenue suite demo |

## Conventions

- Script modules are hand-authored orchestration over already-generated
  capital; they carry no `bpm:HandAuthoredSource` admission and trip no
  authorship gate (`scripts/gate_authorship_check.sh` scopes `lib/`).
- Bridge callers use `apply(BeamPM.Ingest.Bridge, :ingest, [event])` or
  ensure-load first (`ensure_loaded/0`/`ensure_ingest_bridge_loaded/0`) —
  a direct call would emit an undefined-module compile warning
  (`../explanation/why-the-ingest-bridges-live-in-scripts.md`, "The
  composition shape" section).

See Also: `docs/diataxis/reference/ingest-and-bridge-api.md` ·
`docs/diataxis/explanation/why-the-ingest-bridges-live-in-scripts.md`
