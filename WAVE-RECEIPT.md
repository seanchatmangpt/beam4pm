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
