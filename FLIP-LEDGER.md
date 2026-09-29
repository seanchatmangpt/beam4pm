# FLIP-LEDGER.md — b4p-f5-06 scope 1 + 3 (pre-bump build)

Branch `chore/ferroplan-verdict-flip-audit` @ beam4pm `22fa4aa`.
Built against the **current** submodule pin `4b8ff2e` (the reconciled bump of
b4p-f5-05 has NOT happened). Purpose: make the post-bump verdict-flip audit
**mechanical** — every expectation that carries an engine verdict is
enumerated, classified against the wave-6 hardened engine
(~/ferroplan main @ `6cacbda`), and where the risk class demanded it,
**measured** with real runs. "No flip" is a row. Empty rows forbidden.

## 0. Method + recorded bounds (柵: explicit truncation evidence)

- **Scanned**: `test/`, `lib/`, `qualification/`, `research/`, `receipts/`,
  `docs/`, `contracts/`, `ontology/` of beam4pm @ `22fa4aa`.
- **Patterns**: pass 1 `-E "solved|NoPlan|FP_[A-Z]+"` (98 raw hits across
  test/lib/qualification only); pass 2 targeted
  `-i -E "strong.cyclic|fond_policy|hddl_solve|\"policy\""`.
- **Noise classes silently excluded after inspection** (not silent — named):
  `resolved_sha` / `unresolved` / prose "policy" (blocker types, types
  reference, case-study docs — 80+ hits); `qualification/fixtures/
  claude-workflows/journal.jsonl` (captured agent-session prose, zero engine
  verdicts); `beam4pm_engine_dispatch_gate_test.exs` (ferroplan op list,
  arity/manifest gate — carries NO verdict expectations).
- **`mix test` was NOT run** — another wave agent owns the beam4pm HTTP
  ports (ticket worktree law). Every engine verdict below was instead
  measured with the scratch runner `/tmp/fp-probe` (rebuilt this session;
  the 2026-09-17 original was lost from /tmp) compiled against
  **~/ferroplan main @ `6cacbda`** via path deps; source read-only from
  `~/ferroplan`, compilation confined to `/tmp/fp-probe/target`. The
  current-pin side of each verdict is the existing green test assertion
  (recorded evidence from `ace23e5`), not a re-run.
- **Classification-only rows** are marked; measured rows carry cmd + exit.
- Upstream state used for classification: fond-htn-57 (FOUND_BUG_2 fix
  ALIVE @ `d00dcf8` on `fix/sc-choice-rewrite`, unmerged), fond-htn-58
  (drop-retry, BLOCKED, unfixed), fond-htn-60 (grounding relevance prune,
  PARTIAL_ALIVE, two re-pinned refusal→solved behavior changes, all in the
  **ferroplan-hddl** HTN grounder), fond-htn-65 (translate plumbing, ALIVE
  @ `6757249`, **default behavior byte-identical** — 761 tests/0 failed).

## 1. Enumeration + classification table (scope 1)

Verdict-type key: `solve-verdict` | `policy-content` | `error-code` |
`parity` (asserts equality with a row above, no independent verdict).

### test/beam4pm_ferroplan_test.exs

