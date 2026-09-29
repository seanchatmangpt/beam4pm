# OP-DIFF — admitted `bpm:EngineOp` set vs reconciled ferroplan WASM ABI

Ticket: `docs/jira/v26.9.17/b4p-f5-07-engine-ontology-refresh-and-facade-rerender.md`, scope item 1 (diff only; admission is item 2-as-draft, render is items 3-4 — remaining, post-bump of b4p-f5-05).

## Evidence bases (both sides)

| side | subject | exact source |
|---|---|---|
| ADMITTED | `bap:engine_ferroplan` facts, 33 ops | `ontology.ttl` (worktree, `chore/engineop-ferroplan-prep` @ beam4pm main 22fa4aa) lines 11374–11697; admitted at `ace23e5` against ferroplan submodule pin `4b8ff2e` |
| ADMITTED cross-check | ggen render (faithful projection) | `lib/beam4pm_ferroplan.ex` — 33 op functions, 1:1 with ontology (plan @188 … hddl_solve @734); same op docs verbatim |
| ENGINE (reconciled) | wasip1 ABI @ `~/ferroplan` main `6cacbda` | `crates/ferroplan-wasm/src/wasi_abi.rs` (1736 lines; dispatch arms @299–340) |
| ENGINE (fix line) | `wt-h57` `fix/sc-choice-rewrite` @ `d00dcf8` | `git diff 6cacbda d00dcf8 -- crates/ferroplan-wasm/` is **empty** — the FOUND_BUG_2 fix touches `crates/ferroplan/src/planning_runtime.rs` (+137) and tests only; **zero ABI delta**. One reconciled ABI surface: `6cacbda`. |
| ENGINE (current pin, for drift attribution) | submodule @ `4b8ff2e` | `/Users/sac/beam4pm/native/ferroplan/crates/ferroplan-wasm/src/wasi_abi.rs` (read-only) |

## Headline

- **Ops: 0 new, 0 removed, 33 unchanged.** The dispatch table at `6cacbda` (`wasi_abi.rs:299–340`) is name-identical to the admitted set. The ticket's anticipated new ops (`hddl_solve`, `htn_plan`, `fond_policy`) are **already admitted** — `ace23e5` added them with submodule pin `4b8ff2e`, and all three dispatch arms exist at that pin too.
- **Error vocabulary: 1 new code, 2 renamed codes** (pin → `6cacbda`), and the admitted `hddl_solve` opDoc's stage list is stale against both pins on reachability.
- **Limits: 1 admitted-set gap** — `PlannerLimits.max_wall_ms` exists at *both* pins (not pin drift) but was never admitted into the three `limits` args' docs; its watchdog semantics are load-bearing for the wasmex-hosted never-block-past-budget property.
- Arg names/orders/types, request/response shapes, defaults, handle semantics: unchanged pin → `6cacbda` (the only wasi_abi.rs deltas are the `hddl_error_json` mapping, its module doc, and tests).

## The ticket table — op | admitted? | engine? | disposition

Admitted side: `ontology.ttl` (this worktree); engine side: `wasi_abi.rs` @ `6cacbda`. Order = `bpm:opOrder`.

