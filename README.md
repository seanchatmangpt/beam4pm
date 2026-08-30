# beam4pm

beam4pm is a BEAM-first process-mining substrate whose application source is
manufactured entirely by [ggen](https://github.com/seanchatmangpt/ggen) from an
RDF ontology and a vendored ggen-marketplace pack — nothing under `generated/`
is hand-written. `beam4pm_pro` is the planned future commercial layer built on
top of this substrate; it does not exist as code yet. See
[`docs/jira/v26.8.29/`](docs/jira/v26.8.29/) for the full doctrine, vision, and
RevOps package that motivates that split.

## Source-authority doctrine

Direct edits to application source are refused by default, for humans and LLMs
alike. The only legitimate manufacturing inputs are `ontology.ttl`, `ggen.toml`,
`rebar.config`, `mix.exs`, `src/beam4pm.app.src`, and the templates inside the
vendored ggen-marketplace pack
(`vendor/ggen-marketplace/packs/beam4pm-process-model-pack`). Everything under
`generated/` is ggen output and must never be hand-edited — if it's wrong, fix
the ontology or the pack's templates and regenerate. See
[`docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`](docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md)
for the full policy, including the narrow, receipted privileged-exception path
for direct intervention.

## Current status

A first bounded slice, manufactured via the `beam4pm-process-model-pack`
(`vendor/ggen-marketplace/packs/beam4pm-process-model-pack`) from the 31
`bpm:RecordType` individuals admitted in `ontology.ttl`.

- 31 process-mining/runtime record types spanning event/log identity
  (`ocel_event`, `ocel_object`, `ocel_relationship`, `event_log`,
  `event_type`, `object_type`, `ocel_attribute`, `object_attribute_change`,
  `log_trace`), process models (`dfg_edge`, `petri_place`,
  `petri_transition`, `petri_arc`, `path_schema`, `path_schema_query`,
  `type_edge`, `heuristic_arc`), conformance/alignment
  (`alignment_move`, `conformance_result`, `oc_declare_constraint`,
  `process_variant`, `case_stats`, `sojourn_time`, `sync_time`), and adjacent
  runtime/planning/policy concepts (`resource_allocation`, `queue_snapshot`,
  `service_span`, `k8s_object_ref`, `planning_action`, `planning_state`,
  `policy_decision`) — see
  `generated/docs/beam4pm_types_reference.md` (itself ggen-generated) for the
  full, exact field-level reference.
- Erlang and Elixir projections only — no Gleam, no Ash yet.
- Each type is a data structure plus a validating constructor
  (`new_<type>/1` in Erlang, the equivalent in Elixir) that checks required
  fields are present and returns `{ok, Record}` or `{error, {missing_field,
  Field}}`. A reflection manifest (`beam4pm_types_manifest`/
  `BeamPM.Types.Manifest`) lists every admitted record and its field names. A
  generated JSON Schema (`generated/schema/beam4pm_types.schema.json`)
  documents the wire shape of every type. No process-mining algorithms (no
  DFG discovery, no conformance checking, no alignment search) exist yet —
  this slice is data structures only.
- Small, real demo scripts exist under `examples/erlang/` and
  `examples/elixir/` exercising the generated constructors — these are demos,
  not a playground; see `playground/README.md` for what a real playground
  would still require. No cross-language roundtrip proof yet.

## Build and test

```sh
git clone --recurse-submodules <this-repo-url>
cd beam4pm
rebar3 eunit   # 94 EUnit tests over the generated Erlang types + manifest
mix test       # 95 ExUnit tests over the generated Elixir types + manifest
```

`--recurse-submodules` is required: the ggen-marketplace pack that manufactures
this repo's types is a git submodule at `vendor/ggen-marketplace`.

## Regenerating

```sh
rm ggen.lock
ggen sync run
```

This re-runs the ggen pipeline against `ontology.ttl` and the vendored pack,
regenerating everything under `generated/` from scratch.

## Full doctrine and vision

See [`docs/jira/v26.8.29/README.md`](docs/jira/v26.8.29/README.md) for the
complete v26.8.29 package: architecture and manufacturing doctrine, product
requirements, pricing/packaging, GTM, security/airgap, release gates, and the
`beam4pm_pro` commercial vision.
