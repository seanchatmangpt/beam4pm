# WAVE-RECEIPT — b4p-p1-fabric-solve-parity (wt-p1, branch parity/fabric-solve)

Observed 2026-09-18, agent P1, v26.9.18 autofde-lab parity wave.
Law: ~/.zcode/AGENTS.md (DfCM). ALIVE claims below are observed executions in
this session only.

## Standing

**ALIVE** for: `BeamPM.Dfcm.fabric_match/2` + `fabric_solve/2` wrappers run for
real through `priv/bin/autofde` (lab @ ~/autofde-lab); cross-validation against
`BeamPM.Ferroplan` wasm (submodule pin **e90928d**, artifact sha256
`69e92296…a4a4`) over the SAME beam4pm-owned fixtures; parity tests green;
authorship gate + gate test green.

## Base + head

- Base: `36b0ed9` (main checkout HEAD; branch parity/fabric-solve cut from it)
- Head: (this commit) — see `git log -1` on parity/fabric-solve
- ferroplan submodule: `e90928d7b0687a959831553c4eacca3d75ca6c88`, wasm built
  `--target wasm32-wasip1` in-worktree.

## Inherited-untracked baseline (disclosed)

`lib/beam4pm_dfcm.ex`, `priv/bin/autofde`, `test/beam4pm_dfcm_test.exs`, and
`qualification/fixtures/dfcm/{dfcm.hddl,dfcm-fond.pddl,abcx-problem.pddl}`
existed ONLY as untracked files in the main checkout (v26.9.17 wave, ledger
rows for them also uncommitted there). Copied byte-identical into wt-p1 as the
ticket's prerequisite baseline, committed here so the branch is self-contained
and the admitted ledger rows resolve. `dfcm-abcx.hddl` (HDDL problem fixture
for `beam4pm-dfcm-hddl`, 9 lines) is NEW, authored this session — no HDDL
problem for the dfcm domain existed anywhere in the family.

## Commands + exits (this session)

| Command (cwd wt-p1 unless noted) | Exit | Evidence |
| --- | --- | --- |
| `./priv/bin/autofde fabric match --help` / `fabric solve --help` | 0 | contracts discovered (match: domain + `--domain-arguments` JSON; solve: `--solver/--domain-arguments/--solver-arguments/--max-steps/--{subject,policy,environment,randomness}-digest/--cache`) |
| `./priv/bin/autofde fabric match HTNDomain --domain-arguments '{"domain_path": "qualification/fixtures/dfcm/dfcm.hddl", "problem_path": "qualification/fixtures/dfcm/dfcm-abcx.hddl"}'` | 0 | MISS envelope, 46 compatible solvers, `identity_sha256` bf7064ca…5935 |
| `./priv/bin/autofde fabric solve HTNDomain --solver Astar …` (same fixture) | 0 | `standing SOLVED`, terminal, 8 steps (p1 preserve → p8 select-lawful-option), `input_sha256` 77ac0269…, `receipt_sha256` ab8521ed…, `trajectory_sha256` 6a74bca2…, schema `autofde_lab.decision-fabric/3` |
| `./priv/bin/autofde fabric solve PDDLDomain --solver Astar …` (dfcm-fond.pddl + abcx-problem.pddl) | 3 | `standing REFUSED`, `SKD-FABRIC-008` ("'ImplicitSpace' object has no attribute 'sample'"); match-stage shows parser "recovery" warnings for `:non-deterministic` (false-positive solver match at match stage; honest refusal at solve stage) |
| `./priv/bin/autofde fabric match HDDLDomain --domain-arguments '{}'` | 3 | REFUSED `SKD-FABRIC-006` — lab `HDDLDomain.__init__` needs a live `HierarchicalProblem`, not JSON-constructible from paths (CLI-unreachable domain) |
| `cargo build --release --target wasm32-wasip1 -p ferroplan-wasm` (native/ferroplan @ e90928d) | 0 | artifact `ferroplan_wasm.wasm` sha256 69e9229600dd1daf61b75fb90504023a7f84757ce2bd6b338931d63bd566a4a4 |
| `mix run qualify_fabric_parity.exs` (session driver, removed before commit) | 0 | 6 JSON legs: ferroplan hddl_solve / fond_policy-raw-PDDL / plan-raw-PDDL / wrapper HDDL solve / wrapper FOND refusal / wrapper match refusal |
| `mix test test/beam4pm_dfcm_test.exs test/beam4pm_dfcm_fabric_parity_test.exs` (`AUTOFDE_LAB_ROOT=$HOME/autofde-lab`) | 0 | **3 doctests, 22 tests, 0 failures** |
| `bash scripts/gate_authorship_check.sh` | 0 | PASS — 50 admitted (43 counted as debt), 0 findings |
| `mix test test/beam4pm_authorship_gate_test.exs` | 0 | 19 tests, 0 failures |
| `mix deps.get`; port config `config :beam4pm, ocel_ingest_port: 4301, a2a_port: 4302` (worktree-local, UNCOMMITTED) | 0 | Bandit bound 0.0.0.0:4301 + 0.0.0.0:4302 observed in logs |

