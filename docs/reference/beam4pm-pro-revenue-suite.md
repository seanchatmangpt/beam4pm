# beam4pm-pro Revenue Suite

*Hand-authored reference for the `beam4pm-pro-revenue-suite` manufacturing run.
Updated 2026-08-30, against the v26.8.29 doc package. Overall standing: UNVERIFIED
until each family's sync script has run and produced real passing `mix test`
output — see the Honesty Ledger section for the full standing vocabulary.*

This document specifies the five revenue capabilities and one practice capability
the suite manufactures, the exact function contracts they expose, how the code is
manufactured (never hand-written into `lib/` or `test/`), and the honesty ledger
that bounds every claim the suite is allowed to make.

## Quick Reference

| Capability | Function | Family |
| --- | --- | --- |
| quantify-rework-cost | `BeamPM.Revenue.Economics.rework_cost/2` | economics |
| measure-cycle-to-cash | `BeamPM.Revenue.Economics.cycle_to_cash/2` | economics |
| detect-conformance-leakage | `BeamPM.Revenue.Economics.conformance_leakage/3` | economics |
| meter-governed-process-estate | `BeamPM.Revenue.Metering.emit_usage_events/4` | metering |
| admit-entitled-usage | `BeamPM.Revenue.Metering.admit_entitled_usage/2` | metering |
| model-claude-workflow | `BeamPM.ClaudeWorkflowReactor.run/1` | practice |

All three families consume the existing generated surface unmodified:
`BeamPM.Discovery`, `BeamPM.Precision`, `BeamPM.Billing`, `BeamPM.Entitlement`,
and the `BeamPM.Types.*` validating constructors. No generated file, `mix.exs`,
or `ontology.ttl` edit is part of v1.

## Shared parser: BeamPM.Revenue.Xes

```elixir
@spec parse_file(Path.t()) ::
        {:ok, %{events: [BeamPM.Types.OcelEvent.t()], trace_attrs: map()}}
        | {:error, term()}
```

An `:xmerl`-based XES reader (OTP built-in, zero new dependencies). Every emitted
event's `attributes` map carries the string key `"case"` holding the trace-level
`concept:name`, so `BeamPM.Discovery.traces_from_events(events, "case")` works
unmodified. `trace_attrs` maps each case id to its string-keyed trace attributes,
including the `"Amount"` / `"RequestedAmount"` floats the economics functions
weight by. This parser is the suite's riskiest hop (the fixtures had never been
parsed through the Elixir surface before) and is deliberately placed in the first
family so any failure surfaces before anything depends on it.

## Capability 1: quantify-rework-cost

```elixir
@spec rework_cost([BeamPM.Types.LogTrace.t()], %{String.t() => map()}) ::
        %{per_case: [map()], loop_case_ids: [String.t()], total_weighted_cost: float()}
        | {:error, {:missing_amount, String.t()}}
```

A rework loop is any activity containing `" REJECTED by "` followed later in the
same `activity_sequence` by a `"SUBMITTED"`-bearing activity. Each flagged case
yields `%{case_id, loop_count, weighted_cost}` where `weighted_cost` is the
case's `"Amount"` trace attribute (fallback `"RequestedAmount"`). A loop-bearing
case with neither attribute is the typed refusal `{:error, {:missing_amount,
case_id}}`, never a silent `0.0`. `total_weighted_cost` is summed in sorted
ascending order — the same canonical-summation float-determinism discipline as
`BeamPM.Billing.reconcile/4`.

Spec citations: roadmap 08:146 ("retry/rework/recovery loops"), 08:184
("minimize WIP/rework"); PRD 02:176 (REV-003 rework and failure/retry loops).

## Capability 2: measure-cycle-to-cash

```elixir
@spec cycle_to_cash([BeamPM.Types.LogTrace.t()], [BeamPM.Types.OcelEvent.t()]) ::
        %{case_stats: [BeamPM.Types.CaseStats.t()],
          sojourns: [BeamPM.Types.SojournTime.t()],
          cycle_to_cash: %{String.t() => number()},
          open_obligations: [String.t()]}
        | {:error, {:malformed_event_time, String.t()}}
```

The first real producer for the previously zero-producer Phase-7 records: emits
`BeamPM.Types.CaseStats` per case and `BeamPM.Types.SojournTime` per (case,
activity) dwell, every one constructed through the generated validating `new/1`,
never as a raw struct literal. Per-case cycle-to-cash is the seconds from the
first `"SUBMITTED"`-bearing event to `"Payment Handled"`; cases with no payment
event land in `open_obligations` with no fabricated duration. A non-ISO8601
`event_time` is the typed refusal `{:error, {:malformed_event_time, event_id}}` —
importing the entitlement pack's timestamp discipline that billing lacks.

Spec citations: roadmap 08:141-143 (cycle/wait time, WIP/throughput,
bottlenecks); PRD 02:176 (REV-003 baseline cycle time, waiting time, WIP,
throughput).

## Capability 3: detect-conformance-leakage

