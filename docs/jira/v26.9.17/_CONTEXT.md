# _CONTEXT.md — v26.9.17 Fortune-5 readiness ticket set (beam4pm)

Read this before any ticket in this directory. Every fact below was observed
on this machine on **2026-09-17** with the named commands; where a repo moved
while being observed, that motion is itself recorded. Nothing here is a
standing claim about any repo — it is the evidence base the tickets gate on.

## Why this ticket set exists

Goal: **beam4pm ready for Fortune 5 customers in `~/xaas`.** Two upstream
siblings carry work that must land first:

- **`~/ferroplan`** owns the planning engine beam4pm hosts in-VM
  (`native/ferroplan`, compiled `wasm32-wasip1`, driven through the
  `fp_alloc`/`fp_call`/`fp_dealloc` JSON ABI by `BeamPM.Ferroplan` and its
  Erlang/Gleam facades). beam4pm already exposes `fond_policy/4` and
  `hddl_solve/4` over it.
- **`~/ash_a2a`** owns the A2A/OCEL agent-protocol loop whose end-to-end
  test produces the real capture files (`qualification/gym_bridge/*.json`)
  that beam4pm's plan-execute-conform closure evidence consumes; beam4pm
  depends on it (`{:ash_a2a, "~> 26.9"}`) and on its `native/hddl_cli`
  Rust binaries.

`~/xaas` integrates with beam4pm **only over the network boundary** (OCEL v2
HTTP forwarding to `ex4pm_web`) — see
`~/xaas/docs/claude/diataxis/explanation/beam4pm-ex4pm-dependency-decision.md`:
no mix dependency is legal until beam4pm has a real release boundary (Hex
publish; package metadata was staged in beam4pm `ace23e5` but no release has
been cut).

## Repo states observed 2026-09-17

### ~/ferroplan (Rust)

- `main @ 6cacbda`, **185 commits ahead of `origin/main @ 1ac9520`** (unpushed).
  The unreleased cycle is the **FOND-HTN line**: native HDDL front-end
  (`crates/ferroplan-hddl`), `solve_hddl`, strong/strong-cyclic FOND policies
  over composite (task-network, state) pairs, WASM ops `hddl_solve` /
  `htn_plan` / `fond_policy` with `FP_PARSE` / `FP_HDDL_GROUND` /
  `FP_HDDL_TRANSLATE` / `FP_MODEL` error codes.
- Wave-6 in flight (`docs/jira/v26.9.17/fond-htn-57..66`), worked in
  `~/ferroplan-worktrees/wt-h*`:
  - **57** (HOTFIX FOUND_BUG_2: strong-cyclic returns witness-first
    goal-unreachable loop policies) — fix ALIVE @ `d00dcf8` on
    `fix/sc-choice-rewrite`, gates green (5000-instance sweep, 0 mismatches,
    carve-out removed) — **not merged to main**.
  - 58 (drop-retry/re-decompose oracle mismatch), 59 (iterative drop),
    60 (grounding prune, PARTIAL_ALIVE), 61 (differential fuzz), 62 (final
    sweep), 63 (docs refresh, ALIVE @ `cd4a7a9`), 64 (ledger close, done),
    65 (TranslateLimits plumbing, PARTIAL_ALIVE), 66 (oracle harvest minimal,
    PARTIAL_ALIVE) — see each ticket's History rows for live state.
- The pin problem: **three divergent pins of the same engine exist** —

  | consumer | pin | position |
  |---|---|---|
  | beam4pm `native/ferroplan` | `4b8ff2e` on `feat/ppcx-hddl-solve-wasm-facade` | 25 ahead / 1 behind its `origin/main`; **commit absent from ~/ferroplan's object store** |
  | autofde-lab wasm registry (`_registry.py`) | `282fae4` | 384 behind ~/ferroplan local main |
  | ~/ferroplan local `main` | `6cacbda` | 185 ahead of origin, unpushed |

  Neither FOND soundness fix (FOUND_BUG_1 on main, FOUND_BUG_2 at `d00dcf8`)
  is reachable from beam4pm's current pin.
- Verdict-flip precedent inside beam4pm itself: `ace23e5` corrected the
  bridge-c oneof test from a **false-positive solve** to the engine's **real
  `NoPlan`/`FP_MODEL` refusal** after a pin bump `29134d7 -> 4b8ff2e`.