Note: two intermediate runs failed honestly and were repaired, not papered
over: (1) pipe-argument-order bug in `fabric_solve/2`'s option builder
(Keyword.get function-clause) — fixed; (2) lab CLI prints python-logging lines
on stdout before the envelope, so a SOLVED run arrived as
`{:error, {:invalid_json, …}}` through `run_autofde_cli/1` — fixed in the new
`fabric_cli/1` by extracting the first-`{`..last-`}` JSON span (shared existing
wrappers untouched). Also one disk-full (`no space left on device`) during the
first test-env build — host-wide constraint; reclaimed this worktree's own
cargo intermediates (wasm artifact kept) and re-ran clean.

## Cross-validation table (SAME fixtures, both engines)

| Fixture | fabric verdict (lab CLI, schema `autofde_lab.decision-fabric/3`) | ferroplan verdict (wasm @ e90928d) | Divergence attribution |
| --- | --- | --- | --- |
| `dfcm.hddl` + `dfcm-abcx.hddl` (HDDL, DfCM phase ladder) | **SOLVED** — 8 rollout steps `preserve-known-options → apply-known-fences → perform-dfcm-calculus → exclude-invalid-options → materialize-falsifiers → extend-if-required → construct-contingent-policy → select-lawful-option`; receipt_sha256 `ab8521ed…0610b9`, trajectory_sha256 `6a74bca2…ad2685` (stable across separate runs) | `hddl_solve/4`: `{:ok, policy}`, `solved=true`, `planning_type="fond"`, `notes=["strong FOND fixed point"]`, **9** policy entries (`htn:decompose:r.root:dfcm-cycle-preserve-before-collapse(g)` + one `htn:exec:r.root.p1..p8:<same phase>(g)` each) | Same decomposition ladder, two receipt vocabularies: fabric counts 8 primitive rollout steps; ferroplan adds the root HTN decomposition entry (8+1=9). Fabric envelope carries ERRC digests; ferroplan carries UniversalPlan policy/outcomes with probability_ppm. No semantic divergence. |
| `dfcm-fond.pddl` + `abcx-problem.pddl` (FOND PDDL, AB CX) | **REFUSED** `SKD-FABRIC-008` exit 3 (`PDDLDomain` is deterministic; skdecide parser only "recovers" from `:non-deterministic` and drops `oneof`, so no FOND semantics exist on any registered lab domain) | `fond_policy/4` on raw text: `{:error, {:engine, FP_ADAPTER "invalid PlanningProblem JSON"}}` (its ingest contract is a JSON `PlanningProblem` document, never PDDL text); `plan/4` on raw text: `{:error, {:engine, FP_ADAPTER "domain parse error: line 2: requirement :NON-DETERMINISTIC not supported by this FF version"}}` | **No engine today ingests this fixture as PDDL text.** Lab has no FOND-capable registered domain; ferroplan's FOND surface is JSON-PlanningProblem-only. Ferroplan's FOND solver itself is ALIVE on this very problem family — it drives `hddl_solve` (`planning_type="fond"`, strong FOND fixed point). Registry pin drift (lab `282fae4` vs `e90928d`) did NOT bind any of these legs: `fabric match/solve` are pure-Python scikit-decide paths that invoke no lab wasm op; the pin is P9's ticket. |

## Files changed (this branch)

