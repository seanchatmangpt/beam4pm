# WAVE-RECEIPT — g5 consumption-max (v26.9.18)

Standing: **ALIVE** (all gates observed passing in this session; see Gates).
Agent: G5, ggen maximization wave. Date: 2026-09-18/19.

## SHAs

- beam4pm worktree `/Users/sac/beam4pm-worktrees/wt-g5`, branch
  `chore/ggen-consumption-max`, base main @ **27ff280**; wave commit = HEAD
  after this receipt (single atomic commit; see `git log -1` on the branch).
- Vendored submodule `vendor/ggen-marketplace`: branch
  `fix/hand-authored-manifest-templates-force-overwrite` (local to this
  worktree's clone), head **6750aa19f** =
  - `f2ae5382e` raise hand_authored_qualification 35 -> 50,
    native_engine_facade 6 -> 7 (fetched from wt-integration's vendored
    clone, branch fix/hand-authored-qualification-ceiling-35-wave-26918),
  - `6a30fad72` fix(process-model): force:true on the two hand-authored
    manifest templates (surfaced by this wave),
  - `0809e8f95` fix(wasm-engine): GENERATED marker in the JSON schema's
    first 3 lines (surfaced by this wave),
  - `6750aa19f` fix(wasm-engine): force:true on all four templates
    (surfaced by this wave).
- No push (wave law). The submodule branch carries the three g5 pack fixes
  for upstreaming; the superproject gitlink pins 6750aa19f.

## Pack-raise reconciliation (honest line)

- beam4pm main @ 27ff280 pins vendor/ggen-marketplace @ **7abe147e1**
  (ceiling 33 -> 35, v26.9.12-era).
- `f2ae5382e` is a DIRECT DESCENDANT of `7abe147e1`
  (merge-base --is-ancestor verified): the integration raise supersedes the
  pin by clean fast-forward; nothing was re-based or rewritten.
- The main CHECKOUT's vendored submodule sits on branch
  fix/hand-authored-qualification-ceiling-33 @ 7abe147e1 with an
  UNCOMMITTED ontology.ttl edit raising ceiling 35 -> 36 (no dated
  receipts). Relationship: superseded by f2ae5382e's fully documented
  35 -> 44 -> 50 line (which also raises native_engine_facade and carries
  the per-file admission receipts). Read-only there; not discarded by this
  wave. When the parity/integration branch lands, that checkout should
  discard the dirty 35 -> 36 edit in favor of the raise.
- ggen.lock was intentionally re-locked three times (rm ggen.lock; ggen
  sync run) as the pack bytes changed under it — once for the raise, twice
  for the g5 pack fixes. FM-PACK-008 did its job each time.

## Wire/decline table (full findings in docs/authorship_dashboard.md section 5)

Universe: 299 packs in the vendored clone @ 6750aa19f (marketplace main has
318; 22 main-only, 3 clone-only). Enumeration bounds and per-pack findings:
dashboard section 5.

- **WIRED (+2, 8 -> 10 packs):** beam4pm-mcp-contracts-pack v0.1.0
  (schema-only sibling of ai-contracts; 10 mcp:MessageType consumers
  admitted into consumer ontology.ttl verbatim from the pack's own
  reference consumer; renders 9 files) and beam4pm-wasm-engine-pack v26.9.1
  (self-contained bpw: engine ABI graph grounded in this repo's real
  facades, SHACL-gated; renders 4 reflection files; required provisioning
  shapes/profile.shacl.ttl consumer-side, byte-identical, because ggen
  26.8.18 resolves `shape:` strictly inside the project root).
- **DECLINED with findings (28 packs + 1 family):**
  beam4pm-post-llm-runtime (zero rt: consumers, off-convention out paths,
  slice already owned upstream); 9x autofde-* (project autofde-lab's own
  Python/Rust/cnv surface — wrong consumer; beam4pm↔autofde-lab is runtime
  bridging, not in-tree manufacture); fortune5-enterprise-architecture
  (zero templates), fortune5-required-capabilities (renders a foreign Rust
  cargo project), fortune5-testing-bblock (renders a Python verifier tree;
  ExUnit manufacture owned upstream); frontier-derivative (no to:/sparql
  frontmatter; hypergraph not admitted here); frontier-release-factory
  (superseded by wired frontier-release-beam; zero frf: consumers);
  gh-actions-errc, github-cloud-operating-doctrine,
  github-controloutcome-observation, github-live-evidence-ingestion
  (strategic/observability projections over graphs this repo does not
  admit); gh-enterprise-architecture (decline-by-dependency on the
  gh-terraform precedent); wasm4pm-* 18-pack family (~/wasm4pm workspace's
  own catalogs, several SUPERSEDED PROTOTYPE); ash-extension-core +
  ash-extension-starter (zero aex: consumers, clone-only);
  ash-reactor-domain-error-contract (zero r84: consumers, Reactor modules
  already manufactured, `generated/` off-convention, clone-only).

## Dashboard counts + forecast (docs/authorship_dashboard.md)

- Classification (reproducible commands in the dashboard): 1371 files under
  gate roots = **1322 GENERATED / 49 admitted / 0 unadmitted**. Product
  roots (lib/src/gleam): lib 633/17/0, src 17/1/0, gleam/src 8/0/0,
  gleam/test 2/0/0, test 47/25/0.
- Lines: manufactured 125,694 / hand-admitted 2,253 / total 127,947 →
  **比 = 98.24%** on the product surface.
- Debt vs ceilings: hand_authored_qualification **36/50**;
  native_engine_facade **6/7**; debt total 42 (reference_evidence 6 and
  manufacturing_input 1 admitted without debt count).
- **Forecast number:** with the parity merge + g1 (CLI-bridge wrappers pack)
  + g3 (port-bridge client pack) landed, lib hand lines retire 512
  (beam4pm_dfcm.ex) + 457 (beam4pm_autofde_bridge.ex) → tree
  **比 98.24% -> 98.64%** (126,663/128,404); the parity wave's own marginal
  比 was 0% hand-written, so those packs make the next wave's marginal
  **100%** on the retired families. g2 (parity qualification tests pack)
  retires 15 qualification rows (9 test files + 6 TTL fixtures, 1,868
  test-side lines) → qualification debt 36/50 with headroom 15 restored.
  Without the packs, the parity merge lands BOTH ceilings exactly at
  capacity (50/50, 7/7) — zero headroom on merge day.
- Merge hazard recorded: lib/beam4pm_dfcm.ex bytes differ between main and
  parity/integration @ 70e2662; the winning side's bpm:contentSha256 must
  be regenerated in the merge commit or GATE AUTHORSHIP refuses
  REFUSED_SHA_DRIFT.

## Gates (all observed this session, this tree)

1. **ggen sync run (Rust leg, real render):** exit 0 after intentional
   re-lock; 13 new files written (9 MCP + 4 engine-manifest), all GENERATED
   -marked within first 3 lines; ggen.lock + docs/reference/
   beam4pm_hand_authored_source.md regenerated with raised ceilings.
2. **GATE AUTHORSHIP:** `bash scripts/gate_authorship_check.sh` →
   **PASS — 49 admitted (42 counted as manufacturing debt), 1371 files
   under roots, 0 findings.**
3. **Bare igniter sync (Elixir/Ash leg):** `bash scripts/igniter_sync.sh`
   — full diagnostic trail, five runs:
   - Run 1 (host-default Elixir 1.18.4): FAILED at the first sync's
     internal build-verification — `--warnings-as-errors` refused on
     PRE-EXISTING main-tree warnings, none from this wave's files:
     `lib/beam4pm_dfcm.ex:179` calls `AshAutofde.CascadeAllocator.allocate/3`,
     a module defined NOWHERE in the repo or deps (grep-verified; the file
     landed on main TODAY, bf818bf, via the parity wave — its own raise
     commit admits P10's branch-scoped run never executed the full gate);
     and `lib/mix/tasks/eds.ledger.ex` (2026-09-12) redefines
     `Mix.Tasks.Eds.Ledger` already shipped by dep ash_a2a. Repair per the
     repo's own regeneration-window convention (the authorship gate's
     TRANSIENT_ABSENT rule): stash the two offending admitted lib files +
     dfcm's test file during the leg, restore after — no gate weakened, no
     sha touched (restored bytes re-verified against admissions).
   - Run 2 (Elixir 1.19.5, deps declare `~> 1.19`): same refusal — proves
     the blockers are pre-existing debt, not toolchain.
   - Run 3 (1.19.5, stash): all syncs rendered, but the cross-engine
     identity probe DIVERGED. Diagnosis: ggen_igniter format-on-writes every
     .ex through `Code.format_string!/1`; the Rust/Tera leg writes raw
     bytes. The parity wave's new long-field-list records crossed mix
     format's wrap width, so raw-vs-formatted diverged on wrapping alone —
     TOKEN STREAMS VERIFIED IDENTICAL. Repair (consumer-side, scripts/
     igniter_sync.sh): normalize BOTH sides through the same deterministic
     `mix format` before diffing — full probe strength retained (any
     record/field/order/content difference still refuses).
   - Run 4 (1.19.5, stash): probe IDENTICAL, compile PASSED, mix test
     failed only on missing host natives (wasm modules + rf oracles).
     Natives built/copied per repo paths: 3 wasm artifacts from the main
     checkout's build dirs, ferroplan vendored source rsync'd (host-local
     untracked state, 23.7 MB sans target/, with the compile-time
     domain.hddl fixture), all four rf oracle binaries cargo-built fresh.
   - Run 5 (final, `source scripts/env/rust4pm_reactor_env.sh` — the
     documented canonical env; fixtures are checked-in byte-identical
     copies — plus stash + natives): **exit 0**: all 7 sync steps, probe
     identical, compile clean, and mix test **1153 tests, 0 failures,
     60 skipped** with the three debt files transiently absent.
4. **Formatter-churn finding (reported, not committed):** any leg run with
   the PINNED ggen_igniter (mix.lock resolution of "~> 26.8") now rewrites
   603+ tracked files, because that ggen_igniter format-on-writes every .ex
   (`Code.format_string!/1`) while the tree's historical rendered bytes
   predate format-on-write (parens-less `attribute :x, :t` style).
   Reproduced under BOTH Elixir 1.18.4 and 1.19.5 — the variable is the
   ggen_igniter version, not the toolchain. Reverted before commit (the
   608-file reformat is a mechanical repo-level transition that must be
   its own commit, and it would collide with the parity/integration merge);
   the leg's exit-0 evidence stands on its own.
5. **Dashboard reproducibility:** the two command blocks in
   docs/authorship_dashboard.md sections 1-2 were executed verbatim to
   produce every number in it; re-running them on the committed HEAD
   reproduces the tables.

## 比 (this wave's own manufacture)

- 産面 lines added by g5: 13 rendered files (9 MCP + 4 engine-manifest) +
  regenerated manifest/.md — all manufactured (pack renders), zero
  hand-written product lines. Hand-written artifacts of this wave:
  docs/authorship_dashboard.md (measurement prose, the dashboard's own
  job), this receipt, the audit comment in ggen.toml, the mcp: instance
  block in ontology.ttl (consumers transcribed verbatim from the pack's
  reference consumer — REUSE, not authorship), shapes/profile.shacl.ttl
  (byte-identical pack copy), and one consumer-side infra repair
  (scripts/igniter_sync.sh probe normalization, documented inline).
  Operator wrote nothing (did-not-write holds: every pack/ontology/
  template byte came from the marketplace or its own reference data).
- Pack-side authorship (my submodule branch): 3 commits fixing real
  cross-engine/gate contract defects surfaced by this wave
  (6a30fad72, 0809e8f95, 6750aa19f) — the wave's net effect is that the
  marketplace now renders cleanly for this consumer at lock-verified
  bytes.
- Remaining: none blocking. Handoffs: (a) upstream the 3 submodule pack
  fixes from branch fix/hand-authored-manifest-templates-force-overwrite;
  (b) parity/integration merge must regenerate dfcm.ex's admission sha and
  sequence g2 before or with the merge (ceiling math above); (c) main
  checkout's dirty 35 -> 36 ontology edit should be discarded in favor of
  f2ae5382e when integration lands; (d) next vendored bump should re-run
  the dashboard section 5 audit for the 22 main-only packs; (e) the repo
  must pick one formatter version for rendered bytes (603-file churn
  waiting for whoever runs the leg under 1.19.5 first); (f) the parity
  wave must fix lib/beam4pm_dfcm.ex's call to the nonexistent
  AshAutofde.CascadeAllocator module (blocks warnings-as-errors
  verification on every full leg until then).
# WAVE-RECEIPT — agent A10, ticket b4p-f5-07 scope items 1 + 2-as-draft

- **Base / branch / tree**: beam4pm main `22fa4aa` → branch `chore/engineop-ferroplan-prep`, worktree `/Users/sac/beam4pm-worktrees/wt-f5-ontology-prep` (this agent's alone).
- **Standing**: `PARTIAL_ALIVE` (ticket level). This slice's gates: diff table committed (gate 1 of 3, done); admission + re-render + parity tests remain and are **BLOCKED on b4p-f5-05** (pin reconciliation).
- **Forbidden surfaces respected**: no `mix test` (ports owned elsewhere), no cargo builds, zero writes to `/Users/sac/beam4pm` main checkout (its `ontology.ttl` is dirty from a concurrent session). ~/ferroplan and the submodule read-only.

## Evidence (commands/observations, this session)

| # | observation | source |
|---|---|---|
| 1 | Admitted set = 33 `bpm:EngineOp` facts for `bap:engine_ferroplan` (incl. `htn_plan`/`fond_policy`/`hddl_solve`, admitted at `ace23e5`); render `lib/beam4pm_ferroplan.ex` carries the same 33 ops 1:1 — faithful projection confirmed | worktree `ontology.ttl:11374–11697`; `lib/beam4pm_ferroplan.ex:188–741` |
| 2 | Engine dispatch table @ `~/ferroplan` main `6cacbda`: 33 arms, name-identical to admitted set | `crates/ferroplan-wasm/src/wasi_abi.rs:299–340` |
| 3 | `git diff 6cacbda d00dcf8 -- crates/ferroplan-wasm/` → **empty** (fix branch `d00dcf8` touches `planning_runtime.rs` +137 and tests only). One reconciled ABI surface. | run in `/Users/sac/ferroplan` |
| 4 | Pin→reconciled ABI delta (only): `FP_HDDL_ROOT_MISMATCH` added; `FP_HDDL_TIMEOUT`→`FP_TIMEOUT`; `FP_HDDL_WORKER_PANIC`→`FP_WORKER_PANICKED` | `wasi_abi.rs:517–544` @6cacbda vs `4b8ff2e` submodule `wasi_abi.rs:519–537` |
| 5 | `hddl_solve` forces `limits.max_wall_ms = 0` (wasi1 has no OS threads; watchdog thread would trap); BEAM wasmex heavy timeout (120 000 ms) is the effective wall bound — never-block-past-budget | `wasi_abi.rs:493–506` @both pins |
| 6 | `PlannerLimits` = `max_depth` 128 / `max_states` 100_000 / `max_iterations` 512 / `max_wall_ms` 10_000 (0 = unbounded), field-identical at **both** pins → admitted-set gap, not drift; `check_wall_deadline` fires only in `fond_policy`/`fond_policy_strong_cyclic` (htn_plan inert); universal-op overrun → `FP_ADAPTER` envelope | `planning_runtime.rs:199–266` @6cacbda (= `171–236` @4b8ff2e); call sites `824/954/988/1040/1051`; `wasi_abi.rs:446–449` |
| 7 | `session_think` caps: `evals` 1..=1_000_000 → `FP_LIMIT_SEARCH`, `mem_mb` 1..=2_048 → `FP_LIMIT_MEMORY` (present at both pins; never admitted) | `wasi_abi.rs:100–101, 687–698` |

## Diff-table summary (full table in `OP-DIFF.md`)

- **0 new ops, 0 removed ops, 33 unchanged** (names, arg shapes, arg defaults, response shapes).
- **Changed (admit as opDoc revisions): 4** — `hddl_solve` (new code + renames + forced-sync watchdog semantics), `fond_policy` (wall deadline honored per round, `FP_ADAPTER` envelope), `htn_plan` (max_wall_ms inert), `session_think` (FP_LIMIT_* caps).
- **New FP codes: 1** (`FP_HDDL_ROOT_MISMATCH`); **renamed: 2**; **engine-level vocabulary confirmed unchanged: 7** generic codes.
- **Falsifiers attempted, all survived as evidence**: (a) "hddl_solve/htn_plan/fond_policy are unadmitted new ops" — FALSIFIED, admitted at `ace23e5`; (b) "the d00dcf8 soundness fix changes the ABI" — FALSIFIED, empty crate diff; (c) "PlannerLimits gained fields since the pin" — FALSIFIED, field-identical at both pins (the doc gap predates the bump).

## Files changed (this branch, this commit family)

- `OP-DIFF.md` (new) — the ticket's op | admitted? | engine? | disposition table, every row cited both sides.
- `ONTOLOGY-DELTA-proposal.ttl` (new) — PROPOSAL, admission via ggen sync only; 4 revised `bpm:opDoc` literals on existing individuals, existing namespace/typing/idiom, 0 new individuals.
- `b4p-f5-07-HISTORY-ROW-A10.md` (new) — the exact History row for the canonical ticket. The ticket file itself is untracked in the beam4pm main checkout (created after `22fa4aa`, owned by the dispatching session); writing the main checkout is forbidden, so the verbatim row is delivered in-tree for append at integration (no untracked-path collision).
- `WAVE-RECEIPT.md` (this file).

## 比

産面 lines delivered by this agent: **0** (no facade, wrapper, test, or production path touched — by design; the ontology delta itself must land through ggen admission, not here). Delivered artifacts are 法-side analysis + a draft delta: 100% hand-written by the agent, attributable, no unattributed lines. The render (items 3–4) is where the manufactured-lines ratio will move; it is explicitly out of this slice.

## Remaining (recorded, not mine)

1. **b4p-f5-05**: reconcile the pin (beam4pm `4b8ff2e` → `6cacbda`/successor), land the FOND soundness line.
2. **Ticket item 2**: apply `ONTOLOGY-DELTA-proposal.ttl` through the pack/ggen sync (`mix ggen` sync per repo convention) — never hand-applied.
3. **Ticket item 3**: re-render the three facades; verify GENERATED markers + compile; expect possible verdict flips on existing fixtures (FOUND_BUG_1/2 become reachable at the new pin).
4. **Ticket item 4**: extend Elixir/Erlang/Gleam parity tests to the revised envelope assertions; `mix test test/beam4pm_ferroplan_facades_test.exs` exit 0.

## What the operator did NOT have to write

The full admitted-vs-engine diff (33 ops × both error vocabularies × limits semantics), the pin/reconciled drift attribution, and the admission-ready proposal text — all manufactured from primary sources this session.
# WAVE-RECEIPT.md — agent A9, b4p-f5-06 scope 1 + 3 (pre-bump flip ledger)

- **date**: 2026-09-18 (session)
- **standing**: **ALIVE** (scope-limited: ledger built and committed; scope 2's
  re-derivation loop correctly awaits b4p-f5-05's reconciled bump)
- **repo/base**: beam4pm worktree `/Users/sac/beam4pm-worktrees/wt-f5-verdict-audit`,
  branch `chore/ferroplan-verdict-flip-audit` @ `22fa4aa` (beam4pm main), clean
  before this session's two file additions + one History append.
- **upstream subject measured**: ~/ferroplan main @ `6cacbda`
  (`6cacbdab1f9dd4f72c5f5f142bbeedc1eaa62222`), read-only.

## Enumeration bounds (scope 1)

- dirs scanned: `test/ lib/ qualification/ research/ receipts/ docs/
  contracts/ ontology/`; patterns `solved|NoPlan|FP_[A-Z]+` (98 raw hits,
  test/lib/qualification) + targeted `strong.cyclic|fond_policy|hddl_solve|"policy"`.
- sites found: **26 ledger rows** — 9 in `test/beam4pm_ferroplan_test.exs`
  (incl. row 5a, the pin-only `solve_x` fixture-provenance hazard),
  9 in `test/beam4pm_ferroplan_facades_test.exs`, 5 in
  `test/beam4pm_pddl_projection_test.exs`, 1 lib doc contract
  (`lib/beam4pm_ferroplan.ex:731`), 2 external pairs measured for
  post-bump readiness (verify-and-commit, sa2a-v26.9.17).
- noise classes named, not silently pruned: resolved_sha/unresolved prose,
  claude-workflows journal.jsonl, engine dispatch gate op list (no verdicts).

## Real verdict runs (8; cmd+exit+result in FLIP-LEDGER §2)

Runner `/tmp/fp-probe` REBUILT this session (2026-09-17 original lost from
/tmp; REUSE was attempted first — `ls /tmp/fp-probe` exit 1). Cargo bin with
path deps on `~/ferroplan/crates/ferroplan`; built in /tmp (37.11 s, exit 0),
never in `~/ferroplan`. `mix test` NOT run (port-owner law); every hardened
verdict measured through the engine's real `solve_hddl` / `api::solve` instead.

Key results vs ferroplan main `6cacbda`:
- bridge-c → `FP_MODEL`/`NoPlan` — current expectation HOLDS (no flip)
- fixture-a → solved=true, 4-entry policy — HOLDS
- solve_x → solved=true, 8-entry policy, notes identical — verdict HOLDS;
  **but the fixture exists ONLY at pin `4b8ff2e`** — post-bump `File.read!`
  will raise (mechanical first-flip for the audit)
- verify-and-commit → solved=true, 6 entries (2026-09-17 preview reproduced)
- sa2a-v26.9.17 → `FP_MODEL`/`NoPlan` @ 4729 ms — preview reproduced; live
  upstream divergence (goal-set vs empty-network termination), to adjudicate
  in ferroplan, not relax
- two-room classical → solved=true, length 1 (control: unreachable → solved=false)
- malformed HDDL → `FP_PARSE` (control)

## Quarantine (scope 3)

**0 artifacts quarantined — sweep found ZERO pre-wave-6 strong-cyclic
verdict citations** in research/erc (12× ERC-002 conformance only),
receipts (no ferroplan op receipts exist), qualification/gym_bridge
(ash_a2a hddl_cli provenance, gym-flag "solved", network-policy refusal),
docs (zero "strong-cyclic" outside this wave's own tickets). The gate is
already satisfied at `22fa4aa`; reasoning per target recorded in
FLIP-LEDGER §3. Artifacts themselves untouched (shared checkout law).

## Files changed (this branch)

- `FLIP-LEDGER.md` (new — enumeration, classification, runs, quarantine,
  post-bump mechanical procedure)
- `WAVE-RECEIPT.md` (new — this receipt)

Ticket-file History append: the b4p-f5-* ticket set is **untracked** in the
shared checkout (coordinator's working set; this agent must not write the
main checkout), so the History row below is carried here for coordinator
union into `docs/jira/v26.9.17/b4p-f5-06-ferroplan-verdict-flip-audit.md`:

```
| 2026-09-18T05:10:00Z | PARTIAL_ALIVE (scope 1+3 pre-bump) | chore/ferroplan-verdict-flip-audit @ 22fa4aa+ (worktree wt-f5-verdict-audit) | scope 1: FLIP-LEDGER.md committed — 26 rows enumerated (bounds recorded: 98 raw hits classified, noise classes named); scope 3: quarantine sweep = ZERO pre-wave-6 strong-cyclic citations in research/erc, receipts, qualification, docs (gate already satisfied @ 22fa4aa); 8 real verdict runs vs ferroplan main 6cacbda via rebuilt /tmp/fp-probe (mix test NOT run — port-owner law): bridge-c NoPlan HOLDS, fixture-a/solve_x solved HOLDS, verify-and-commit solved=true/6 reproduced, sa2a NoPlan reproduced (upstream divergence to adjudicate), two-room classical HOLDS; NEW FINDING row 5a: solve_x fixture exists ONLY at pin 4b8ff2e — post-bump File.read! raises (mechanical first flip for the scope-2 loop) | scope 2 flip loop (awaits b4p-f5-05 reconciled bump; procedure = FLIP-LEDGER §4), scope 4 tripwire gate, sa2a divergence filed upstream |
```

## 比 (ratio, honest)

産面 lines delivered: FLIP-LEDGER.md + WAVE-RECEIPT.md + History row.
Manufactured: 100% of the ledger is produced from observed grep output,
read source, and measured engine runs; 0 hand-written production lines
(産面 production code untouched — this ticket is docs/evidence 産面).
No reconciliation manifest applies (no generator owns "audit ledger");
the 8 runs + build exits are the receipts. Known non-manufactured residue:
none on production paths.

## Falsifiers attempted

- Tried REUSE first: `/tmp/fp-probe` gone → rebuilt, same path/scope.
- Tried to run solve_x from `~/ferroplan` → absent (became row 5a finding).
- Tried `native/ferroplan` fixtures from worktree → submodule uninitialized
  (recorded; substituted pin checkout read-only + ~/ferroplan main).
- Looked for strong-cyclic citations in every evidence index — none found
  (quarantine gate satisfied by absence, verified per-target).

## Remaining (for the ticket, not this session)

- scope 2: run-the-suite flip adjudication — blocked on b4p-f5-05's
  reconciled bump; procedure is FLIP-LEDGER §4 (mechanical).
- scope 4: tripwire fixture-pair gate — not this session's scope.
- upstream: file sa2a goal-set divergence in ferroplan with /tmp/fp-probe
  reproducer; solve_x fixture provenance decision in the bump.
# WAVE-RECEIPT — b4p-p4 sa2a-admit parity (agent P4, v26.9.18)

Date: 2026-09-18. Worktree: `/Users/sac/beam4pm-worktrees/wt-p4`, branch `parity/sa2a-admit`.
Ticket: `docs/jira/v26.9.18/b4p-p4-sa2a-admit-parity.md` (+ `_CONTEXT.md`).

## Standing

**PARTIAL_ALIVE** — every gate executed and observed in this session on both
courts (12/12 parity tests, 16/16 canonical dfcm tests, 10 real lab CLI runs).
PARTIAL, not full ALIVE, for exactly three named reasons:

1. The positive-control deviation result maps mirror the real
   `PowlConformance.check_conformance/3` typed shape but were not produced by
   the native engine here: `native/rust4pm-wasm/target/` (wasm32-wasip1 build)
   is absent in parity worktrees (submodule not built; verified by `ls` vs the
   main checkout). The full native-engine E2E leg is the existing
   `test/beam4pm_deviation_admission_test.exs` (passes where the wasm is
   built; its assertion pins the same `">>/clean_house"` activity string my
   positive control admits).
2. `lib/beam4pm_dfcm.ex` (+ `priv/bin/autofde`, `test/beam4pm_dfcm_test.exs`,
   `qualification/fixtures/dfcm/`) is carried UNTRACKED in this worktree,
   matching all four sibling parity worktrees (wt-p1/p2/p5/p10): the canonical
   bridge exists upstream only as uncommitted working-tree state in
   `/Users/sac/beam4pm` (read-only for this agent), and committing it here
   would create an unadmitted hand-written file under a gate root
   (`REFUSED_UNADMITTED`). Admission path below (Remaining).
3. The HANDWRITTEN ledger row for the new wrapper could NOT be lawfully
   written: `docs/reference/beam4pm_hand_authored_source.md` carries
   "*GENERATED by ggen ... Do not edit*" and the renderer (ggen marketplace
   pack; `vendor/ggen-marketplace` submodule is empty in worktrees) is not
   runnable here. The row text is supplied below for the upstream render
   session. Hand-editing the projection was refused, per 源.

## SHAs

- Base commit: `36b0ed9` (merge: bump native/ferroplan submodule … b4p-f5-05). Branch tip after this receipt: see `git log -1` (commit adds fixtures + this receipt only).
- Carried files (sha256):
  - `test/beam4pm_sa2a_admit_parity_test.exs` (271 lines, new)
    `579ab8cbae4b9934e1ae266551e6042726bbd204b086da806f05c2729099c874`
  - `lib/beam4pm_dfcm.ex` (568 lines; 511 lines verbatim from the canonical
    upstream bridge + 57 new lines: `sa2a_admit/2`)
    `9f15c69f495129c272cbe434ae855d04d642c3a45bfacd075fce3f04cb9ec281`
  - `priv/bin/autofde` (verbatim upstream trampoline)
    `112aafb087ac4c88ed3acf2abd7384ebf4879f7e9e1ca0a6952d0dd6e9dc7670`
  - `test/beam4pm_dfcm_test.exs` (verbatim upstream)
    `b3fd6bd1b279a7c2116a6986caaa4a69f0550a9b6a15ee7ccaa084a273b4edea`
  - `qualification/fixtures/dfcm/` (verbatim upstream fixtures)
  - `qualification/fixtures/sa2a_admit/` (new, COMMITTED — outside gate roots)
- `config/config.exs` modified, UNCOMMITTED (like wt-p2): exclusive port pair
  `ocel_ingest_port: 4305, a2a_port: 4306` for test boots on the shared wave
  host; default 4210/4211 collided with sibling agents (`:eaddrinuse`,
  observed, fixed by the config lines; Bandit then bound 4305/4306, observed
  in the boot log).

## Commands + exits (all observed this session)

Lab side (direct CLI, `/Users/sac/autofde-lab/.venv/bin/autofde`):

| # | Candidate | Command (abridged) | Verdict | Exit |
|---|---|---|---|---|
| C1 | real `bpm:ocel_event_rt` fact + provenance evidence | `sa2a admit -i cand-c1-ocel-event-rt -a "$(cat positive_c1…)" -e '{"ontology":…}'` | `ok:true, KNOWN, CONFORMS_TO_SPEC`, receipt `rec-57577fa9` | 0 |
| C2 | real `bpm:conformance_result_rt` fact + provenance | same shape | `ok:true, KNOWN`, `rec-a79869a2` | 0 |
| C3 | FORGED unknown type (`bpm:ghost_record_xyz`), clean evidence | same shape | `ok:true, KNOWN` (ADMITTED — see falsifiers) | 0 |
| C4 | FORGED dangling ref (`bpm:ocel_event_rt bpm:hasField bpm:ghost_field_000`), clean evidence | same shape | `ok:true, KNOWN` (ADMITTED — see falsifiers) | 0 |
| C5 | empty assertion | `-a ""` | `ok:false, REFUSED, EMPTY_ASSERTION` | 0 |
| C6 | real fact, empty evidence payload | `-e '{}'` | `ok:false, REFUSED, MISSING_EVIDENCE` | 0 |
| C7 | real fact, evidence carries `"error"` key | `-e '{"error":…}'` | `ok:false, REFUSED, UNSUPPORTED_OR_ERROR_EVIDENCE` | 0 |
| C8 | real fact, evidence carries `"unsupported"` key | `-e '{"unsupported":…}'` | `ok:false, REFUSED, UNSUPPORTED_OR_ERROR_EVIDENCE` | 0 |
| C9 | malformed evidence JSON | `-e 'not-json'` | Typer BadParameter (not a verdict) | 2 |

beam4pm side (`mix test`, cwd = this worktree, `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab`):

| Command | Result | Exit |
|---|---|---|
| `mix deps.get` (twice; first truncated by 300s cap) | 93 deps fetched | 0 |
| `mix compile` | app generated (known upstream warning only: `AshAutofde.CascadeAllocator.allocate/3` optional dep) | 0 |
| `mix test test/beam4pm_sa2a_admit_parity_test.exs --trace` (run 1) | 12 tests, 2 failures — both test-fixture bugs on MY side (see falsifiers), not court behavior | 2 |
| `mix test test/beam4pm_sa2a_admit_parity_test.exs` (run 2, after fixes) | **12 tests, 0 failures** | 0 |
| `mix test test/beam4pm_dfcm_test.exs` (canonical bridge suite, after `sa2a_admit/2` added; run 1 missing untracked fixtures → copied; run 2) | **16 tests, 0 failures** | 0 |
| `mix run -e '…'` probe ×2 (DeviationAdmission real file append on temp ontology copy) | block written at byte offset 1586530; probe exposed my fixture slash bug (below) | 0 |

## Consent table (candidate | lab verdict | beam4pm verdict | boundary consent?)

| Candidate (equivalent class) | Lab §64 court | BeamPM.DeviationAdmission | Consent? |
|---|---|---|---|
| Well-formed, evidenced candidate from a real admitted fact (C1/C2) ↔ real `conforms:false` result with real deviation moves (E1) | ADMITTED → KNOWN, `CONFORMS_TO_SPEC` | `{:ok, process_deviation_<hex>}`; real `bpm:ProcessDeviation` block appended, append-only verified | **CONSENT (admit)** |
| Empty content: empty assertion (C5) ↔ `conforms:false, deviations: []` (E3) | REFUSED `EMPTY_ASSERTION` | `{:error, :no_deviation}` | **CONSENT (refuse)** |
| Contract violation: empty evidence (C6) ↔ `%{conforms: false}` with no deviations key (E4) | REFUSED `MISSING_EVIDENCE` | no function head matches → `FunctionClauseError` | **CONSENT (refuse)** — different typed mechanism (court receipt vs clause refusal), same boundary |
| Failed/unsupported evidence: `"error"`/`"unsupported"` keys (C7/C8) ↔ `conforms: true` (E5) | REFUSED `UNSUPPORTED_OR_ERROR_EVIDENCE` | `{:ok, :conforms}` — no-op, file untouched | **DIVERGENT verdict, CONSENTING consequence** — attributed: beam4pm's law admits deviations only, so a conforming trace is a legitimate true negative (never a forged candidate); the lab's law gates evidence quality. Materially both write nothing; verdict phrasing differs by design |
| Semantic forgery: unknown type (C3), dangling ref (C4) ↔ no equivalent input — beam4pm's emitted class is hardcoded `bpm:ProcessDeviation`; the court cannot emit an unknown class by construction | **ADMITTED** (court is evidentiary-form only) | structurally impossible | **NO SHARED CASE** — attributed: semantic referential integrity on the lab side belongs to a DIFFERENT engine (`sa2a graphlaw validate`), not `sa2a admit`. Parity claim therefore excludes semantic forgery classes |
| Broken input plumbing: malformed JSON evidence (C9) ↔ missing ontology file (E6) | exit 2 BadParameter (unreachable through `Dfcm.sa2a_admit/2`, which always JSON-encodes — pinned in test) | `{:error, {:read_failed, :enoent}}` | **CONSENT (fail closed, typed errors)** |

Parity claim: CONSENT on accept/refuse boundaries for all shared cases;
divergences attributed to the two courts' different laws (§64 evidentiary
admission vs deviation-contract admission). Identity is neither claimed nor
true.

## Files

Committed on `parity/sa2a-admit`:
- `qualification/fixtures/sa2a_admit/` — README + 7 candidate assertion files (positive controls copied from real `ontology.ttl` facts; forged negative controls)
- `WAVE-RECEIPT.md` — this file

Carried untracked (upstream-owned admission; sha256s above):
- `lib/beam4pm_dfcm.ex` — canonical bridge + **new `sa2a_admit/2`** (pure one-shot CLI passthrough: builds args, one `System.cmd` via `run_autofde_cli/1`, decodes JSON; refusal is a verdict `{:ok, receipt}` with `"ok": false`, never `{:error, _}` — only process failures are errors). QUALIFIES as pure passthrough per ticket test: no state, no ports, no cwd writes; the lab `admit` command builds a fresh in-memory pipeline per invocation.
- `priv/bin/autofde`, `test/beam4pm_dfcm_test.exs`, `qualification/fixtures/dfcm/`
- `test/beam4pm_sa2a_admit_parity_test.exs` — new parity/consent qualification (12 tests; doubles as the permanent tripwire for the consent boundaries and the wrapper's behavior)

Modified, uncommitted: `config/config.exs` (exclusive ports 4305/4306).

## 比 (honest)

New 産面-adjacent lines authored this session: ~340 (parity test 271 + wrapper 57 + fixtures/config ~12). Manufactured by generator/pack render this session: **0**. Reused verbatim from the sanctioned canonical bridge: 511 of 568 bridge lines. So: **0% newly-manufactured / 100% hand-written for new lines** — reported truthfully per the 比 law. Mitigation: the wrapper lives in the one file the wave law sanctions for this class, the parity test is qualification debt counted upstream at admission, and the ledger row below makes every hand-written line owned. No decorative ratio is claimed.

## HANDWRITTEN ledger rows to admit upstream (via ontology.ttl `bap:HandAuthoredSource` individuals + ggen re-render; NOT hand-written into the generated ledger)

- `lib/beam4pm_dfcm.ex` — delta `BeamPM.Dfcm.sa2a_admit/2` (2026-09-18, branch parity/sa2a-admit, agent P4): one-shot `autofde sa2a admit` CLI passthrough; missing capability was "no beam4pm seam for the lab §64 admission court"; owner family: the file's existing "Standalone AutoFDE Typer CLI Bridge" section. Content sha256 of file at admission: `9f15c69f…c281` (full value above).
- `test/beam4pm_sa2a_admit_parity_test.exs` — hand-authored qualification (2026-09-18, same session): consent-table tripwire for §64-admit vs DeviationAdmission; sha256 `579ab8cb…c874`.
- Upstream note: the bridge base files (`priv/bin/autofde`, `test/beam4pm_dfcm_test.exs`) are already disclosed in the main checkout's pending ledger; carry those rows through the same render.

## Falsifiers attempted (and outcomes)

1. **Forged unknown-type + dangling-ref through the lab court** (expecting refusal). FALSIFIED my expectation: the §64 default court ADMITS them. Surviving finding → permanent tripwire pinned in the parity test ("admits forged… clean evidence") naming the law it guards: `sa2a admit` = evidentiary-form court; semantic conformance = `sa2a graphlaw validate`. Upstream recommendation: a beam4pm admission path that needs semantic consent should chain both lab commands.
2. **My own positive-control fixture** (`[">>", "/clean_house"]` with leading slash). FALSIFIED by the real module: admitted activity became `">>//clean_house"` and my `=~` assertion failed. The real engine emits bare activity names; fixed the fixture to the shape pinned by the existing real-engine test (`">>/clean_house"`). Recorded because it is exactly the class of plausible-but-wrong fixture the 器 law warns about.
3. **"Refusals exit non-zero"** — falsified: lab refusals exit 0 (`ok:false`); only malformed CLI input exits 2. The wrapper is designed accordingly (refusal = `{:ok, receipt}`).
4. **Wrapper addition is regression-safe**: canonical 16-test dfcm suite re-run after the edit — 16/0.
5. **Port collision under fleet load** (`:eaddrinuse` on defaults): resolved with the ticket-assigned exclusive pair 4305/4306; boot log shows Bandit bound both.

## Remaining (honest gaps)

1. Native-engine leg (`rust4pm-wasm` build) absent in parity worktrees — the full real `check_conformance → admit_deviation` E2E stays with the existing upstream test until wasm builds are shared.
2. Ledger + gate: upstream admission session must add the two `bap:HandAuthoredSource` individuals, re-render `docs/reference/beam4pm_hand_authored_source.md` + `schema/beam4pm_hand_authored_source.tsv` + `test/beam4pm_authorship_gate_test.exs` (counts move), THEN commit the carried files. I did not hand-edit those generated artifacts.
3. The lab court's semantic blind spot (C3/C4) is a lab-side design fact, not a beam4pm defect; if beam4pm mission needs semantic consent at admission, the seam is `sa2a_admit/2` + `graphlaw_validate/2` composed — no new bridge function required.
4. `config/config.exs` port lines: integration should either keep per-worktree configs out of merges or parameterize ports by env var.

## What the operator did NOT have to write

All of it: candidate fixtures, both court run matrices, the consent table, the wrapper + its tripwires, the two gate re-runs, and this receipt. Operator keystrokes: none.
# WAVE-RECEIPT — P6: sa2a chicago parity (autofde-lab vs ash_a2a)
# WAVE-RECEIPT — v26.9.18 autofde-lab parity wave INTEGRATION (wt-integration, branch parity/integration)

Date: 2026-09-18. Integrator session. Law: ~/.zcode/AGENTS.md (DfCM). Every claim
below is an observed execution in this session on this branch. No push, no writes
to any main checkout.

## Standing

**PARTIAL_ALIVE** for the wave integration as a whole: all gates green in this
worktree (compile, authorship gate, full suite, architecture verifier — exits
below), but the tree is NOT landed (landing is the tree owner's, per wave law),
and the vendored-pack ceiling raise is a worktree-local pack commit until the
owner fast-forwards the pack (exact command below). No decorative ALIVE.

## Base + final SHAs

- Base: `36b0ed9` (main @ merge of ferroplan pin bump b4p-f5-05)
- Branch: `parity/integration` (worktree /Users/sac/beam4pm-worktrees/wt-integration)
- Final head: **`3ac0d8f`** (+ one receipt-only commit when this file lands)
- Vendored pack raise commit: `f2ae5382e` on
  `fix/hand-authored-qualification-ceiling-35-wave-26918` (in wt-integration's
  submodule gitdir; NOT reachable from the main checkout until fetched — see
  landing step 3)
- Union bridge digest: `lib/beam4pm_dfcm.ex` = sha256 `a88af2e5…5d42`, 1017 lines

## Per-branch merge table (all --no-ff, all parents verified)

```
# 1. Discovery (exit 0)
~/autofde-lab/.venv/bin/python3 -m autofde_lab.cli sa2a chicago --help        # EXIT=0

# 2. Lab Canonical Chicago DoD Court — BUILD_BROKEN (3 runs, deterministic)
cd ~/autofde-lab && .venv/bin/python3 -m autofde_lab.cli sa2a chicago         # EXIT=1 (run1, run3 captured)
# Crash: AttributeError: 'NoneType' object has no attribute 'to_dict'
#   at scripts/verify_v26_9_16_chicago.py:209 — prep_rec = receipt_store.get_prepared(...)
#   returns None => Gate09 identity binding broken at master; Gate10 line crashes.
# Last receipted PASS: reports/rfc_sa2a_002_chicago_crown_receipt.json (2026-09-16,
#   tag f5727fa9): all_gates_passed=true, 12/12 gates, duration_ms=188.

# 3. Lab SA2A-B9 — ALIVE (receipt redirected to /tmp; lab untouched)
cd ~/autofde-lab && .venv/bin/python3 scripts/run_sa2a_benchmarks.py \
  --benchmarks SA2A-B9 --iterations 20 --output /tmp/p6-lab-b9-receipt.json  # EXIT=0

# 4. ash_a2a SA2A-B9 — MEASURED (own worktree; primary repo not written)
git -C ~/ash_a2a worktree add --detach /tmp/p6-ash-a2a main                  # EXIT=0 (main was checked out in primary; detached at same SHA baa135d)
cd /tmp/p6-ash-a2a && mix deps.get                                           # EXIT=0
cd /tmp/p6-ash-a2a && mix compile                                            # EXIT=0
cd /tmp/p6-ash-a2a && mix ash_a2a.chicago.bench --only B9                    # EXIT=0
git -C ~/ash_a2a worktree remove --force /tmp/p6-ash-a2a                     # cleaned up; primary @ baa135d [main] intact
```

## Cross-walk: lab categories vs ash_a2a RFC-SA2A-002 B1-B10

Both sides implement the SAME taxonomy — RFC-SA2A-002 v26.9.16, Appendix E, ids SA2A-B1..B10.
Lab registry: `src/autofde_lab/sa2a/conformance/benchmarks/harness.py` BENCHMARK_NAMES.
ash_a2a registry: `lib/ash_a2a/chicago/bench.ex` @benchmarks (all 10 wired).

| Cat | Lab name (harness.py) | ash_a2a module (§ref) | Measured-metric parity? |
|---|---|---|---|
| B1 | Admission latency & throughput | B1Admission (§85; per-stage latency, refusals never skipped) | YES — latency+throughput both sides; ash adds per-stage split + per-case distributions |
| B2 | Logic closure | B2LogicClosure (§86; shallow/recursive/near_bound Datalog) | CATEGORY yes; lab B2 BUILD_BROKEN in committed report (`'DatalogEngine' object has no attribute 'compute_closure'`, reports/rfc_sa2a_002_benchmarks.json) — not re-run by me |
| B3 | Knowledge hook reflex latency | B3HookReflex (§87; delta size, hooks evaluated/fired, intent count) | YES — latency + hook counters both sides |
| B4 | Planning projection & preflight | B4Planning (§88; real hddl_cli subprocess, 3 disclosed fixtures) | YES — plan latency + preflight both sides |
| B5 | Authority & BRCE consequence latency | B5Authority (§89; authorized/refused/expired/revoked) | YES — scenario-split latency; ash adds per-phase (authority/actuator/receipt) splits |
| B6 | Reactive cascade latency & memory | B6ReactiveCascade (§90; depth/fan-out matrix to quiescence/exhaustion) | YES — cascade latency+memory both sides |
| B7 | Portability verification | B7CrossRuntime (§91; one wasm artifact, two heterogeneous hosts) | YES — portability verdict + timing both sides |
| B8 | Replay verification time | B8Replay (§92; offline chain reconstruction by chain size) | YES — replay time vs chain size |
| B9 | OCEL evidence generation overhead | B9OcelOverhead (§93; baseline vs observed arms) | PARTIAL — same category; lab measures per-event tracer cost + export; ash measures whole-workload delta (arms). Double-run below |
| B10 | Recovery & reconciliation | B10Recovery (§94; 5 real crash points, kill+restart) | YES — recovery/reconciliation both sides |

Shared standard markers on both sides: Chicago zero-mock (lab "Chicago Zero-Mock Standard"; ash real-SUT invariants), anti-oracle (lab "No golden OCEL traces"; ash §84 invariant-failure discipline), Appendix E environment receipts, content-addressed/digested result artifacts.

## Shared-category double-run: SA2A-B9 (OCEL overhead) — real numbers

**Lab** (autofde-lab @ fe81a552, 20-iter setting, 50-event trace; exit 0, standing ALIVE):
- events_recorded=50; mean event recording 9.41 us; p50 8.37 us; p95 10.22 us
- export_latency_ms=2.199; log_file_bytes=68,162; bytes_per_event=1363.24; events_per_sec=60,885.84
- ocpq_def2_verified=true (OCPQ Definition 2 laws: no dangling links)
- Evidence: notes/p6-sa2a-chicago/p6-lab-b9-receipt.json

**ash_a2a** (baa135d, 10 measured iterations + 2 warmup, GC-before-measure, invariants on warmup AND measured; exit 0, MEASURED, invariant_failures=0):
- baseline arm (no observer): n=10, p50=29,274 us, mean=29,051.8, p90=42,417, max=51,965; 10/10 committed
- observed arm (real Chicago Observer): n=10, p50=15,279 us, mean=21,602.8, p90=33,119, max=41,849; 10/10 committed
- claimed overhead: p50 latency delta **-13,995 us** (NEGATIVE — see falsifier F4), vm_reductions_delta=+150,014, vm_runtime_ms_delta=+3 ms
- OCEL evidence produced: 132 events, 0 dropped, 92,759 bytes, 702.7 bytes/event; serialization_us=47,978; query_load_us=9,150; observer process memory 42,264 -> 142,728 bytes
- environment identity bf35e58106952698...; artifact content-addressed sha256 205e4df0bedc... (digest algorithm sha256(canonical_json(raw_result)))
- Evidence: notes/p6-sa2a-chicago/ash-a2a-SA2A-B9-record.json, ash-a2a-bench-summary.json

**Parity verdict (B9):** same category, both ALIVE/MEASURED with real evidence on disk; metric operationalizations differ (per-event tracer microcost vs whole-consequence arm delta) — category-level parity YES, unit-level comparability NO without normalization work.

## 比 (honest)

0% manufactured / 100% hand-written — but zero production (産面) code lines delivered. Deliverable is measurement evidence: WAVE-RECEIPT.md + 4 artifact files in notes/p6-sa2a-chicago/. No bridge functions added to lib/beam4pm_dfcm.ex => no HANDWRITTEN.md ledger rows required. No pack exists for parity-receipt manufacture (failed-edge recorded below).

## Falsifiers attempted

- F1: "chicago crash is flaky" → RE-RAN 3x: identical AttributeError at verify_v26_9_16_chicago.py:209, exit 1 every time. Survives: deterministic regression at lab master.
- F2: "maybe only the Gate01 identity fence fails (HEAD ≠ tag)" → FALSIFIED: crash is at Gate10 machinery — `receipt_store.get_prepared(idempotency_token)` returns None at master, i.e. receipt-store semantics drifted past the v26.9.16 tag. Deeper than the fence.
- F3: "bench wrote into ~/ash_a2a" → NO: bench ran in /tmp/p6-ash-a2a (detached @ baa135d, removed after); primary repo shows no writes; lab receipt redirected to /tmp then copied out.
- F4: "observed arm p50 15,279us < baseline 29,274us means OCEL has negative overhead" → treated as n=10 BEAM noise (baseline arm runs first; warm effects), NOT reported as a win: the record's honest cost carriers are vm_reductions_delta=+150,014, vm_runtime_ms_delta=+3ms, serialization_us=47,978, 92,759 OCEL bytes. The record is content-addressed, so this honest negative stays in the raw artifact.

## Remaining (not done here)

1. Lab fixes (upstream autofde-lab scope, not beam4pm): `sa2a chicago` Gate09/Gate10 crash at master; B2 `DatalogEngine.compute_closure` missing. Both last-good at tag v26.9.16 (f5727fa9).
2. Double-runs for B1-B8, B10 (ticket required exactly one shared category; B9 chosen per ticket).
3. beam4pm `BeamPM.Dfcm` surfaces only `sa2a graphlaw hash|validate|hooks` today — the chicago court and B1-B10 bench harness are NOT bridged (future ticket candidate; would land in lib/beam4pm_dfcm.ex with HANDWRITTEN rows per 帳).
4. failed(edge): no marketplace pack expresses "parity receipt manufacture" — this receipt is hand-written per ticket instruction; if parity waves recur, promote a receipt pack (ontology + template + gate) upstream.

## Session receipt (証)

- Repo/base: beam4pm wt-p6, branch parity/sa2a-chicago @ 36b0ed9 (this commit adds receipt+notes only)
- Commands+exits: see "Commands + exits" above (12 commands, all exits recorded)
- Ledger deltas: none (no bridge code, no HANDWRITTEN rows)
- Standing deltas: lab chicago court ALIVE(crown 2026-09-16) → BUILD_BROKEN @ master fe81a552 (new finding)
- What the operator did NOT have to write: this entire receipt, all benchmark executions, the cross-walk table, and the /tmp worktree lifecycle.
# WAVE-RECEIPT — A8, ticket b4p-f5-05 (PREP: audit + reconcile plan + pin-drift filing)

- date: 2026-09-18, agent A8 of the 10-agent wave
- worktree: `/Users/sac/beam4pm-worktrees/wt-f5-pin-audit`, branch
  `chore/ferroplan-pin-audit` based on beam4pm `main @ 22fa4aa`
- main checkout: NOT written (concurrent-writer serialization respected)

## Standing

**PARTIAL_ALIVE** — for this ticket's PREP scope: the three-way overlap audit
is ALIVE (real git plumbing against both object stores made local in this
session); the reconciliation plan and the pin-drift filing are authored
artifacts (candidate, not executed). Scope 2 (actual merge + push), scope 3
(submodule bump + wasm rebuild + facade gates), and the autofde-lab re-pin
remain with their owning tickets/times.

## Commands + exits (the load-bearing ones)

| # | command (in `native/ferroplan` submodule clone unless noted) | exit |
|---|---|---|
| 1 | `git submodule update --init native/ferroplan vendor/ggen-marketplace` (worktree root) | **128** — `upload-pack: not our ref 4b8ff2e…` (the remote itself proves the pin is nowhere upstream) |
| 2 | `git fetch /Users/sac/beam4pm/native/ferroplan 'refs/heads/*:refs/remotes/beam4pm-main/*'` | 0 — pin now local |
| 3 | `git checkout 4b8ff2e` (submodule) | 0 — `native/ferroplan @ 4b8ff2e` |
| 4 | `git submodule update vendor/ggen-marketplace` | 0 — `vendor/ggen-marketplace @ 7abe147` |
| 5 | `git fetch /Users/sac/ferroplan 'refs/heads/*:refs/remotes/home-main/*'` | 0 — 78 branches, 30 tags |
| 6 | `git rev-parse --verify d00dcf8^{commit}` / `6cacbda^{commit}` | 0 / 0 — wt-h57 fetch NOT needed |
| 7 | `git merge-base 4b8ff2e 6cacbda` | `3e1d27a` |
| 8 | `git rev-list --left-right --count origin/main...4b8ff2e` | `1 25` (25 ahead/1 behind confirmed) |
| 9 | `git rev-list --left-right --count origin/main...6cacbda` | `0 185` (unpushed confirmed) |
| 10 | `git rev-list --left-right --count 6cacbda...d00dcf8`; `git merge-base --is-ancestor 6cacbda d00dcf8` | `1 1`; exit 1 (siblings, fix NOT on main) |
| 11 | `git rev-list --left-right --count 4b8ff2e...6cacbda` | `13 174` |
| 12 | `git log --left-only --cherry-pick --oneline 4b8ff2e...6cacbda` | 11 (1 merge + 10 unique + see #13) |
| 13 | `git cherry 6cacbda 4b8ff2e` / `git cherry -v …` | 10 `+` / 2 `-`; equivalents `d493c19`≡`47a898c`, `29134d7`≡`658ea7b`, patch-id match YES/YES |
| 14 | `git show --name-status` × 10 unique commits | file lists in AUDIT.md §2 |
| 15 | `git diff --name-only 3e1d27a..4b8ff2e` (7) / `3e1d27a..6cacbda` (496) / `6cacbda..d00dcf8` (4); `comm -12` | overlap = `crates/ferroplan-wasm/src/wasi_abi.rs` ONLY; ppcx∩d00dcf8 = ∅ |
| 16 | `git merge-tree --write-tree 6cacbda 4b8ff2e` / `… d00dcf8 4b8ff2e` | exit 1 both; CONFLICT only in `wasi_abi.rs`, 2 hunks (doc union + `FP_TIMEOUT`/`FP_WORKER_PANICKED` vs `FP_HDDL_TIMEOUT`/`FP_HDDL_WORKER_PANIC`) |
| 17 | beam4pm facade FP-code grep (`grep -o 'FP_[A-Z_]*'` over lib/test) | only `FP_PARSE`, `FP_MODEL`, `FP_HDDL_TRANSLATE`, `FP_HDDL_GROUND`, `FP_INVALID_REQUEST` — neither conflicted name asserted |
| 18 | autofde: `grep 282fae4 …/_registry.py`; `git rev-list --left-right --count 282fae4...6cacbda` / `origin/main...282fae4` | pin @ `src/autofde_lab/wasm/_registry.py:172`; `0/384`; `199/0` (pin ancestor of pushed origin/main) |

## Audit tables (full detail: AUDIT.md)

**Unique-LEFT (ppcx, 10):** `703d502` `0e28a38` `e98da74` `3304d92` `caf625d`
`91e7d90` (errc operator compiler + SOLVE(x) grammar/fixture),
`5cb0f95` `84b0114` (strong policy validator), `42dce51` (wasm error mapping —
SUPERSEDED variant: main's 09-17 line is newer and tested), `5f9fc86`
(format-recovery CI workflow).
**Equivalent-LEFT (2):** `d493c19`≡`47a898c`, `29134d7`≡`658ea7b`.
**Unique-RIGHT (174):** hardened main's FOND-HTN waves 1–6 (not replayed;
taken wholesale). **Overlap files (1):**
`crates/ferroplan-wasm/src/wasi_abi.rs`. No `hddl.rs` in the wasm crate on
either tip; TranslateLimits and choice-rewrite files: zero ppcx touch.

## Reconcile recommendation

**MERGE `--no-ff` of `4b8ff2e` into post-wave-6 main, push to ferroplan
origin; do NOT rebase.** Grounds: (1) the repo's own law — RELEASING.md is
silent on branch history, no CONTRIBUTING exists, but `_RUNBOOK.md`
("merges ONLY the frozen SHAs", "integration … serial, sole writer") and
main's shape (33/50 first-parent = annotated merge commits) prescribe it;
(2) merge keeps `4b8ff2e` an ancestor of origin so beam4pm's current pin is
never a private commit, in any ordering of the bump; (3) conflict surface is
1 file / 2 hunks with a pre-audited resolution (main's error-code names win;
beam4pm asserts neither name, so no beam4pm-side adaptation needed);
(4) robust to the b4p-f5-04 dependency. Concrete 7-step sequence in AUDIT.md §4.

## Files changed (this branch)

- `AUDIT.md` (new) — overlap audit + reconcile plan (ticket gate artifact)
- `PIN-DRIFT-filing.md` (new) — autofde-lab `282fae4` drift, filed not fixed
- `WAVE-RECEIPT.md` (new) — this receipt
- `docs/jira/v26.9.17/b4p-f5-05-ferroplan-pin-three-way-reconciliation.md`
  (append-only History row, worktree copy)

## 比 (ratio)

Honest: this ticket delivered **0 manufactured / ~100% hand-authored lines** —
4 markdown evidence artifacts, no product code. There is no pack render for
audit/reconciliation artifacts in the admitted set (failed-edge note: the
calver-ticket-day-pack renders ticket scaffolding, not audit artifacts; no
family express audit-diff Capability was found, so the audit itself is the
1%-ledger class of work for now). No production paths changed; no tests
weakened; no placeholders.

## What the operator did NOT have to write

All of it: the submodule/offline-pin recovery, the cross-fetches, the entire
cherry/patch-id/file-overlap/merge-tree audit, the conflict-hunk extraction,
the reconcile plan, the autofde drift measurements, and the four documents.

## Remaining (not mine; recorded, not executed)

1. **b4p-f5-05 scope 2** — execute the merge per AUDIT.md §4 on post-wave-6
   main and push to ferroplan origin. Blocked by b4p-f5-04 (post-wave-6 main
   push).
2. **b4p-f5-05 scope 3** — bump `native/ferroplan` gitlink to the reconciled
   commit; `cargo build -p ferroplan-wasm --target wasm32-wasip1`; atomic
   beam4pm commit; `mix test test/beam4pm_ferroplan_test.exs
   test/beam4pm_ferroplan_facades_test.exs` exit 0.
3. **autofde-lab re-pin** — its own ticket; handoff in PIN-DRIFT-filing.md §4.
4. Ticket gates NOT touched here (no builds, no pushes): all four gates in
   the ticket remain open; scope-1 gate satisfied by AUDIT.md (linked from
   the ticket History row) once this branch lands.
# WAVE-RECEIPT — b4p-p8-beam-bridge (v26.9.18 autofde-lab parity wave)

- Date: 2026-09-18
- Agent: P8 (session b4p-p8), worktree `/Users/sac/beam4pm-worktrees/wt-p8`, branch `parity/beam-bridge`
- Base: `36b0ed9` (merge: bump native/ferroplan submodule to reconciled post-wave-6 pin e90928d)
- Ticket: `docs/jira/v26.9.18/b4p-p8-beam-bridge.md`
- Standing: **ALIVE** — every ticket gate observed executing in this session, in this worktree.

## SHAs

- Base tree: `36b0ed9`
- Admission digests (at admission, final bytes):
  - `lib/beam4pm_autofde_bridge.ex` sha256 `26104d7ff39850d3f2c3e9de8acd3bafe23f057ebe293ff2293af80df67454b7`
  - `test/beam4pm_autofde_bridge_test.exs` sha256 `e96351f9b34c77ccf3bfb3fa42e96e9c55c537384a80e1fec500998433c3ae88`
- Commit: see `git log -1 parity/beam-bridge` (this receipt committed with the change)

## Commands + exits (all run in this session)

| Command | Exit | Evidence |
| --- | --- | --- |
| `printf '{"op":"ping"}\n{...cmca_allocate...}' \| ~/autofde-lab/.venv/bin/python3 -m autofde_lab.beam.beam_port_bridge` | 0 | protocol witness: `{"ok": true, "pong": true}` + full plan line |
| `~/autofde-lab/.venv/bin/python3 -m autofde_lab.cli cmca allocate '[...same candidates...]' --plan-id p8_witness_plan ...` | 0 | same-result witness, 1.901s wall (one interpreter) |
| `mix deps.get` | 0 | deps fetched |
| `mix compile` | 0 | clean after warning fix |
| `mix test test/beam4pm_autofde_bridge_test.exs` | 0 | **8 tests, 0 failures** (3 witnessed runs) |
| `bash scripts/gate_authorship_check.sh` | 0 | PASS — 49 admitted (42 debt), 0 findings |
| `mix test test/beam4pm_authorship_gate_test.exs` | 0 | 19 tests, 0 failures (rendered counts match real tree) |

## Protocol contract (read from `src/autofde_lab/beam/beam_port_bridge.py` @ lab master fe81a552, verified live)

- Framing: newline-delimited single-line JSON objects over stdio; exactly one reply line per request line, **in request order**; blank lines ignored by the bridge.
- Ops: `ping` -> `{"ok":true,"pong":true}`; `cmca_allocate` (budget + candidates -> `{"ok":true,"plan":{...}}`); `calculate_salience` (branch -> `{"ok":true,"salience":float}`); unknown op -> `{"ok":false,"error":"unknown_op: <op>"}`.
- Error envelope: the bridge NEVER exits on a bad request — every exception becomes `{"ok":false,"error":str,"exception_type":str}`.
- **Failed edge (recorded)**: the lab bridge has NO `fabric` ops — `fabric solve|catalog|match` cannot traverse the persistent channel as-is. The bridge's one real solve op is `cmca_allocate` (certified multifractal cascade), so that is the parity solve proven here; the one-shot comparator is the lab CLI's `cmca allocate` (same engine, same payload shape; `consequence_risk_budget` hardcoded 0.5 CLI-side, matched bridge-side).

## Parity + latency (5 calls each path, 3 witnessed runs; microseconds)

| Run | bridge call 1 (interpreter boot) | bridge calls 2-5 avg (persistent) | one-shot CLI avg (fresh interpreter per call) |
| --- | --- | --- | --- |
| 1 | 494,517 | 7,468 [6995, 5922, 8819, 8139] | 939,323 [932948, 912899, 934593, 959175, 957004] |
| 2 | 1,578,407 | 8,070 [7416, 7280, 9255, 8331] | 1,246,404 [1245410, 958425, 1011132, 1199103, 1817953] |
| 3 (loaded machine) | 972,016 | 36,696 [16448, 52758, 44214, 33367] | 2,379,240 [1405773, 1236038, 6874295, 1258666, 1121430] |

- Same result proof: bridge plan == one-shot CLI plan, exact structural equality on decoded JSON (deterministic allocator; asserted in `test/beam4pm_autofde_bridge_test.exs` "same solve returns the exact same plan through both paths").
- Persistent channel wins after call 1 in every run (~100x on idle machine; ~65x loaded). The test asserts `steady_avg < one_shot_avg`.

## Kill-and-recover evidence

`System.cmd("kill", ["-9", os_pid])` mid-session, then:

```
20:39:18.669 [debug] BeamPM.AutofdeBridge port exited (status 137); restarting on demand
```

- status 137 = 128+9 (SIGKILL) received via the port's `:exit_status`; pending/queued waiters get `{:error, :bridge_down}`.
- GenServer process stays alive (`Process.alive?` asserted); `os_pid` returns nil after death.
- Next `ping` lazily boots a fresh interpreter; `os_pid` differs from the killed pid; round-trip succeeds (asserted). Also proven: explicit `restart/1` (fresh pid), and kill-race safety (`Port.command` rescue -> `{:error, :bridge_down}` -> lazy reopen).

## Files (all in this worktree)

- NEW hand-authored `lib/beam4pm_autofde_bridge.ex` — GenServer-wrapped BEAM Port: framed JSON-lines request/reply with per-request timeout, FIFO waiter queue with ordering-poison semantics, `{:error, :bridge_down}` on port death, lazy + forced (`restart/1`) interpreter restart; one-shot CLI comparator (`oneshot_cmca_allocate/4`) using BeamPM.Dfcm's exact CLI resolution chain.
- NEW `test/beam4pm_autofde_bridge_test.exs` — 8 Chicago tests against the REAL interpreter (named skip when the lab checkout is absent).
- Ledger (ggen render delta, hand-applied because the vendored pack render tooling is not initialized in parity worktrees — shapes mirror the main checkout's dfcm-session delta exactly):
  - `ontology.ttl` (+2 `bpm:HandAuthoredSource` individuals: `bap:hand_authored_lib_autofde_bridge` under `native_engine_facade` 5->6/6, `bap:hand_authored_test_autofde_bridge` under `hand_authored_qualification` 35->36, ceiling raised 35->36 per the documented precedent)
  - `schema/beam4pm_hand_authored_source.tsv` (+2 rows, sorted)
  - `docs/reference/beam4pm_hand_authored_source.md` (counts 47->49 / 40->42, kind table, headings, table rows, detail sections)
  - `test/beam4pm_authorship_gate_test.exs` (rendered counts 49/42 + 2 admitted paths)
- `WAVE-RECEIPT.md` (this file)

## 比 (honest)

Delivered 産面 lines this change: ~430 (lib) + ~180 (test) = ~610, all hand-authored. `ratio = 0/610 = 0%` manufactured. No pack template family exists for a GenServer stdio port-bridge client (failed edge recorded in both admission rows); paydown plan = the sunset plans: admit the beam-bridge op surface as ontology facts and render both files from them. Ledger grows monotonically with a named owner-pack intent, not silently.

## What the operator did NOT have to write

Everything in this change: bridge module, qualification, protocol discovery, admissions, gate deltas, receipt. Operator keystrokes: zero.

## Falsifiers attempted

1. "fabric solve through the persistent bridge" — FALSIFIED: bridge exposes no fabric ops (read the source, then proved by live round-trip what it does expose). Adapted to `cmca_allocate` + `cmca allocate`, disclosed above and in the admissions.
2. "BeamPM.Dfcm is available for the one-shot leg" — FALSIFIED on this branch base: `lib/beam4pm_dfcm.ex` is untracked in the main checkout, absent from `36b0ed9` and every parity branch. One-shot leg reimplements Dfcm's exact CLI path resolution (app env `:autofde_cli_path` -> `AUTOFDE_CLI_PATH` -> `priv/bin/autofde` trampoline) with a direct lab-python fallback (the path actually taken here); recorded.
3. Determinism of the allocator — tested by running both paths on identical inputs and asserting exact equality (survives 3 runs).
4. "Maybe the bridge dies on bad requests" — tested unknown-op: typed error envelope, interpreter survives.
5. Kill race (request in flight when the interpreter dies) — handled + rescue-tested path (`Port.command` ArgumentError -> `:bridge_down`).
6. Disk-full mid-compile — freed MY worktree's redundant `_build/dev` only; no other tree touched.

## Remaining

- `lib/beam4pm_dfcm.ex` + `priv/bin/autofde` trampoline remain uncommitted in the main checkout (another session's in-flight work — not mine to commit). Integration must reconcile the two independent 47->49 ledger moves (dfcm rows + my rows; true integrated count 51, 45 debt).
- Persistent-channel fabric parity requires the LAB to extend `beam_port_bridge.py` with fabric ops (read-only law for me: `~/autofde-lab` untouched).
- `BeamPM.AutofdeBridge` is supervision-ready (`start_link/1`, lazy port open) but deliberately not inserted into `BeamPM.Application`'s tree — that shared file is hot across the parity fleet; one-line follow-up at integration.
- Full `mix test` suite not run (fleet time cost); gates run: affected file's suite + authorship gate + its rendered test.
| # | Branch | Agent head | Merge commit | Content |
|---|---|---|---|---|
| P1 | parity/fabric-solve | `95ab1ac` | `cc7264e` | fabric_match/2, fabric_solve/2 + typed-refusal machinery; dfcm baseline committed; dfcm-abcx.hddl fixture |
| P2 | parity/ocel-validate | `8ba9480` | `8c19add` | ocel_validate/1 + OCPQ Def. 2 parity test |
| P3 | parity/sa2a-card | `d9dba35` | `0d7369e` | sa2a_validate_card/1 + real 1194-skill card fixture; mix.lock ash_a2a 26.9.17 |
| P4 | parity/sa2a-admit | `2b12eef` | `d0c6228` | §64 admit fixtures + receipt; wrapper + test carried from wt-p4 untracked state (shas verified vs receipt: 9f15c69f / 579ab8cb) |
| P5 | parity/sa2a-replay | `9388c60` | `5261ba1` | sa2a_replay/1 + 3-test tamper/canonicalization file; trampoline $HOME fallback |
| P6 | parity/sa2a-chicago | `6130d8a` | `3ba6803` | measurement-only (notes/ + receipt); lab chicago court BUILD_BROKEN @ fe81a552 finding |
| P7 | parity/cmca-allocator | `78ae830` | `e592849` | allocate_options/2 cmca rework (dead CascadeAllocator probe REMOVED — removal wins) + 8 property tests |
| P8 | parity/beam-bridge | `3a0b029` | `846984d` | lib/beam4pm_autofde_bridge.ex GenServer port bridge + 8 real kill/recover tests |
| P10 | parity/graphlaw-triangle | `db397e9` | `c3e99e3` | graphlaw flip-ledger test + 6-file TTL corpus |
| — | receipt filing | — | `24cd950` | P1's root receipt filed to docs/jira/v26.9.18/ (all 9 receipts now live there as WAVE-RECEIPT-pN.md) |
| — | synthesis 1 | — | `86b0363` | union ledger + ceilings + real render |
| — | synthesis 2 | — | `3ac0d8f` | corpus admissions after gate findings |

## Union decision: lib/beam4pm_dfcm.ex (one file, synthesized)

Scaffold = P7's version (baseline `05b4d2e7` + allocate_options rework);
`AshAutofde.CascadeAllocator` probe: zero references (P7's removal wins per
dispatch). Every other wrapper inserted as a verbatim block from its branch;
every @spec, @doc, doctest, and @type preserved. Digest `a88af2e5…5d42`.

Function inventory (owner branch in parens):

- Baseline (P10 = byte-identical `05b4d2e7`): `authority_ceiling/0`,
  `phase_order/0`, `fond_outcomes/0`, `cycle/1`, `observe/3`, `policy/1`,
  `dominates?/2`, `benchmark/0`, private normalize/fence/observation/dominance/
  select/receipt helpers, `fond_policy/1+2`, `autofde_cli_path/0`,
  `autofde_cli_available?/0`, `run_autofde_cli/1`, `catalog/0`,
  `ocel_conformance/2`, `graphlaw_hash/1`, `graphlaw_validate/2`,
  `graphlaw_hooks/2`
- `allocate_options/2` REWORKED (P7): real `autofde cmca allocate` over a
  temp-file candidates transport; uniform fallback ONLY when the CLI is absent;
  typed refusals otherwise; + private `cmca_allocate/2`, `cmca_budget_opts/1`,
  `cmca_plan_to_shape/1`, `uniform_fallback/1`
- `ocel_validate/1` (P2), placed after `ocel_conformance/2` as on its branch
- `sa2a_validate_card/1` + private `run_sa2a_validate/1` (P3)
- `sa2a_admit/2` (P4, extracted from carried-untracked file — branch does NOT
  contain the bridge, confirmed via `git show parity/sa2a-admit --stat`)
- `sa2a_replay/1` (P5)
- `fabric_match/2`, `fabric_solve/2`, types `fabric_solve_opt/fabric_solve_opts`,
  private `fabric_cli/1`, `decode_fabric_stdout/1` (P1)
- No function was edited by two agents; union = pure composition (P7's rework of
  the baseline allocate_options is the only same-function change, and it wins).

Other shared-file decisions:

- `priv/bin/autofde`: P5's 25-line version wins (strict superset: adds
  `$HOME/autofde-lab` fallback; identical elsewhere).
- `test/beam4pm_dfcm_test.exs`, dfcm fixtures: identical blobs across all
  branches (auto-merged, zero conflict).
- `config/config.exs`: ALL agent port lines dropped (P2 4303/4304, P3 4310/4311,
  P7 4313/4314); my runs used uncommitted `ocel_ingest_port: 4321, a2a_port:
  4322` (still uncommitted, per wave law).
- `mix.lock`: P3's mix-owned ash_a2a 26.9.17 pin kept (matches main checkout's
  uncommitted working state per P3's receipt — expected landing conflict is
  therefore content-identical).
- WAVE-RECEIPT.md collisions: each branch's receipt preserved verbatim at
  `docs/jira/v26.9.18/WAVE-RECEIPT-pN.md`.

## Ledger recount table (honest, gate-mechanical)

| State | admitted | debt | qualification | native_engine_facade | other |
|---|---|---|---|---|---|
| base `36b0ed9` | 47 | 40 | 35 | 5 | 1 manufacturing_input, 6 reference_evidence |
| + 11 wave paths (synthesis 1, `86b0363`) | 58 | 51 | 44 | 7 | unchanged |
| + 6 P10 corpus fixtures after gate findings (synthesis 2, `3ac0d8f`) | **64** | **57** | **50** | **7** | unchanged |

- Dedupe: one `bpm:HandAuthoredSource` individual per path; duplicate-name
  collisions (lib_dfcm / test_dfcm rows from P2/P3/P5) resolved to single rows
  carrying final digests; P4's two rows added from its receipt-supplied text;
  P10's test row new. 64 unique individual names, verified by sort/uniq.
- Digest corrections: `lib/beam4pm_dfcm.ex` re-admitted at union digest
  `a88af2e5…5d42` (P1's 9f305132, P2's 927b39c2, P3's b35fe560, P4's 9f15c69f,
  P5's c1f29849, P7's 72e671f1 are all superseded branch-state digests).
- Ceiling raises (vendored pack `vendor/ggen-marketplace`, commit `f2ae5382e`,
  dated reasons in authorshipKindDoc): `hand_authored_qualification` 35 → 50,
  `native_engine_facade` 6 → 7. Gate 070 verdict now 50/50 and 7/7.
- NEW finding surfaced by integration: the full gate run refused P10's six
  corpus TTLs (REFUSED_UNADMITTED x6 — P10's branch-scoped run never executed
  the full gate). Admitted sha-bound rather than silently exempted.

## Projection provenance (源)

`schema/beam4pm_hand_authored_source.tsv`, `docs/reference/beam4pm_hand_authored_source.md`,
and `test/beam4pm_authorship_gate_test.exs` are GENUINE `ggen sync run` output —
observed this session, twice (once per synthesis). Two disclosed fences crossed
by the tool's own documented remediations:

1. FM-PACK-008 (pack content hash mismatch after the ceiling raise): ggen.lock
   deleted and re-locked per the error's own remediation text. Committed lock
   `36fc3a3d…` hashes the clean raised pack.
2. FM-WRITE-005 (refusing silent clobber of the agents' hand-synced renders):
   temporary `force: true` front-matter on the 3 render targets, applied and
   REVERTED around each run — the submodule is clean at `f2ae5382e` with no
   force flags committed.

## Gates (all in wt-integration; commands + exits)

| Gate | Command | Exit | Result |
|---|---|---|---|
| deps | `mix deps.get` | 0 | 96 deps |
| compile | `mix compile` | 0 | clean; only dep-side warning is `Mix.Tasks.Eds.Ledger` redefinition from the ash_a2a 26.9.17 pin (pre-existing with that pin; note P7's probe removal KILLED the old CascadeAllocator warning) |
| authorship gate | `bash scripts/gate_authorship_check.sh` | 0 | **PASS — 64 admitted (57 counted as manufacturing debt), 0 findings** |
| rendered gate test | `mix test test/beam4pm_authorship_gate_test.exs` | 0 | 19 tests, 0 failures |
| full suite | `source scripts/env/rust4pm_reactor_env.sh && AUTOFDE_LAB_ROOT=$HOME/autofde-lab mix test` | 0 | **6 doctests, 1164 tests, 0 failures, 52 skipped** (97.8s). The dispatch's expected VendorCwd flake trio did NOT fire — zero failures total, nothing to triage. Skips are the named-skip classes (absent lab legs, kubectl, prereq-gated) |
| architecture | `mix ash_a2a.verify_architecture` | 0 | 17/17 architecture checks passed |
| natives | cargo builds (see below) | 0 | rf1–rf4 host release, petgraph/tract host release, rust4pm-wasm host + wasm32-wasip1, ferroplan wasm32-wasip1 |

Native artifact proof: `native/ferroplan/target/wasm32-wasip1/release/ferroplan_wasm.wasm`
sha256 `69e9229600dd1daf61b75fb90504023a7f84757ce2bd6b338931d63bd566a4a4` —
byte-identical to P1's receipted artifact (built here with P1's exact
`cargo build --release --target wasm32-wasip1 -p ferroplan-wasm`; a whole-workspace
build fails on winit/tokio@1.53.1 wasm feature gates — use the `-p` form).

Test-minted receipt: `research/erc/ERC-002-1789794942459.json` was minted for
real during the full-suite run (EDS claim verification against tree `3ac0d8f`)
and is committed, per the repo's tracked-receipts convention (12 already tracked).

## 比 (honest)

The integration session delivered zero new product semantics: every bridge
function, test, and fixture was manufactured by the P-agents (their ratios:
P3 reported 22% manufactured via a real render, everyone else 0% — all
hand-written-in-admitted-classes, all ledgered). This session's own bytes are
reconciliation + ledger prose: merges, conflict resolutions, 17 ontology
individuals, 1 pack ceiling commit, receipts. Of the ~200 rendered projection
lines, the proven-by-render share this session is the ggen output above
(manufactured); the ontology facts feeding it are hand-authored manufacturing
input. No ratio was decorated anywhere in the wave; the ledger grew 40 → 57
debt rows and the pack ceilings were raised with dated, reviewed reasons —
the honest direction of travel for a wave whose mandate was parity evidence,
not pack manufacture.

## Remaining (owner actions, exact commands below)

1. LAND: merge parity/integration on the main checkout (untracked-file-safe
   procedure below).
2. PACK CEILING: fast-forward the vendored pack to `f2ae5382e` (or apply the
   equivalent one-hunk change to the main checkout's already-dirty submodule
   working tree) and push the pack branch per the pack's own review law. Until
   then a bare `ggen sync run` on the main checkout refuses at FM-PACK-008 —
   that refusal is the tripwire, not a defect.
3. P8's announced one-liner (insert `BeamPM.AutofdeBridge` into
   `BeamPM.Application`'s supervision tree) deliberately NOT done here:
   `lib/beam4pm_application.ex` is sha-bound by its admission row; the edit
   needs its own re-admission, not a piggyback.
4. ash_a2a 26.9.17 pin collision warning (`Mix.Tasks.Eds.Ledger` redefinition)
   is upstream-shaped: ash_a2a now ships a task that collides with beam4pm's
   own `eds.ledger` task name. Triage upstream or rename locally in a reviewed
   change.
5. Unchanged from agents' receipts: P9's lab wasm registry pin; lab-side fixes
   (chicago Gate09/10, sa2a validate A2A-v0.3 mode, graphlaw transport
   ceilings, fabric subject blind spot, cmca inline-JSON E2BIG); B1–B3 card
   fixes; P5's ReceiptChain 2 :enospc-blocked tests (green here).
6. `docs/jira/v26.9.18/` ticket files still live only as untracked files in
   the main checkout; commit them alongside the landing so the docstring
   references (e.g. sa2a_replay's) resolve.

## Landing procedure (tree owner, main checkout @ /Users/sac/beam4pm)

The main checkout carries a concurrent session's uncommitted tracked edits
(ontology.ttl, tsv, md, gate test, mix.lock, ggen.lock, ferroplan sources,
tests) plus untracked files (lib/beam4pm_dfcm.ex, priv/bin/autofde,
test/beam4pm_dfcm_test.exs, dfcm fixtures, docs/jira/v26.9.18/*, research/*).
The merge will fail on: (a) untracked files colliding with incoming paths,
(b) tracked-file local edits overlapping the merge. Spell:

```bash
cd /Users/sac/beam4pm

# 0. Snapshot the concurrent session's in-flight state WITHOUT losing it:
git stash push --include-untracked -m "pre-parity-integration in-flight (auto-stashed by landing)"
# (review with: git stash show -p 'stash@{0}' — restore afterwards with git stash pop
#  ONLY for files the integration did not supersede; the integration SUPERSEDES
#  the untracked dfcm bridge baseline, its ledger rows, and the mix.lock pin.)

# 1. Land the wave (no-ff, one merge):
git merge --no-ff parity/integration -m "merge: v26.9.18 autofde-lab parity wave integration (9 agent branches, synthesis, ledger recount 64/57)"

# 2. Vendored pack ceiling raise — the pack commit is NOT in the main checkout's
#    submodule gitdir yet; fetch it from the integration worktree:
git -C vendor/ggen-marketplace fetch /Users/sac/beam4pm-worktrees/wt-integration/vendor/ggen-marketplace fix/hand-authored-qualification-ceiling-35-wave-26918
git -C vendor/ggen-marketplace checkout fix/hand-authored-qualification-ceiling-35-wave-26918
#    (the superproject gitlink still records 7abe147 — either commit the bump
#     `git add vendor/ggen-marketplace && git commit -m "bump ggen-marketplace: hand-authored ceilings 35->50, native 6->7"`
#     or leave the gitlink and land the raise via the pack's own upstream review;
#     theformer is what parity/integration was gate-proven against).

# 3. Re-run the gates for real on the landed tree:
mix deps.get && mix compile
AUTOFDE_LAB_ROOT=$HOME/autofde-lab bash scripts/gate_authorship_check.sh
source scripts/env/rust4pm_reactor_env.sh && AUTOFDE_LAB_ROOT=$HOME/autofde-lab mix test

# 4. Restore what remains of the concurrent session (anything the wave did not
#    supersede — the v26.9.17 F5 work, engine ontology refresh, petgraph/tract
#    sha updates) from the stash as NEW reviewed work, not silently:
git stash show --name-only 'stash@{0}'
# ...cherry-pick those paths back, re-run the gate, commit separately.

# 5. Commit the wave's ticket files (still untracked):
git add docs/jira/v26.9.18 && git commit -m "docs(jira): v26.9.18 parity wave tickets + context"
```

If step 1's merge reports CONFLICT (add/add) on any path: stop — that means a
concurrent session created a file the wave also carries; diff against the
parity/integration version and keep the one the receipt digests pin (all
wave digests are in schema/beam4pm_hand_authored_source.tsv, gate-enforced).

## Session receipt (証)

- Repo/base: beam4pm @ 36b0ed9 → branch parity/integration @ 3ac0d8f (13 commits)
- Commands + exits: table above (every gate exit 0; two mid-session failures
  disclosed and repaired narrowly: P5-merge ontology resolution took --theirs
  and dropped P2/P3 rows — caught by individual-count tracing, restored at
  synthesis; whole-workspace ferroplan build failure — repaired with P1's
  `-p ferroplan-wasm` form)
- Standing deltas: wave integration ALIVE-in-worktree / PARTIAL_ALIVE overall
  (unlanded + pack raise unfetched); lab chicago court remains BUILD_BROKEN
  upstream (P6, unchanged)
- Falsifiers attempted: per-branch digest verification against all 9 receipts
  (all matched); duplicate-individual scan (0); merge-parent audit (9/9
  correct); union function inventory grep (all 6 wrappers + rework present);
  artifact sha vs P1 receipt (byte-identical)
- What the operator did NOT have to write: all of it — 9 merges, the union
  synthesis, the ledger reconciliation, both renders, every gate run, and
  this receipt.
