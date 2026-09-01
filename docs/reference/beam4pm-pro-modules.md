# BeamPM.Pro Modules Reference

Exhaustive reference for the `BeamPM.Pro.*` commercial-layer modules and related actuation,
process-governance, and billing/entitlement reconciliation modules. All modules below are
hand-authored Elixir/Erlang (not ggen-generated) unless noted.

## BeamPM.Pro.CapabilityManifest

`lib/beam4pm_pro_capability_manifest.ex:1-16`

Introspects real repo state to produce a machine-readable capability status manifest and verify
claims against it.

| Function | Signature | Line |
|---|---|---|
| `capabilities/0` | `() :: [capability_fact()]` | :23 |
| `capability/1` | `(name :: atom()) :: capability_fact() \| nil` | :38 |
| `status/1` | `(name :: atom()) :: status() \| nil` | :44 |
| `evidence_for/1` | `(name :: atom()) :: [String.t()]` | :53 |
| `verify/1` | `(claimed :: %{atom() => atom()}) :: {:ok, :consistent} \| {:error, {:contradicts, [mismatch()]}}` | :68 |

```elixir
BeamPM.Pro.CapabilityManifest.verify(%{rust4pm_wasm_engine: :alive})
# => {:error, {:contradicts, [%{capability: :rust4pm_wasm_engine, claimed: :alive, actual: :unsupported}]}}
```

## BeamPM.Pro.Compatibility

`lib/beam4pm_pro_compatibility.ex:1-10`

Version-compatibility matrix that refuses incompatible component pairings using real
`Version.match?/2` semver checks.

| Function | Signature | Line |
|---|---|---|
| `matrix/0` | `() :: %{component() => String.t()}` | :25 |
| `check/1` | `(versions :: %{component() => String.t()}) :: {:ok, :compatible} \| {:error, {:incompatible, component(), String.t()}}` | :34 |

```elixir
BeamPM.Pro.Compatibility.check(%{beam4pm: "0.9.0", ggen_igniter: "26.8.0"})
# => {:ok, :compatible}
BeamPM.Pro.Compatibility.check(%{beam4pm: "1.5.0"})
# => {:error, {:incompatible, :beam4pm, "1.5.0 does not satisfy requirement \">= 0.1.0 and < 1.0.0\""}}
```

## BeamPM.Pro.License

`lib/beam4pm_pro_license.ex:1-15`

Struct plus HMAC-SHA256 sign/verify for commercial license evidence, deliberately separate from
entitlement/actuation authority.

| Function | Signature | Line |
|---|---|---|
| `canonical_payload/1` | `(license :: t()) :: binary()` | :42 |
| `sign/2` | `(license :: t(), secret_key :: binary()) :: t()` | :51 |
| `verify/2` | `(license :: t(), %{expected_scope: String.t(), trusted_key: binary() \| nil}) :: verify_outcome()` | :64 |

`verify_outcome()`: `{:ok, :valid} \| {:error, :expired} \| {:error, {:wrong_scope, ...}} \|
{:error, :tampered} \| {:error, :offline_unverifiable}`

```elixir
lic =
  %BeamPM.Pro.License{
    license_id: "L1",
    scope: "pro",
    issued_at: DateTime.utc_now(),
    expires_at: ~U[2027-01-01 00:00:00Z]
  }
  |> BeamPM.Pro.License.sign(key)

BeamPM.Pro.License.verify(lic, %{expected_scope: "pro", trusted_key: key})
# => {:ok, :valid}
```

## BeamPM.Pro.Doctor

`lib/beam4pm_pro_doctor.ex:1-17`

Runs an injectable check suite (version/migration/connector/entitlement/provenance) and produces
a redacted JSON-safe support bundle.

| Function | Signature | Line |
|---|---|---|
| `run/1` | `(opts :: keyword()) :: report()` | :31 |
| `bundle/1` | `(report :: report()) :: map()` | :51 |

`opts` may force any check's outcome for testing.

```elixir
BeamPM.Pro.Doctor.run(connector_failure: "timeout to gym bridge")
|> BeamPM.Pro.Doctor.bundle()
# => %{"status" => "degraded", ...one check with "outcome" => "error"...}
```

## BeamPM.Pro.Tenancy

`lib/beam4pm_pro_tenancy.ex:1-27`