| # | site | fixture | current expectation | verdict-type | wave-6 exposure | disposition | evidence |
|---|---|---|---|---|---|---|---|
| 1 | L54–55 | two-room (classical PDDL, inline) | `solved == true`, `plan.length == 1` | solve-verdict | none (classical path untouched by 57/58/60/65) | **NO FLIP — measured** | run 6: solved=true, length 1 |
| 2 | L62 | two-room via plan_production | `outcome == "solved"` | solve-verdict | none | **NO FLIP — measured** | run 6 (same engine call) |
| 3 | L69–70 | two-room + bogus mode | `outcome == "refused"`, code `FP_INVALID_REQUEST` | error-code | none (request validation, pre-engine) | **NO FLIP — classified** | validation happens before solve; not in wave-6 scope |
| 4 | L110–111 | fixture-a (`crates/ferroplan-hddl/fixtures/a`) | no `error` key, `solved == true` | solve-verdict | 60 (HTN grounding) — count reduction only | **NO FLIP — measured** | run 2: solved=true, 4-entry policy, notes `["strong FOND fixed point"]` |
| 5 | L119–122 | solve_x (`native/ferroplan/domains/solve_x*`) | `solved == true`, `notes == ["strong FOND fixed point"]`, `length(policy) == 8` | policy-content | 57 (strong-cyclic choices; this is a STRONG deterministic chain) | **NO FLIP — measured** + **FIXTURE HAZARD** (row 5a) | run 3: solved=true, 8 entries, identical notes |
| 5a | L115–116 | solve_x file provenance | `File.read!("native/ferroplan/domains/solve_x.hddl")` at module load | fixture-provenance | **the reconciled bump removes this file** — `solve_x*` exists ONLY at pin `4b8ff2e`, absent from ferroplan main `6cacbda` (verified: not in `~/ferroplan/domains/`, not under `crates/ferroplan-hddl/fixtures/`) | **POST-BUMP FLIP (non-verdict): `File.read!` will RAISE in this test AND facades rows 12–17.** Post-bump audit must migrate the fixture into beam4pm (`test/fixtures/` or equivalent) or repoint to a main-side fixture. Adjudicate in b4p-f5-05/06, do not silently delete tests | `find /Users/sac/ferroplan -name "solve_x*"` → 0 hits; `ls /Users/sac/beam4pm/native/ferroplan/domains/` @ pin → present |
| 6 | L176–178 | bridge-c (inline oneof HTN, non-covering methods) | `{:error, {:engine, msg}}`, `msg =~ "FP_MODEL"`, `msg =~ "NoPlan"` | error-code + solve-verdict | 57/58 directly (oneof + method choice); this is the ace23e5 precedent flip | **NO FLIP — measured.** Semantics re-derived: with m-direct, the lucky oneof outcome empties the task network at l3 with goal unreached (dead); with m-two-step, the lucky outcome leaves `walk l3→l2` inapplicable at l2 (dead). No method covers all outcomes ⇒ NoPlan is the true verdict under both old and new semantics; ticket-58's empty-branch re-decompose does not apply (no empty branch — an inapplicable primitive, and non-covering method choice) | run 1: `{"verdict":"error","code":"FP_MODEL","detail":"Planner(NoPlan)"}` |
| 7 | L185 | malformed HDDL `(define (domain broken` | error code matches `FP_PARSE\|FP_HDDL_GROUND\|FP_HDDL_TRANSLATE` | error-code | none (parser untouched by wave-6) | **NO FLIP — measured** | run 8: `FP_PARSE "syntax error: unbalanced parentheses"` |
| 8 | L192–196 | two-room via session_think | `solved == true`, `has_plan == true`, `valid == true` | solve-verdict | none (classical) | **NO FLIP — measured** (same engine call as row 1) | run 6 |
| 9 | L215–216 | session_fork plan-state isolation | parent `has_plan == true`, child `false` | derived (row 8) | none | **NO FLIP — classified** | follows row 8 |

### test/beam4pm_ferroplan_facades_test.exs (parity suite — every row also asserts byte-equality with the Elixir wrapper)

| # | site | fixture | current expectation | verdict-type | disposition |
|---|---|---|---|---|---|
| 10 | L110–112 | two-room, erlang `plan/2` | parity + `solved==true`, `length==1` | solve-verdict + parity | **NO FLIP** (row 1) |
| 11 | L118–120 | two-room, erlang `plan_production/2` | parity + `outcome=="solved"` | solve-verdict + parity | **NO FLIP** (row 2) |
| 12 | L142–145 | fixture-a, erlang `hddl_solve/2` | parity + `solved==true`, policy non-empty | policy-content + parity | **NO FLIP — measured** (row 4); FIXTURE HAZARD n/a (fixture-a exists on main) |
| 13 | L152–155 | solve_x, erlang `hddl_solve/2` | parity + `solved==true`, notes, `length==8` | policy-content + parity | **NO FLIP — measured** (row 5) + **FIXTURE HAZARD** (row 5a applies: `File.read!` at L71–72) |
| 14 | L165–166 | two-room, erlang `session_think` | parity + `solved==true` | solve-verdict + parity | **NO FLIP** (row 8) |
| 15 | L243–244 | two-room, gleam `plan/2` | parity + `solved==true` | solve-verdict + parity | **NO FLIP** (row 1) |
| 16 | L262–265 | fixture-a, gleam `hddl_solve/2` | parity + `solved==true`, policy non-empty | policy-content + parity | **NO FLIP — measured** (row 4) |
| 17 | L271–275 | solve_x, gleam `hddl_solve/2` | parity + `solved==true`, notes, `length==8` | policy-content + parity | **NO FLIP — measured** (row 5) + **FIXTURE HAZARD** (row 5a, `File.read!` at L71–72) |
| 18 | L280–289 | two-room, gleam session parity | equality with Elixir results | parity only | **NO FLIP** (row 8) |