```elixir
@spec conformance_leakage([BeamPM.Types.DfgEdge.t()], [BeamPM.Types.LogTrace.t()],
                          %{String.t() => map()}) ::
        %{findings: [map()], flagged_case_ids: [String.t()], total_amount_at_risk: float(),
          unweighted_findings: non_neg_integer()}
        | {:error, :empty_model}
```

Model edges are mined from a clean population via the existing
`BeamPM.Discovery.dfg_from_traces/1`; each trace is scored with the existing
`BeamPM.Discovery.conformance/2` (edges first, bare `ConformanceResult` back)
and `BeamPM.Precision.etc_precision/3` (alpha `0.0` default). A trace with
`fitness < 1.0` is a leakage candidate; each finding row is `%{case_id, fitness,
precision, amount_at_risk}` (`Amount` fallback `RequestedAmount`; nil-amount
findings are kept, excluded from the total, and counted in
`unweighted_findings`). `model_edges == []` is the typed refusal
`{:error, :empty_model}`, never a spurious all-flagged result.

Vocabulary discipline (also in the moduledoc): this is DFG adjacent-pair fitness
plus ETC escaping-edge precision — not alignment-based conformance.

Spec citations: roadmap 08:145 (conformance deviations), 08:148 (anomaly
detection); PRD 02:102 (PI-003 confidence/provenance).

## Capability 4: meter-governed-process-estate

```elixir
@spec emit_usage_events([BeamPM.Types.LogTrace.t()], String.t(), String.t(),
                        {String.t(), String.t()}) ::
        [BeamPM.Billing.UsageEvent.t()]
```

Converts governed process scope — one `quantity: 1.0` event per case, metric
such as `"beam4pm.estate.governed_cases"` — into MP6 usage events via the
existing `BeamPM.Billing.UsageEvent.new/1`. The event id is deterministic:

```elixir
event_id =
  Base.encode16(
    :crypto.hash(:sha256, entitlement_id <> "|" <> metric_name <> "|" <>
                            case_id <> "|" <> period_start),
    case: :lower
  )
```

so at-least-once re-emission dedups to zero double-billing inside the existing
`BeamPM.Billing.reconcile/4` with no billing-code change (`metric_name` is an
open set by construction). `occurred_at` is the case's real last event
timestamp. This enforces pricing doc 05:161 structurally — only process-scoped
metrics exist; nothing meters raw spans or log bytes — and manufactures
denominators only: no rates exist anywhere, because 05:93 rules dollar levels
UNKNOWN.

Spec citations: pricing 05:161 (anti-pattern: never price raw telemetry),
05:93 (price levels UNKNOWN); PRD 02:170-172 (REV-002 value-scoped usage
dimensions); revops 04:20 (principle 6: metering never double bills).

## Capability 5: admit-entitled-usage

```elixir
@spec admit_entitled_usage([BeamPM.Billing.UsageEvent.t()],
                           %{String.t() => BeamPM.Entitlement.EntitlementState.t()}) ::
        %{billable: [BeamPM.Billing.UsageEvent.t()],
          refusals: [%{event: BeamPM.Billing.UsageEvent.t(), reason: atom()}]}
```