Fail-closed tenant/role authorization model; checks tenant boundary before role capability,
deliberately not adopting Triplex given the ETS-based data layer.

| Function | Signature | Line |
|---|---|---|
| `role_capabilities/0` | `() :: %{atom() => [capability()]}` | :51 |
| `authorize/3` | `(principal :: principal(), resource_tenant_id :: tenant_id(), capability :: capability()) :: authorize_result()` | :59 |

```elixir
BeamPM.Pro.Tenancy.authorize(%{id: "u1", tenant_id: "t1", roles: [:viewer]}, "t1", :write)
# => {:error, {:insufficient_role, [:viewer], :write}}
```

## BeamPM.Pro.OcpmDiscovery

`lib/beam4pm_pro_ocpm_discovery.ex:1-27`

Object-centric process mining primitives over `ocel_event`/`ocel_object` maps —
object-type co-occurrence and per-object-type activity frequency. No OC-Petri-net synthesis.

| Function | Signature | Line |
|---|---|---|
| `object_type_interactions/2` | `(links :: [event_object_link()], objects :: [ocel_object()]) :: %{[String.t()] => non_neg_integer()}` | :44 |
| `object_type_activity_frequency/3` | `(links, events, objects) :: %{{String.t(), String.t()} => non_neg_integer()}` | :67 |
| `gaps/0` | `() :: [atom()]` | :87 |

`gaps/0` returns `[:object_centric_petri_net_synthesis, :divergence_free_log_transformation,
:multi_instance_dfg, :convergence_detection]`.

```elixir
BeamPM.Pro.OcpmDiscovery.object_type_interactions(
  [{"e1", "order-1"}, {"e1", "pkg-1"}],
  [%{object_id: "order-1", object_type: "order"}, %{object_id: "pkg-1", object_type: "package"}]
)
# => %{["order", "package"] => 1}
```

## BeamPM.Pro.Simulation

`lib/beam4pm_pro_simulation.ex:1-17`

What-if structural analysis (edge add/remove, reachability, cycle detection) over a discovered
DFG. No discrete-event/throughput simulation.

| Function | Signature | Line |
|---|---|---|
| `apply_change/2` | `(edges :: [dfg_edge()], {:remove, from, to} \| {:add, from, to, freq}) :: [dfg_edge()]` | :29 / :33 |
| `reachable_from/2` | `(edges, start_activity :: String.t()) :: MapSet.t(String.t())` | :47 |
| `has_cycle?/1` | `(edges) :: boolean()` | :70 |
| `gaps/0` | `() :: [atom()]` | :119 |

`reachable_from/2` is a real BFS; `has_cycle?/1` is a real DFS with a recursion stack.

```elixir
edges = [{"A", "B", 5}, {"B", "C", 3}]
BeamPM.Pro.Simulation.reachable_from(edges, "A")
# => #MapSet<["A", "B", "C"]>
BeamPM.Pro.Simulation.has_cycle?(edges ++ [{"C", "A", 1}])
# => true
```

## BeamPM.Actuation.GymBridge / Session / Actuation

`lib/beam4pm_actuation.ex:205-267`

BRCE actuation pipeline (validate → admit → execute → observe+receipt) over a real subprocess
gym bridge, with a graph-derived admission allowlist and a guaranteed-receipt entry point.

| Function | Signature | Line |
|---|---|---|
| `GymBridge.open/2` | `(bridge_py :: String.t(), gym :: String.t()) :: {:ok, t()} \| {:error, term()}` | :25 |
| `GymBridge.request/3` | `(bridge :: t(), payload :: map(), timeout \\ 10_000) :: {:ok, map()} \| {:error, term()}` | :52 |
| `GymBridge.close/2` | `(bridge :: t(), timeout \\ 2_000) :: :ok` | :62 |
| `Session.open/3` | `(bridge_py, gym, bridge_timeout \\ 10_000) :: {:ok, t()} \| {:error, term()}` | :158 |
| `Session.update_observation/2` | `(session, observation :: map()) :: t()` | :195 |
| `Session.close/2` | `(session, bridge_timeout \\ 2_000) :: :ok` | :200 |
| `Actuation.run/2` | `(action_input :: map(), opts :: keyword()) :: {:ok, map()} \| {:error, {:refused, term()} \| {:execution_failed, term()} \| term()}` | :548 |
| `Actuation.admission_verdict/1` | `(action :: PlanningAction.t()) :: {:admitted, gym_op :: String.t()} \| {:refused, reason :: String.t()}` | :574 |
| `Actuation.admitted_actuations/0` | `() :: %{String.t() => %{gym_op: String.t(), requires: [String.t()]}}` | :596 |