- Session-measured preview (2026-09-17, scratch runner at `/tmp/fp-probe`
  against ~/ferroplan main HEAD `6cacbda`): `verify-and-commit` HDDL fixture
  pair → `solved=true`, 6-entry policy; a larger FOND fixture
  (autofde-lab's `sa2a-v26.9.17` pair) → **`NoPlan`** under full
  empty-task-network semantics. Expect verdicts on existing fixtures to move
  again when wave-6 + reconciliation land.

### ~/ash_a2a (Elixir/Ash)

- `main` under **live automation** (HEAD moved `d0cd552 -> 1f06cab` during the
  2026-09-17 observation window); ~69+ commits ahead of `origin/main`,
  unpushed.
- v26.9.17 harden/benchmark/stress pass merged (`fea05cd`, final fix
  `1f06cab`). From its own CHANGELOG:
  - **2 real production defects found, deliberately left unfixed** (flagged
    for the serial MergeVerify/integration phase):
    1. `AshA2A.Semantic.Peer.admit_candidate/2` silently admits non-Turtle
       garbage that parses to zero triples over the real HTTP wire (no
       parse-stage witness, unlike `AdmissionPipeline`).
    2. shipped `test/support/command_worker.ex` never calls
       `ObanAuthority.verify_live!/3` — a revoked-but-unexpired authority
       still actuates through it.
  - **7 of 10 RFC-SA2A-002 benchmark categories have new modules not yet
    wired** into `Bench.@benchmarks` / the mix task (B2 B3 B4 B6 B7 B8 B10).
  - Stress findings: `CommandBus.run/4` tail-latency climbs under load
    (late-half p99 up to 181x early-half p99, 34,881 dispatches, 0 errors);
    **`HddlSolver` cross-VM temp-file collision** (multinode, 6 `:peer`
    nodes); `RouterCounters` telemetry cross-contamination between
    concurrent instances; 1-2 flaky failures across runs
    (`SemanticRefusalTest` `:hddl_solve_error` mapping; `:eaddrinuse`
    port-bind race).
- `native/hddl_cli` Rust binaries must be built locally (`cargo build
  --release --locked`) before `mix test` works in a fresh checkout.
- The ash_a2a-side end-to-end test (real HDDL plan -> real A2A dispatch ->
  real HTTP POST to beam4pm's `BeamPM.OcelIngest.Router`) is the **only
  producer** of the `qualification/gym_bridge/*.json` captures beam4pm's
  closure evidence reads (per beam4pm `ontology.ttl` admission facts, which
  honestly skip when the captures are absent).

### ~/beam4pm (this repo)

- `main @ 22fa4aa` (pushed); `ace23e5` staged Hex package metadata and bumped
  the ferroplan submodule to the divergent ppcx pin; mix version `26.9.12`.
- Facades `BeamPM.Ferroplan` / `beam4pm_ferroplan` / `beam4pm/ferroplan` are
  **ggen-generated from `bpm:Engine` / `bpm:EngineOp` / `bpm:EngineArg`
  ontology facts** — engine-surface changes are ontology changes, never
  hand-edits.
- Working tree carries a concurrent session's uncommitted changes
  (`ontology.ttl`, `ggen.lock`, `docs/reference/beam4pm_hand_authored_source.md`,
  `qualification/gym_bridge/*.json`) — serialize; never stage another
  session's paths.
- Family cleanup state: `cleanup-merge-plan.md` in this directory (same day)
  records the four-copy consolidation, the pushed `main`, the preserved
  `review/ws2-docs-types-cleanup-20260917` branch, and the unresolved
  `beam4pm_ws2` vendor submodule mass-deletion. Its open items are
  prerequisites for release hygiene but are owned by that plan, not
  re-ticketed here.

### ~/xaas (the customer surface)

- Integrates beam4pm **only via OCEL v2 HTTP** (`Xaas.Telemetry.OcelForwarder`
  -> `ex4pm_web`); no mix dep is legal without a beam4pm release boundary.
- Owns the Fortune-5 deployment blocks (ggen-generated
  `docs/FORTUNE5_DEPLOYMENT_BLOCKS_CATALOG.md`, catalog `26.7.31`) and its
  v26.9.17 lease/actuation wave (`15c287a`).

## Standing law for this ticket set

- Tickets are `oslc_cm:ChangeRequest` dual-typed `earl:TestRequirement`;
  append-only History; `ALIVE` only for observed execution against the exact
  admitted subject in the working session.
- Upstream landings are **not** beam4pm work, but every ticket here carries a
  beam4pm-side verification gate so that "landed" means "consumed and
  verified here", not "pushed somewhere else".
- Evidence vocabulary: `UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED |
  BUILD_BROKEN | UNSUPPORTED` + typed `REFUSED_*`.
- No fabricated evidence, no weakened tests, no acceptance mocks. Where a
  gate needs the ash_a2a side to run first, say so and order the tickets.