| # | op | admitted? | engine? | disposition | evidence (admitted | engine) |
|---|---|---|---|---|---|
| 1 | `plan` | yes | yes | UNCHANGED — args domain/problem/extra(merge_map, default `%{}`); engine's `mode`/`flags`/`search` optionals already documented in opDoc | `ontology.ttl:11392–11403` | `wasi_abi.rs:17–18, 344–361` |
| 2 | `plan_production` | yes | yes | UNCHANGED — strict mode/search; `max_evaluated`/`max_plan_steps`/`max_output_bytes`/`request_id`; `OperationEnvelope`; refusal envelope `FP_INVALID_REQUEST` | `ontology.ttl:11405–11416` | `wasi_abi.rs:19–21, 363–410, 452–468` |
| 3 | `readiness` | yes | yes | UNCHANGED — capability manifest + fingerprint (response now `schema_version`/`manifest_fingerprint`/…; doc-level, no fact change) | `ontology.ttl:11418–11421` | `wasi_abi.rs:39, 546–560` |
| 4 | `version` | yes | yes | UNCHANGED | `ontology.ttl:11423–11426` | `wasi_abi.rs:40, 306` |
| 5 | `explain` | yes | yes | UNCHANGED — plan as decoded map; failures → `FP_VALIDATION` envelope | `ontology.ttl:11428–11437` | `wasi_abi.rs:41–42, 562–574` |
| 6 | `session_new` | yes | yes | UNCHANGED shape — note (unadmitted, both pins): domain/problem bounded ≤4 MiB, over-bound → `FP_ADAPTER` envelope | `ontology.ttl:11439–11446` | `wasi_abi.rs:43, 584–609`; `readiness.rs:705–735` (`ProductionLimits::default`) |
| 7 | `session_fork` | yes | yes | UNCHANGED | `ontology.ttl:11448–11453` | `wasi_abi.rs:44, 611–620` |
| 8 | `session_free` | yes | yes | UNCHANGED — `{freed:true}`; unknown handle → `FP_ADAPTER` envelope | `ontology.ttl:11455–11460` | `wasi_abi.rs:45, 622–635` |
| 9 | `session_set_goal` | yes | yes | UNCHANGED | `ontology.ttl:11462–11469` | `wasi_abi.rs:46, 637–643` |
| 10 | `session_restrict_prefix_claims` | yes | yes | UNCHANGED | `ontology.ttl:11471–11480` | `wasi_abi.rs:47, 645–665` |
| 11 | `session_restrict_contains` | yes | yes | UNCHANGED | `ontology.ttl:11482–11489` | `wasi_abi.rs:48, 667–675` |
| 12 | `session_think` | yes | yes | DOC GAP (both pins, not drift): engine enforces `evals ∈ 1..=1_000_000` → `FP_LIMIT_SEARCH`, `mem_mb ∈ 1..=2_048` → `FP_LIMIT_MEMORY` envelopes; admitted opDoc says only "bounded by evals/memory" | `ontology.ttl:11491–11500` | `wasi_abi.rs:49, 100–101, 677–698` |
| 13 | `session_valid` | yes | yes | UNCHANGED (Elixir `session_valid?`) | `ontology.ttl:11502–11508` | `wasi_abi.rs:50, 708–716` |
| 14 | `session_step` | yes | yes | UNCHANGED | `ontology.ttl:11510–11515` | `wasi_abi.rs:51, 718–726` |
| 15 | `session_suffix` | yes | yes | UNCHANGED | `ontology.ttl:11517–11522` | `wasi_abi.rs:52, 728–737` |
| 16 | `session_advance` | yes | yes | UNCHANGED | `ontology.ttl:11524–11529` | `wasi_abi.rs:53, 739–745` |
| 17 | `session_drop_plan` | yes | yes | UNCHANGED | `ontology.ttl:11531–11536` | `wasi_abi.rs:54, 747–754` |
| 18 | `session_has_plan` | yes | yes | UNCHANGED (Elixir `session_has_plan?`) | `ontology.ttl:11538–11544` | `wasi_abi.rs:55, 756–760` |
| 19 | `session_set_fact` | yes | yes | UNCHANGED | `ontology.ttl:11546–11555` | `wasi_abi.rs:56, 762–772` |
| 20 | `session_set_timed_fact` | yes | yes | UNCHANGED | `ontology.ttl:11557–11568` | `wasi_abi.rs:57, 774–789` |
| 21 | `session_observe` | yes | yes | UNCHANGED — pair-list sight; ≤100k facts (over → dispatch-level `FP_ADAPTER` envelope) | `ontology.ttl:11570–11578` | `wasi_abi.rs:58, 791–807` |
| 22 | `session_goal_met` | yes | yes | UNCHANGED (Elixir `session_goal_met?`) | `ontology.ttl:11580–11586` | `wasi_abi.rs:59, 809–813` |
| 23 | `session_fact` | yes | yes | UNCHANGED — `bool \| null` | `ontology.ttl:11588–11595` | `wasi_abi.rs:60, 815–823` |
| 24 | `session_apply_start` | yes | yes | UNCHANGED | `ontology.ttl:11597–11604` | `wasi_abi.rs:61, 825–831` |
| 25 | `session_elapse` | yes | yes | UNCHANGED | `ontology.ttl:11606–11613` | `wasi_abi.rs:62, 833–841` |
| 26 | `session_set_fluent` | yes | yes | UNCHANGED | `ontology.ttl:11615–11624` | `wasi_abi.rs:63, 843–853` |
| 27 | `session_fluent` | yes | yes | UNCHANGED — `f64 \| null` | `ontology.ttl:11626–11633` | `wasi_abi.rs:64, 855–863` |
| 28 | `session_plan_valid` | yes | yes | UNCHANGED (Elixir `session_plan_valid?`) | `ontology.ttl:11635–11645` | `wasi_abi.rs:65, 865–884` |
| 29 | `session_world_bytes` | yes | yes | UNCHANGED | `ontology.ttl:11647–11652` | `wasi_abi.rs:66, 886–890` |
| 30 | `session_mind_bytes` | yes | yes | UNCHANGED | `ontology.ttl:11654–11659` | `wasi_abi.rs:67, 892–896` |
| 31 | `htn_plan` | yes | yes | **CHANGED (admit)** — `limits` gains `max_wall_ms` (u64 ms, serde-default 10 000, 0 = unbounded). Watchdog semantics: **inert here** — `Hierarchical` never calls `check_wall_deadline`; only structural bounds (`max_depth`/`max_states`) apply | `ontology.ttl:11661–11672` | `wasi_abi.rs:22–24, 412–450`; `planning_runtime.rs:190–191, 199–249` @6cacbda (identical @4b8ff2e:171–206); call sites `planning_runtime.rs:824,954,988,1040,1051` (fond only) |
| 32 | `fond_policy` | yes | yes | **CHANGED (admit)** — `limits.max_wall_ms` **honored cooperatively**: `check_wall_deadline` per fixpoint round in `fond_policy`/`fond_policy_strong_cyclic`; overrun → `PlannerError::Timeout` → `FP_ADAPTER` envelope via `solve_universal` (never `FP_TIMEOUT` through this op). Strong→strong-cyclic fallback already existed at the pin (no drift) | `ontology.ttl:11674–11685` | `wasi_abi.rs:25–26, 426–450`; `planning_runtime.rs:254–266, 402–444, 824…1051`; pin fallback @`4b8ff2e/planning_runtime.rs:380` |
| 33 | `hddl_solve` | yes | yes | **CHANGED (admit)** — see detail below: new code `FP_HDDL_ROOT_MISMATCH`; renames `FP_HDDL_TIMEOUT`→`FP_TIMEOUT`, `FP_HDDL_WORKER_PANIC`→`FP_WORKER_PANICKED`; adapter **forces `limits.max_wall_ms = 0`** (wasi1 has no threads — `thread::spawn` would trap); BEAM caller's wasmex call timeout (heavy class = 120 000 ms) is the only wall bound → never-block-past-budget; `timeout/worker-panic` stages unreachable through this ABI | `ontology.ttl:11687–11697` | `wasi_abi.rs:27–38, 476–511, 517–544`; pin @`4b8ff2e/wasi_abi.rs:36–38, 532–537` (force predates: `4b8ff2e/wasi_abi.rs:485–506`) |