The bill-only-if-entitled join that `usage_event.entitlement_id`'s own fieldDoc
declares ("usage whose entitlement_id has no reconciled entitlement_state is a
typed refusal, never silently billed") and that no shipped code implemented —
the largest named open manufacturing edge between MP3 and MP6. A pure partition
of a usage stream against a map of entitlement states (produced by real
`BeamPM.Entitlement.reconcile_entitlement/2` folds, never hand-built except via
`new/1`). Refusal reasons: `:unknown_entitlement`, `:inactive_entitlement`
(status `CANCELLED` and `occurred_at >=` the state's `updated_at`),
`:negative_quantity`, `:malformed_occurred_at` (ISO8601 regex reused from the
entitlement discipline). Conservation invariant, in the crown's own control
vocabulary: `billable` plus the refusal events is exactly the input multiset —
no event lost, none duplicated. The billable set feeds `reconcile/4` directly.

Spec citations: roadmap 08:220-226 (Phase 13 usage/contract accounting
correctness); PRD 02:154 (ENT-004), 02:156-158 (ENT-005 diagnosable billing
failures); revops 04:20 (principle 6).

## Manufacturing method

The suite is manufactured, not hand-written, by the `ggen_igniter` recipe that
already produces the rf-family modules:

1. Developers author fully-static EEx template pairs under
   `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/`
   (`beam4pm_revenue_economics{,_test}`, `beam4pm_revenue_metering{,_test}`,
   `beam4pm_claude_workflow_reactor{,_test}`), copying the header and marker
   conventions of `beam4pm_rf1_dfg.ex.eex`.
2. One sync script per family (`scripts/revenue_economics_sync.sh`,
   `scripts/revenue_metering_sync.sh`, `scripts/claude_workflow_reactor_sync.sh`)
   copies `scripts/rf1_dfg_sync.sh`'s exact conventions, including the
   dummy-query pattern: `mix ggen_igniter.sync` requires at least one `--query`,
   so each invocation passes `igniter/queries/admitted_actions.rq`, which the
   fully-static templates never reference.
3. The sync run renders `lib/beam4pm_revenue_*.ex`,
   `lib/beam4pm_claude_workflow_reactor.ex`, and their `test/` twins. Rendered
   outputs carry a GENERATED marker and are never hand-edited; fixes go through
   the templates and a re-sync. Each family is committed only after a real
   passing `mix test` run of its generated test file.

Fixtures are committed inputs with recorded digests: the stratified BPI-2020
extracts under `qualification/fixtures/bpi2020/` (`international_50.xes` sha256
`e0733f79a524d72437020c6877f1321d8abaca220d21a40f7ca8ee217520c88e`,
`domestic_50.xes` `0f134ff3632281b2f93836fb7c45c3cea3dbdae8f93b6d2bb80e626406edfd2c`,
`rfp_50.xes` `48cad40b9f6dceaa34a16870a7c5f59a3c2b10eeabcf7971fa3d20f7c5c49dec`;
generator `scripts/extract_bpi2020_fixture.sh`, deterministic strata 20/15/10/5)
and the 19-agent workflow journal at
`qualification/fixtures/claude-workflows/journal.jsonl` (187,684 bytes, sha256
recorded in its commit message). Tests assert fixture digests before parsing.

Ontology changes are not part of v1: new output shapes are plain maps per the
rf-family receipt-map precedent. The v2 promotion (typed `rework_cost`,
`leakage_finding`, `value_receipt` record types) exists only as a content
proposal outside the repo; admission belongs to the main loop, never to a suite
agent.

## Honesty Ledger

Standing vocabulary per the no-overclaiming rules. These bounds are part of the
suite's contract and are restated in the relevant moduledocs and at every demo
print site:

- **BPI-2020 amounts are anonymization-rescaled floats, not EUR.** Every money
  figure derived from the fixtures is in rescaled units, usable for weighting
  and aggregation semantics only, and is labeled as such wherever printed.
- **Prices are UNKNOWN by doctrine (pricing doc 05:93); no rating layer
  exists.** Nothing anywhere multiplies a quantity by a rate. The suite
  manufactures billing denominators, never dollar amounts.
- **Conformance means DFG adjacent-pair fitness plus ETC escaping-edge
  precision, not alignments.** Alignment-based conformance is UNSUPPORTED in
  this suite and the vocabulary is disclosed rather than blurred.
- **Provider usage-report transport is unbuilt and BLOCKED** on a live
  marketplace seller account. Metering ends at reconciled local receipts; no
  AWS/Azure/GCP submission call exists.
- **Before/after analytics over a historical log prove computation and
  evidence lineage, not causal customer outcomes.** A delta between two
  windows of a static log is a computed artifact, never an outcome claim.
- **Everything above the committed fixtures is UNVERIFIED until its sync
  script has run and its `mix test` output exists.** The fixtures themselves
  are the only artifacts ALIVE at authoring time (byte-verified, digest-pinned).

## Practice model: BeamPM.ClaudeWorkflowReactor

The sixth capability turns the process-intelligence product on the process that
manufactures it. `BeamPM.ClaudeWorkflowReactor` (`use Reactor`, plain Reactor
per the `lib/beam4pm_rf1_dfg.ex` precedent, `async?: false`) models Claude
Code's own orchestration shape as a real DAG over the committed session journal:

```text
:parse_journal -> :derive_waves -> :label_phases -> :receipt
Measure (fan-out) -> Design (synthesis) -> Develop (fan-out)
  -> Actuate (sequential) -> Qualify
```

Waves are derived from `started`/`result` interleaving in the journal; phases
are labeled by a documented ordinal heuristic over wave structure (first
multi-agent wave = measure, following singleton = design, next multi-agent wave
= develop, subsequent singletons = actuate, final wave = qualify). Malformed
journal lines are the typed refusal `{:error, {:malformed_journal_line, n}}`.

Disclosure baked into the moduledoc: the journal carries only
`{type, key, agentId, result}` — no timestamps and no phase fields exist — so
"durations" are journal-line ordinal spans (first started line to last result
line), named `ordinal_span`, and are never presented as wall-clock time.

Why model it at all: beam4pm sells the claim that operational processes can be
discovered, measured, and governed from their own event evidence. Running that
claim against beam4pm's own manufacturing workflow — waves, receipts,
conservation of the 19 agent start/result pairs — is dogfooding the product on
the process that builds it, with the same typed-refusal and receipt discipline
the revenue capabilities apply to customer processes.

## See Also

- [Cloud marketplace RevOps](../jira/v26.8.29/04-cloud-marketplace-revops.md) —
  commercial object vocabulary, marketplace lanes, quote-to-cash (doc 04)
- [Pricing, packaging, unit economics](../jira/v26.8.29/05-pricing-packaging-unit-economics.md)
  — tier ladder, usage-dimension models, the 05:93 UNKNOWN-price doctrine
- [Process-intelligence roadmap](../jira/v26.8.29/08-process-intelligence-roadmap.md)
  — Phase 7 economics layer, Phase 13 marketplace closure
- [beam4pm process-model types](beam4pm_types_reference.md) — generated record
  reference for the `BeamPM.Types.*` constructors the suite consumes