### test/beam4pm_pddl_projection_test.exs (classical plan_production over manufactured PDDL projections)

| # | site | fixture | current expectation | verdict-type | disposition |
|---|---|---|---|---|---|
| 19 | L163–169 | toy_counter_governed, k8s_scaling_governed | `outcome=="solved"`, `payload.solved==true`, ordinal action sequence | solve-verdict | **NO FLIP — classified** (classical path; control-measured: run 6) |
| 20 | L186 | both contracts | both `outcome=="solved"`, disjoint action sets | solve-verdict | **NO FLIP — classified** |
| 21 | L223–227 | final transition deleted | `outcome=="no_plan"`, `payload.solved==false`, no `plan` key, `grounded_actions==0` | solve-verdict | **NO FLIP — classified** (control-measured: run 7, unreachable goal ⇒ solved=false) |
| 22 | L238–241 | first transition deleted | `outcome=="no_plan"`, `solved==false` | solve-verdict | **NO FLIP — classified** |
| 23 | L258–261 | requiresFact removed | `outcome=="no_plan"`, `solved==false` | solve-verdict | **NO FLIP — classified** |

### lib/ (surface contracts, not test expectations)

| # | site | content | verdict-type | disposition |
|---|---|---|---|---|
| 24 | lib/beam4pm_ferroplan.ex:731 | `@doc hddl_solve`: stage error codes `FP_PARSE`, `FP_HDDL_GROUND`, `FP_HDDL_TRANSLATE`, `FP_MODEL` | error-code (doc contract) | **NO FLIP — measured** (run 8 exercised FP_PARSE; run 1 exercised FP_MODEL; ggen-generated from `bpm:EngineOp` — any change is an ontology change, never a hand-edit) |

### External pairs measured for the post-bump audit (no beam4pm test site exists; context-designated highest-risk)

| # | fixture | hardened verdict (6cacbda) | disposition |
|---|---|---|---|
| 25 | autofde-lab `verify-and-commit.hddl` + `-problem.hddl` | `solved=true`, 6-entry policy (m-verify-then-commit-honest → compile→migrate→test→mock-grep→commit-with-real-status) | **Reproduces the 2026-09-17 preview exactly.** If a future beam4pm fixture adopts it, `solved==true` is the re-derived expectation |
| 26 | autofde-lab `sa2a-v26.9.17-domain.hddl` + `-problem.hddl` | `FP_MODEL` / `Planner(NoPlan)` in 4729 ms | **Reproduces the preview's NoPlan.** The problem declares ONLY an `(:htn :ordered-subtasks (top0 (ORIENT-AND-CERTIFY-RELEASE)))` root — no `(:goal …)` section — so under full empty-task-network termination the run ends at network-empty, short of the fixture's intended typed-stop acceptance. Believed-solvable-by-design ⇒ **semantic divergence to adjudicate UPSTREAM in ferroplan** (goal-set semantics class named in b4p-f5-06 scope 2), NOT a test to relax. No beam4pm site consumes it today; file with reproducer = `/tmp/fp-probe` + this pair |

## 2. Real verdict runs (all vs ~/ferroplan main @ `6cacbda`; runner /tmp/fp-probe, built this session)

| # | cmd | exit | result |
|---|---|---|---|
| 1 | `fp-probe bridge-c-domain.hddl bridge-c-problem.hddl` | 0 | `{"verdict":"error","code":"FP_MODEL","detail":"Planner(NoPlan)","ms":1}` |
| 2 | `fp-probe ~/ferroplan/crates/ferroplan-hddl/fixtures/a/{domain,problem}.hddl` | 0 | solved=true, 4 entries, notes `["strong FOND fixed point"]`, 0 ms |
| 3 | `fp-probe solve_x.hddl solve_x.problem.hddl` (pin-copied fixtures vs hardened engine) | 0 | solved=true, 8 entries, notes `["strong FOND fixed point"]`, 2 ms |
| 4 | `fp-probe autofde-lab/…/verify-and-commit{,-problem}.hddl` | 0 | solved=true, 6 entries, 0 ms |
| 5 | `fp-probe autofde-lab/…/sa2a-v26.9.17-{domain,problem}.hddl` | 0 | `FP_MODEL` / `Planner(NoPlan)`, 4729 ms |
| 6 | `fp-probe two-room.pddl two-room-problem.pddl` | 0 | solved=true, plan_length=1, 1 ms |
| 7 | `fp-probe two-room.pddl two-room-broken.pddl` (control) | 0 | solved=false, plan_length=0 |
| 8 | `fp-probe broken.hddl bridge-c-problem.hddl` (control) | 0 | `FP_PARSE "syntax error: unbalanced parentheses"`, 2 ms |