## Error-envelope vocabulary (`bpm:ErrorCollapse_single_key_inspect`, `ontology.ttl:11390`)

Every failure is `{"error":{"code","message","retryable"}}` inside an `Ok` response (`wasi_abi.rs:8–14, 211–213`) — the admitted convention, unchanged.

| code | engine @6cacbda | engine @4b8ff2e (pin) | admitted? | disposition |
|---|---|---|---|---|
| `FP_PARSE` | `wasi_abi.rs:519` | same | yes (hddl_solve opDoc) | keep |
| `FP_HDDL_GROUND` | `wasi_abi.rs:520–522` | same | yes | keep |
| `FP_HDDL_TRANSLATE` | `wasi_abi.rs:523–526` | same | yes | keep |
| `FP_HDDL_ROOT_MISMATCH` | `wasi_abi.rs:527–530` (new `HddlError::RootTaskMismatch`) | **absent** | **no** | **ADMIT** — new code, pin→6cacbda drift |
| `FP_MODEL` | `wasi_abi.rs:531` | same | yes | keep |
| `FP_TIMEOUT` | `wasi_abi.rs:532–538` | `FP_HDDL_TIMEOUT` (`4b8ff2e:532`) | no | RENAME recorded; **unreachable via this ABI** (watchdog thread disabled, `wasi_abi.rs:493–506`) — admit as inert-at-ABI, not as a live hddl_solve outcome |
| `FP_WORKER_PANICKED` | `wasi_abi.rs:539–542` | `FP_HDDL_WORKER_PANIC` (`4b8ff2e:536`) | no | RENAME recorded; unreachable via this ABI, same reason |
| `FP_ADAPTER` | `wasi_abi.rs:197–201, 359, 448` | same | no | generic adapter-fault envelope (dispatch `Err` collapse; unknown handle; over-bound inputs; universal-solver `PlannerError` incl. `Timeout`) — candidate prose in opDocs, no per-op fact |
| `FP_UNKNOWN_OP` | `wasi_abi.rs:333–339` | same | no | engine-level, unchanged |
| `FP_LIMIT_INPUT` | `wasi_abi.rs:286–292` (request >16 MiB) | same | no | engine-level, unchanged |
| `FP_INVALID_REQUEST` | `wasi_abi.rs:452–468` (plan_production strict refusal); `readiness.rs:743–760` validate | same | no | already implied by plan_production opDoc ("strict-mode refusal … `{:ok, envelope}`") |
| `FP_INVARIANT` | `wasi_abi.rs:558` | same | no | readiness fingerprint failure |
| `FP_VALIDATION` | `wasi_abi.rs:572` | same | no | explain failure |
| `FP_LIMIT_SEARCH` | `wasi_abi.rs:687–692` | same | no | session_think evals cap — admit in opDoc (doc gap) |
| `FP_LIMIT_MEMORY` | `wasi_abi.rs:693–698` | same | no | session_think mem_mb cap — admit in opDoc (doc gap) |

