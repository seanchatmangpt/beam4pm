# WAVE-RECEIPT — A1 capability sweep: beam4pm A2A surface under ash_a2a 26.9.17

Ticket: "Make sure all capabilities work" for beam4pm's A2A agent surface under
the freshly consumed ash_a2a 26.9.17 hex release (recorded under b4p-f5-01's
consumption gate, operator-ordered 2026-09-18).
Agent: A1 of 10-agent wave. Date: 2026-09-18.

## Standing

**ALIVE** — every gate below is observed execution in this session, this VM,
this worktree. No inspection-only claims.

## Base

- branch `chore/a2a-capability-sweep-v26917` @ base `22fa4aa` (same as main).
- Dependency consumed IN THIS WORKTREE: `mix deps.update ash_a2a` → hex
  `ash_a2a 26.9.17`, lock sha256-prefix `70e3e925`, hex package sha `04bcebe3…`
  — matches b4p-f5-01's consumption-gate lock exactly. (The worktree's committed
  lock was 26.9.10; main's 26.9.17 consumption was uncommitted mix.lock-only.)
- Prereqs materialized in-worktree (untracked/ignored, no diff): `cargo build
  --release --target wasm32-wasip1` for rust4pm-wasm (exit 0); `cargo build
  --release` for rf1/rf2/rf3/rf4 oracle binaries (all exit 0); ferroplan +
  vendor/ggen-marketplace submodules initialized at their pinned commits
  (`4b8ff2e`, `7abe147`) via local object store (`git -c submodule.<name>.url=
  /Users/sac/beam4pm/<path> submodule update --init <path>` — main checkout used
  read-only as clone source).

## Commands + exits

| command | exit |
|---|---|
| `mix deps.get && mix compile` (26.9.10 baseline) | 0 |
| `mix deps.update ash_a2a && mix deps.get && mix compile` (26.9.17) | 0 |
| `cargo build --release --target wasm32-wasip1` (native/rust4pm-wasm) | 0 |
| `cargo build --release` (rf1/rf2/rf3/rf4 oracles) | 0 ×4 |
| `mix run --no-start /tmp/a2a-sweep/server.exs` (harness VM) | up |
| `mix run --no-start /tmp/a2a-sweep/enumerate.exs` | 0 |
| `python3 /tmp/a2a-sweep/dispatch.py` (real JSON-RPC over HTTP) | 0, ALL_PASS |
| positive-leg python (S29 legs, create, replay) | 0, ALL_PASS |
| `ggen sync run` (manifest re-render after ontology re-admission) | 0 |
| `mix run qualification/a2a_smoke_test.exs` (admission acceptance command) | 0 |
| `mix test` (final, documented env harness) | **0 — 1087 tests, 0 failures, 86 skipped** |

## Gates

1. **card == capability index — PASS.** Wire `GET /a2a/.well-known/agent-card.json`
   (port 4311): 1194 skills; in-VM `AshA2A.Info.capability_index(BeamPM.Ash.Domain)`:
   1194 skills. `card_ids == index_ids` (sorted), ids unique, sorted by id,
   protocol `jsonrpc`/`0.3.0`. 597 read + 597 create; every skill maps to a real
   public action (0 unresolved via `Ash.Resource.Info.public_actions/1`).
   Exactly 2 display-name overrides survive: `read_ocel_events`
   (OcelEvent.read), `read_conformance_results` (ConformanceResult.read).
2. **classification — PASS.** By compiled consequence: 597 `:observe` (:read
   default), 597 `:change` (:create default), 0 `:external_do`, 0 `:unknown`.
3. **dispatch over real JSON-RPC message/send — PASS (with one defect found, below).**
   - 6 `:observe` skills across 6 different resources (OcelEvent,
     ConformanceResult, ActivationEvent, AccountDiscovery, AddOnBundle,
     AgentAssignment): HTTP 200, task `TASK_STATE_COMPLETED`, real artifact
     `%{"results": [...]}`; seeded rows return real attribute shapes
     (event_id/event_type/event_time/attributes; fitness/precision/trace_id).
   - 3 `:change` skills without a grant (OcelEvent.create,
     ActivationEvent.create, AccountDiscovery.create): documented typed refusal
     — HTTP 200, task `TASK_STATE_FAILED`, text `Error: %{code:
     :authority_required, detail: "authority_required"}` — CommandBus refuses
     before any Ash action runs; no crash, no receipt. Recorded.
   - S29 (authentication ≠ authority), observed on the wire:
     authenticated caller + no broker → `:authority_required`; nil-identity
     caller (no Auth plug) + granting broker → `:authority_required` (Grant
     `nil`-in-`nil`-out); bad bearer token → HTTP 401 at `A2A.Plug.Auth`;
     transport 401s an unauthenticated POST before JSON-RPC even runs.
   - positive `:change`: authenticated + harness-broker grant →
     `TASK_STATE_COMPLETED`, artifact = created record; row visible on read-back
     through the unauthenticated surface (same UUID). Receipt committed
     (see gate 4).
   - replay: same `message_id` + same content dispatched twice → completed
     twice, exactly ONE row created (receipt replay, no double execution).
   - error paths, all typed, HTTP 200 task-level or JSON-RPC level, never a
     500/crash: unknown skill → `TASK_STATE_FAILED` (`{:unknown_skill, _}` via
     skill_lookup stage); missing skill metadata → `:ambiguous_skill` typed
     failure; malformed JSON body → `-32700`; unknown method → `-32601`;
     missing message param → `-32602`; bogus read args → `TASK_STATE_INPUT_REQUIRED`.