Build evidence: `cargo build --release` in /tmp/fp-probe exit 0 (37.11 s;
second build 0.95 s after adding the classical path). Source tree
`~/ferroplan` only ever read (docs/jira ticket files there carry unrelated
concurrent-session edits, untouched by this agent).

## 3. Evidence quarantine (scope 3)

**Sweep targets**: `research/erc/`, `receipts/` (incl. `engine_ops/`,
`actuation-selfmine/`), `qualification/` (incl. `gym_bridge/`),
`docs/` (incl. all jira history dirs), `contracts/`, `ontology/`.

**Result: ZERO quarantine rows.** No beam4pm artifact cites a strong-cyclic
(or any ferroplan FOND/policy) verdict produced by the pre-wave-6 engine:

- `research/erc/` — 12 files, all `ERC-002-*` (2026-09-12…14): POWL
  **conformance** verdicts over gym_bridge OCEL captures. No solve /
  NoPlan / policy / strong-cyclic claim. (`ERC-001` is referenced via
  `depends_on` but is not in-repo; nothing here cites engine verdicts.)
- `receipts/engine_ops/` — petgraph + rust4pm op receipts only; **zero**
  ferroplan/fond_policy/hddl_solve receipts exist.
- `receipts/actuation-selfmine/` — actuation receipts, no engine verdicts.
- `qualification/gym_bridge/` — OCEL captures produced by **ash_a2a's**
  end-to-end run over its own `native/hddl_cli` binaries (a different
  engine pin from beam4pm's submodule), and the README's "solved" is the
  lock-and-key **gym's** episode flag; `REFUSED:BRIDGE_NETWORK_POLICY` is
  network policy, not FOND policy. No engine verdict captured or cited.
- `docs/` — zero occurrences of "strong-cyclic" outside
  `docs/jira/v26.9.17/` (which contains this wave's own tickets).
  `docs/reference/beam4pm_types_reference.md` FP-hit scan = all
  resolved/unresolved noise.
- `docs/jira/v26.9.17/*.md` (beam4pm tickets f5-01…f5-05 etc.) — no engine
  verdict citations other than b4p-f5-06 itself.

**Standing consequence**: the ticket's quarantine gate ("zero un-marked
pre-wave-6 strong-cyclic verdicts reachable from current evidence indexes")
is **already satisfied at `22fa4aa`** — there is nothing to mark. The only
strong-cyclic-adjacent verdict evidence in-repo is test row 6 (bridge-c),
which cites a refusal and was re-measured as still true. **Residual
coupling note (not quarantine)**: the gym_bridge capture chain and
autofde-lab's wasm registry pin (`282fae4`, 384 behind ferroplan main) are
separate engine pins — a beam4pm submodule bump does NOT flip them, and
this ledger does not claim to govern them.

## 4. Post-bump mechanical procedure (for b4p-f5-06 scope 2, after b4p-f5-05 lands)

1. Re-run the 8-run table in §2 unchanged (runner: `cargo build --release`
   in /tmp/fp-probe, retarget its path deps at the new pin if the pin is
   not main).
2. Reconcile §1 rows against actual `mix test` output; any row whose
   measured hardened verdict differs from its expectation is a flip: name
   the cause ticket (57 choice-rewrite / 58 drop-retry / 60 grounding prune
   / 65 translate plumbing), re-derive or escalate per scope 2.
3. Row 5a fires first and mechanically (File.read! raise) if the bump
   removes `solve_x*` — resolve fixture provenance BEFORE the test run.
4. Row 26's upstream adjudication should be filed in ferroplan regardless
   of the bump (the divergence exists on main today).