## PlannerLimits (the `limits` arg payload for ops 31–33)

Engine @6cacbda `planning_runtime.rs:199–249` — **field-identical at pin `4b8ff2e:171–215`** (so this whole block is an admitted-set gap, not pin drift). All fields serde-default; partial maps admitted correctly; unknown keys ignored.

| field | type | default | semantics |
|---|---|---|---|
| `max_depth` | usize | 128 | belief-search depth bound |
| `max_states` | usize | 100_000 | state-space bound; also `states+1` round failsafe on FOND fixpoints |
| `max_iterations` | usize | 512 | round cap for the one iteration-gated loop (`probabilistic_policy` value iteration); advisory for FOND fixpoints (`planning_runtime.rs:181–188`) |
| `max_wall_ms` | u64 | 10_000 (`planning_runtime.rs:203–205, 231–240`) | wall-clock budget; **0 = unbounded**. Watchdog = cooperative `check_wall_deadline` at fixpoint-round boundaries in `fond_policy`/`fond_policy_strong_cyclic` ONLY (`planning_runtime.rs:253–266`; call sites 824/954/988/1040/1051 — `htn_plan`'s `hierarchical_plan` and `hddl_solve`'s inner solve never consult it). On the WASI side `hddl_solve` **forces 0** (`wasi_abi.rs:493–506`), so the effective, admitted wall bound for `hddl_solve` is the BEAM caller's wasmex call timeout (`bpm:opTimeoutClass heavy` → `bpm:heavyTimeoutMs 120000`, `ontology.ttl:11389`) — the never-block-past-budget property. |

## Verdict

- Ticket scope-item-1 gate satisfiable **now**: diff table above is complete, every row cites both sides.
- Admission (scope item 2) = 3 opDoc revisions + 1 shared-limits semantics note (drafted in `ONTOLOGY-DELTA-proposal.ttl`); **zero** new/removed `bpm:EngineOp` individuals, **zero** arg-shape changes.
- Render (items 3–4) must wait for the b4p-f5-05 pin bump; verdicts on existing fixtures may move at that point (context: FOUND_BUG_1/2 not reachable from `4b8ff2e`; `d00dcf8` changes `planning_runtime.rs` behavior behind the unchanged ABI).