4. **OCEL forwarder end-to-end — PASS.** `ocel_ingest_url` pointed at the
   capture relay on the ocel_ingest port, which forwards raw bytes to the real
   `BeamPM.OcelIngest.Router` (4312). 23 real POSTs captured byte-exact
   (`/tmp/a2a-sweep/ocel-capture.log`), **all 23 answered `HTTP/1.1 201 Created`
   `{"ok": true}`** by the real router. Captured bodies include
   `ash_a2a.dispatch.<domain>.<skill>` events (skill_name, reply_type,
   duration_native; `stage`/`error` attributes on the skill_lookup failure) and
   CommandBus receipt events, including one `ash_a2a.receipt.completed` carrying
   capability_id, command_id, execution_id, fingerprint, principal_id,
   `replayed: false`, `standing: "observed"` and the real
   `relationships: [{"qualifier": "acted_on", "object_id": "763938ca-…"}]`
   (the created record's actual PK — not fabricated).
5. **moduledoc fixed + ledger re-admitted — DONE.** `lib/beam4pm_a2a_agent.ex`
   now states the 26.9.17 all-public-actions default (1194 skills,
   observe/change split, S29 authority on `:change`) and that curated
   `a2a do skill` blocks are display-name overrides only. The edit tripped the
   repo's own GATE AUTHORSHIP (`REFUSED_SHA_DRIFT`, as designed) — resolved by
   the gate's own prescribed remedy: re-admission in `ontology.ttl`
   (`bap:hand_authored_lib_a2a_agent`: new `bpm:contentSha256`, truthed
   `bpm:admissionReason`), `ggen sync run` re-rendered both projections
   (`schema/beam4pm_hand_authored_source.tsv`, `docs/reference/
   beam4pm_hand_authored_source.md` — projections, never hand-edited), and the
   admission's `acceptanceCommand` (`mix run qualification/a2a_smoke_test.exs`)
   passes exit 0. No new hand-authored files.
6. **mix test — GREEN.** Progression, honestly: run 1 = 24 failures + 1
   invalid (fresh-worktree prereqs missing: wasm artifact, ferroplan submodule
   fixtures); run 2 = 10 failures (RF oracle binaries/env harness missing);
   run 3 after wasm + submodules + `cargo build --release` (rf1–rf4) + the
   canonical env harness from `scripts/env/rust4pm_reactor_env.sh` (RF2_/RF3_
   vars pointing at the checked-in `qualification/fixtures/` copies):
   **1087 tests, 0 failures, 86 skipped, exit 0** (skips are the documented
   `:chicago` exclusion + capture-dependent skips; log at
   /tmp/a2a-sweep/mix-test3.log). Sweep ports (4310–4313) never collide with
   the test VM's defaults (4210/4211).

## Defect found (upstream ash_a2a, NOT fixed here — upstream tickets own it)

`AshA2A.CommandBus.dispatch_with_ocel_correlation/5` re-dispatches by
`skill.name` (the bare atom, e.g. `:create`) instead of the caller's resolved
capability selector. `AshA2A.Dispatcher.fetch_skill/2` then resolves `:create`
to the FIRST `create`-named skill in the capability index (alphabetically
`BeamPM.Ash.Resources.AcceptanceCriteriaNonweakening.create`), so the BRCE
prepared-receipt anchor — bound to the caller's canonical id
(`…OcelEvent.create`) — mismatches the re-resolved skill and every
duplicate-action-name `:change` skill is refused fail-closed with
`:brce_prepared_receipt_required, reason: :capability_mismatch`. Observed on
the real wire: `OcelEvent.create` (and every other create) refused; only the
index-first `create` actuates (verified: ACNW.create → `TASK_STATE_COMPLETED`
+ real row). Impact: safe (no wrong-resource actuation — the fence catches
it) but the `:change` half of the 1194-skill surface is inoperable for any
domain with duplicate action names, which is the DEFAULT under the v26.9.12+
all-public-actions model. Falsifier, evidence, and mechanism recorded for the
ash_a2a defect/bench tickets (b4p-f5-01/02 scope).

## Files changed (this branch)

| path | change | attribution |
|---|---|---|
| `mix.lock` | 28+/8− (26.9.10 → 26.9.17 lock, mix-written) | mix-owned (`mix deps.update ash_a2a`) — manufactured |
| `lib/beam4pm_a2a_agent.ex` | 11+/5− moduledoc truthing | hand-written, operator-ORDERED by this ticket, file already on the hand-authored ledger |
| `ontology.ttl` | 2+/2− (re-admission: new sha + truthed reason on `bap:hand_authored_lib_a2a_agent`) | hand-written 法面 ledger edit, prescribed by GATE AUTHORSHIP's own refusal message |
| `schema/beam4pm_hand_authored_source.tsv` | 1+/1− | ggen-manufactured projection of ontology.ttl (`ggen sync run`) |
| `docs/reference/beam4pm_hand_authored_source.md` | 2+/2− | ggen-manufactured projection of ontology.ttl (`ggen sync run`) |
| `WAVE-RECEIPT.md` | new | session receipt (帳), not 産面 app code |
| `research/erc/ERC-002-1789768459328.json` (+ one from the final green run) | new | test-manufactured conformance receipts produced by `mix test` in this worktree |

Submodules `native/ferroplan` + `vendor/ggen-marketplace`: pinned gitlinks
unchanged; working trees materialized only. `native/*/target/`: ignored build
output.

## 比

total delivered = 51 changed lines across the 5 tracked files (44 before the
re-admission leg; +7 from ontology + its two projections) + 1 receipt + test-
manufactured ERC receipts.
- manufactured: 29 lines (mix.lock 28, mix-owned; + TSV 1 and .md 2 net lines,
  ggen-rendered projections) = **~57% of the tracked diff**
- hand-written: 22 lines (moduledoc 6 net, operator-ordered on an admitted
  file; ontology re-admission 0 net — 2+/2− sha/reason substitution, a 法面
  ledger maintenance edit prescribed by the gate itself)
Honest note: this ticket's deliverable is verification (証), not manufacture;
every app-code byte is either mix-owned or the ordered moduledoc correction.
No pack exists that could render an agent moduledoc truthing — recorded as the
missing capability rather than papered over.

## Falsifiers attempted

1. "Card advertises skills that don't exist" — cross-checked 1194 card skills
   against the compiled index AND `Ash.Resource.Info.public_actions/1` per
   resource: 0 unresolved. Held.
2. "Index and wire card drift" — sorted-id set equality: equal. Held.
3. ":change without authority crashes or silently actuates" — neither: typed
   `:authority_required`, no effect, no receipt. Held (fail-closed verified).
4. "Authentication implies authority" (S29 regression hunt) — refused all
   directions (authed+no-broker; nil-identity+granting-broker; unauthenticated
   POST 401s at the transport). Held.
5. "Replay double-executes" — same message_id twice → 1 row. Held.
6. "All 1194 capabilities actually work" — FALSIFIED for `:change` duplicates:
   CommandBus/BRCE name-resolution defect (section above); fail-closed, but
   inoperable. This is the sweep's real finding.
7. "OCEL forwarding is decorative" — byte-captured 23 POSTs, all 201 at the
   real router, relationships proven non-fabricated. Held.
8. "The authorship gate won't notice the moduledoc edit" — it did
   (`REFUSED_SHA_DRIFT`), proving the gate alive; resolved by re-admission,
   not by weakening the gate. Held.

## Operator did not have to write

The lock update (mix), the two projection re-renders (ggen), the entire
verification harness execution (scripts in /tmp are this agent's throwaway
probes, not repo artifacts), all 1194 skill projections (compiled from the
ontology-generated resources), the entire refusal/receipt/authority/OCEL
behavior under test (upstream ash_a2a), the test-suite natives (cargo), and
the ERC conformance receipts (mix test). Operator keystrokes this session:
0 on 産面.

## Remaining

- The CommandBus/BRCE duplicate-name defect belongs to ash_a2a upstream
  (b4p-f5-01/02 scope): the fix class is to dispatch by the resolved
  capability id, not `skill.name`.
- `BeamPM.A2ARouter`'s `a2a_base_url` is `Application.compile_env`-frozen at
  compile time (default `http://localhost:4211/a2a`); moving `:a2a_port` at
  runtime moves the listener but not the card's advertised url. Observed,
  not fixed (hand-authored ledger file, out of ticket scope).
- beam4pm main still needs its committed consumption of 26.9.17 (main's
  mix.lock change was uncommitted; this branch carries it independently).
- Harness ports used: 4310 (capture relay), 4311 (A2A), 4312 (real ingest),
  4313 (auth front door) — all released at sweep end.