- `lib/beam4pm_dfcm.ex` — inherited bridge + NEW: `fabric_match/2`,
  `fabric_solve/2`, `fabric_solve_opt/opts` types, private `fabric_cli/1` +
  `decode_fabric_stdout/1` (typed refusal surfacing incl. exit-3 envelopes and
  stdout log-noise extraction), `@spec`s + doctests. New content sha256
  `9f305132…ba1c` (ledger re-admitted).
- `test/beam4pm_dfcm_fabric_parity_test.exs` — NEW, 212 lines: match/solve
  real-CLI legs, typed-refusal legs, cross-validation legs (both engines),
  named skips for missing lab/wasm, divergence attribution in moduledoc.
  sha256 `c8a2fe98…be9d`.
- `qualification/fixtures/dfcm/dfcm-abcx.hddl` — NEW HDDL problem fixture
  (9 lines) for the inherited `dfcm.hddl` domain.
- `schema/beam4pm_hand_authored_source.tsv`, `docs/reference/beam4pm_hand_authored_source.md`,
  `test/beam4pm_authorship_gate_test.exs` — ledger: +1 admission (parity test),
  re-admit `lib/beam4pm_dfcm.ex` with new digest, counts 49/42 → 50/43,
  ceiling 36 → 37 with justification; petgraph/tract rows kept at THIS tree's
  committed digests (the main checkout's uncommitted edits to those files are
  foreign in-flight work and were NOT imported).
- `priv/bin/autofde`, `qualification/fixtures/dfcm/{dfcm.hddl,dfcm-fond.pddl,abcx-problem.pddl}`,
  `test/beam4pm_dfcm_test.exs` — inherited untracked baseline, committed
  byte-identical (shas verified against the main checkout's pinned digests
  before my edits).

## 比 (honest)

Manufactured-by-generator lines this session: **0**. Hand-written+ledgered
delivered lines: ~166 (lib wrappers) + 212 (parity test) + 9 (fixture) + ~20
(ledger/gate) ≈ **407/407 hand-written (0% manufactured)**. All of it is
admitted debt with named sunset plans (render from DfCM/fabric ontology facts;
the bridge file already owns this class). No ledger entry was skipped; the
authorship gate mechanically enforces the count.

## Falsifiers attempted (all survived → tripwired)

1. Can the fabric produce a FALSE `SOLVED` on the FOND fixture (parser
   recovery)? — No: match stage matches solvers on the recovered domain, but
   solve stage honestly refuses (`SKD-FABRIC-008`). Tripwired in the parity
   test (typed refusal asserted).
2. Does `fond_policy/4` accept PDDL text? — No (`FP_ADAPTER` JSON ingest
   refusal). Tripwired.
3. Does `plan/4` handle `:non-deterministic`? — No (FF version refusal).
   Tripwired.
4. Does the bridge survive lab stdout log-noise on a SOLVED run? — Initially
   failed (`{:invalid_json, …}`); fixed by envelope extraction; doctests +
   tests re-run green.
5. Does the gate tolerate importing the main checkout's uncommitted ledger
   state wholesale? — No: `REFUSED_SHA_DRIFT` on petgraph/tract (their bytes
   are not in this tree); foreign sha rows reverted, gate PASS.

## Remaining (not mine)

- P9: lab wasm registry pin `282fae4…` → `e90928d` (`src/autofde_lab/wasm/_registry.py:172`,
  receipts bind via `_model.py:202` source_revision equality).
- Lab: (a) fabric match-stage false-positive on parse-"recovered" domains;
  (b) stdout log-line hygiene (python logging before the JSON envelope);
  (c) `HDDLDomain` not constructible from file paths over the CLI (needs a
  live `HierarchicalProblem`).
- ferroplan: a PDDL-text FOND ingest path (or a PDDL→`PlanningProblem` JSON
  converter op) would close the FOND cross-validation gap observed here.
- Pack-side sync: the three ledger edits made here are rendered-projection
  edits (TSV/MD/gate-test); the owning `bpm:HandAuthoredSource` graph in the
  pack still needs the matching facts at the next ontology render
  (sync-drift hazard, same class as the AGENTS.md 並 note).
- `config/config.exs` port override (4301/4302) is deliberately uncommitted —
  worktree-local only, per wave instructions.
