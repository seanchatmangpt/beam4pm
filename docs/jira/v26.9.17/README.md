# v26.9.17 — Fortune-5 readiness for beam4pm in ~/xaas

Ticket set cut 2026-09-17 from the observed states of `~/ash_a2a`,
`~/ferroplan`, `~/beam4pm`, and `~/xaas` (evidence base: `_CONTEXT.md`).
Scope: **everything that must land from ash_a2a and ferroplan** for beam4pm
to be ready for Fortune 5 customers in xaas, each ticket carrying a
beam4pm-side verification gate so "landed" means "consumed and verified
here".

Nothing in this set has executed yet — every ticket starts `BLOCKED`. The
`cleanup-merge-plan.md` in this directory (same-day family cleanup) is a
sibling artifact: its open items are referenced by b4p-f5-08, not
re-ticketed.

## Reading order

`_CONTEXT.md` → the crown (09) → its dependency lines:

```
ash_a2a line      01 defects+bench  ──┐
                   02 stress defects ──┼─→ 03 captures ──────────┐
                                                              ├─→ 09 CROWN
ferroplan line    04 wave-6+push ─→ 05 pin reconcile ─→ 06 verdict-flip audit ─┤
                                            └───────→ 07 EngineOp refresh ────┤
release line      08 Hex/release boundary ─────────────────────────────────────┘
```

## Tickets

| id | title | standing | blocks |
|---|---|---|---|
| `b4p-f5-01` | ash_a2a: land the two disclosed production defects + wire the 7 orphaned benchmark modules + push main | `BLOCKED` | every consumer of the A2A admission/actuation path |
| `b4p-f5-02` | ash_a2a: land multinode/stress outcomes (HddlSolver cross-VM temp collision is beam4pm-blocking) | `BLOCKED` | concurrent dispatch under Fortune-5 load |
| `b4p-f5-03` | ash_a2a → beam4pm: regenerate qualification/gym_bridge captures on the landed line | `BLOCKED` | beam4pm plan-execute-conform closure evidence (today honestly skips) |
| `b4p-f5-04` | ferroplan: finish+merge wave-6 (FOUND_BUG_2 hotfix `d00dcf8` first) and push the 185-commit line | `BLOCKED` | admissibility of ANY strong-cyclic verdict through beam4pm |
| `b4p-f5-05` | beam4pm: three-way ferroplan pin reconciliation (ppcx `4b8ff2e` vs hardened main vs origin) + submodule bump | `BLOCKED` | everything downstream of the engine |
| `b4p-f5-06` | beam4pm: post-bump verdict-flip audit + quarantine of pre-wave-6 strong-cyclic evidence | `BLOCKED` | evidence integrity |
| `b4p-f5-07` | beam4pm: bpm:EngineOp ontology refresh + ggen re-render of the three facades | `BLOCKED` | lawful engine-surface consumption |
| `b4p-f5-08` | beam4pm: real release boundary (Hex publish or digested artifact) for xaas | `BLOCKED` | any xaas consumption beyond OCEL HTTP |
| `b4p-f5-09` | **CROWN**: Fortune-5 trial closure — evidenced end-to-end run visible in xaas | `BLOCKED` | the milestone itself |

## Standing law

Append-only History per ticket; `ALIVE` only for observed execution against
the exact admitted subject in the working session; `inspection ≠ execution`;
no weakened tests, no acceptance mocks, no hand-patched capture bytes. A
trial report without attempted falsifiers is not a closure.