`Session.open/3` opens and resets a gym bridge once for reuse across multiple `Actuation.run/2`
calls. `Actuation.run/2` required opts: `:gym`, `:bridge`; optional: `:run_id`, `:receipts_dir`,
`:chain_id`, `:bridge_timeout`, `:session`.

```elixir
BeamPM.Actuation.run(
  %{action_name: "increment_counter", preconditions: ["counter_ready"], effects: []},
  gym: "toy_counter",
  bridge: "priv/bridges/toy_counter.py"
)
# => {:ok, %{receipt_path: "receipts/actuations/act-....json", performed: true, reward: ...}}
# writes a beam4pm-brce/v1 receipt
```

## BeamPM.ProcessGovernor

`lib/beam4pm_process_governor.ex:1-77`

Multi-step stateful process governance on top of `BeamPM.Actuation`, sequencing named
actuations with exact-state-hash fencing. Never reimplements admission/execution.

| Function | Signature | Line |
|---|---|---|
| `initial_snapshot/2` | `(process_id :: String.t(), opts \\ []) :: {:ok, map()} \| {:error, {:refused, String.t()}}` | :157 |
| `plan_transition/2` | `(snapshot :: map(), ordinal :: pos_integer()) :: {:ok, map()} \| {:error, {:refused, String.t()}}` | :181 |
| `apply_transition/3` | `(snapshot, candidate, actuation_opts :: keyword()) :: {:ok, map(), map()} \| {:error, {:refused, String.t()} \| {:execution_failed, term()}, map()}` | :233 |
| `run/2` | `(process_id :: String.t(), actuation_opts :: keyword()) :: {:ok, map()} \| {:error, term(), map()}` | :361 |
| `contracts/0` | `() :: map()` | :473 |
| `replay/2` | `(process_id :: String.t(), process_receipts :: [map()]) :: {:ok, %{final_state: ..., mined_trace: LogTrace.t(), dfg: [DfgEdge.t()]}} \| {:error, {:replay_broken, ordinal, reason}}` | :492 |

`apply_transition/3` delegates to `Actuation.run/2`. `run/2` runs the full graph-declared
contract; pass `continuous: true` for one shared bridge session. `contracts/0` includes
`"k8s_scaling_governed"` and `"toy_counter_governed"`.

```elixir
BeamPM.ProcessGovernor.run("toy_counter_governed", gym: "toy_counter",
  bridge: "priv/bridges/toy_counter.py")
# => {:ok, %{process_id: "toy_counter_governed", state: "observed", state_hash: ..., receipts: [...]}}
```

## BeamPM.ReceiptChain

`lib/beam4pm_receipt_chain.ex:1-92`

Additive, opt-in hash-chaining extension for `beam4pm-brce/v1` receipts (adapted from ex4pm's
`Replay.Chain`), file-based, hashing raw on-disk bytes.

| Function | Signature | Line |
|---|---|---|
| `link_fields/2` | `(receipts_dir :: String.t(), chain_id :: String.t()) :: link()` | :114 |
| `hash_file!/1` | `(path :: String.t()) :: String.t()` | :132 |
| `verify/2` | `(receipts_dir :: String.t(), chain_id :: String.t()) :: {:ok, %{chain_id: ..., length: non_neg_integer(), receipt_paths: [String.t()]}} \| {:error, {:chain_broken, seq, reason}}` | :172 |

`link_fields/2` returns `%{chain_id, chain_seq, prev_receipt_path, prev_receipt_hash}`.
`hash_file!/1` computes a sha256 hex digest of raw bytes.

```elixir
BeamPM.ReceiptChain.verify("receipts/actuations", "toy_counter_governed")
# => {:ok, %{chain_id: "toy_counter_governed", length: 2,
#            receipt_paths: ["receipts/actuations/toy_counter_governed-t1.json",
#                             "receipts/actuations/toy_counter_governed-t2.json"]}}
```

## beam4pm_billing (Erlang)

`src/beam4pm_billing.erl:1-49` — not under `lib/`; MP6 billing/usage dedup.

`usage_event`/`billing_reconciliation` record projection plus a hand-designed
`reconcile_billing/4` that dedups usage events by `event_id` and sums billable quantity over a
half-open `[period_start, period_end)` window, guarding against double-billing across period
boundaries.

| Function | Signature | Line |
|---|---|---|
| `new_usage_event/1` | `(Map :: map()) -> {ok, usage_event()} \| {error, {missing_field, atom()}}` | :152 |
| `new_billing_reconciliation/1` | `(Map :: map()) -> {ok, billing_reconciliation()} \| {error, {missing_field, atom()}}` | :97 |
| `reconcile_billing/4` | `(Events :: [usage_event()], EntitlementId :: binary(), MetricName :: binary(), {PeriodStart :: binary(), PeriodEnd :: binary()}) -> billing_reconciliation() \| {error, {invalid_period, binary(), binary()}}` | :257 |

```erlang
beam4pm_billing:reconcile_billing(
    Events, <<"ent-1">>, <<"api_calls">>,
    {<<"2026-08-01T00:00:00Z">>, <<"2026-09-01T00:00:00Z">>}
).
%% => #billing_reconciliation{entitlement_id = <<"ent-1">>, total_quantity = 42.0,
%%      applied_event_ids = [...sorted, deduped...],
%%      period_start = <<"2026-08-01T00:00:00Z">>, period_end = <<"2026-09-01T00:00:00Z">>}
```

An inverted period (`PeriodStart >= PeriodEnd`) returns
`{error, {invalid_period, PeriodStart, PeriodEnd}}` (:259-261).

## beam4pm_entitlement (Erlang)

`src/beam4pm_entitlement.erl:1-58` — not under `lib/`; MP3 entitlement reconciliation.

`entitlement_event`/`entitlement_state` record projection plus a hand-designed
watermark-based fold (`reconcile_entitlement/2`) that is idempotent and order-independent over
redelivered/out-of-order lifecycle events, admitting an event only if
`(effective_at, event_id)` strictly exceeds the state's current watermark.

| Function | Signature | Line |
|---|---|---|
| `new_entitlement_event/1` | `(Map :: map()) -> {ok, entitlement_event()} \| {error, {missing_field, atom()}}` | :118 |
| `new_entitlement_state/1` | `(Map :: map()) -> {ok, entitlement_state()} \| {error, {missing_field, atom()}}` | :163 |
| `initial_entitlement_state/1` | `(EntitlementId :: binary()) -> entitlement_state()` | :216 |
| `validate_event_shape/1` | `(Event :: entitlement_event()) -> ok \| {error, {malformed_event, atom()}}` | :277 |
| `transition/2` | `(EventType :: binary(), CurrentStatus :: binary()) -> binary() \| {error, {unknown_event_type, binary()}}` | :351 |
| `reconcile_entitlement/2` | `(State :: entitlement_state() \| undefined, Event :: entitlement_event()) -> entitlement_state() \| {error, {wrong_partition, ...}} \| {error, {unknown_event_type, ...}} \| {error, {malformed_event, ...}}` | :294 |

`initial_entitlement_state/1` starts at the bottom watermark `("","")`. `validate_event_shape/1`
guards non-binary/empty `event_id` and non-ISO8601 `effective_at`. `transition/2` is a total map
over the 13 admitted event types.

```erlang
{ok, Ev} = beam4pm_entitlement:new_entitlement_event(#{
    event_id => <<"e1">>, entitlement_id => <<"ent-1">>,
    event_type => <<"ENTITLEMENT_ACTIVE">>, effective_at => <<"2026-08-01T00:00:00Z">>
}),
beam4pm_entitlement:reconcile_entitlement(undefined, Ev).
%% => #entitlement_state{entitlement_id = <<"ent-1">>, status = <<"ENTITLEMENT_ACTIVE">>,
%%      last_applied_event_id = <<"e1">>, updated_at = <<"2026-08-01T00:00:00Z">>}
```

## See Also

- `docs/jira/v26.8.29/README.md` — full `beam4pm_pro` commercial vision and doctrine index
- `CLAUDE.md` — manufacturing pipeline, source-authority doctrine, generated-module inventory
- `docs/reference/beam4pm_types_reference.md` — generated field-level record type reference
- `lib/beam4pm_actuation.ex`, `lib/beam4pm_process_governor.ex`,
  `lib/beam4pm_receipt_chain.ex` — full source for the actuation/governance/receipt modules
