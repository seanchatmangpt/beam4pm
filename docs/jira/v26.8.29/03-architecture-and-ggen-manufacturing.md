# Architecture and ggen Manufacturing — v26.8.29

## Architectural thesis

beam4pm is not a handwritten application with generated helpers. It is a projection system whose executable artifacts are manufactured from admitted knowledge.

`A = μ(O*)`

Where:

- `O` = raw observations/specifications/reference material;
- `O*` = admitted, aligned, grounded and bounded knowledge;
- `μ` = ggen manufacturing transformations;
- `A` = generated executable/documentation/test/package artifacts;
- `R` = receipts binding identity, authority, execution and consequence.

## Canonical graph

The canonical model must remain language-neutral and execution-neutral. It represents, at minimum:

- semantic type identity;
- product/sum/collection type structure;
- fields, variants and cardinality;
- constraints and validation;
- wire representation;
- process/event/object identity;
- provenance and source authority;
- process activities/transitions/relations;
- capability and authority requirements;
- projection rules;
- acceptance/falsification rules.

A Rust, Erlang, Gleam, Elixir, Ash, JSON Schema, OCEL, PDDL or PPDDL representation is a projection of this graph, not the canonical graph itself.

## Reference ingestion

Rust4PM type documentation may seed semantic understanding because it exposes a substantial modern process-mining type surface. The ingestion rule is preservation first: record semantic distinctions before translating them.

Examples of distinctions that must not be flattened:

- event type vs object type namespaces;
- optional vs absent vs null where wire semantics differ;
- weighted arcs and markings in Petri representations;
- alignment moves, cost and search-state evidence;
- path-schema reach/support/selectivity/coverage;
- identity and relationship qualifiers in object-centric events.

Reference source does not gain execution authority merely because it informed the ontology.

## Projection matrix

### Erlang

Generate:

- modules;
- `-type`, `-opaque`, `-spec`;
- records/maps/native-record usage where admitted;
- validation;
- codecs;
- OTP application metadata where required;
- docs;
- Common Test/EUnit/property tests;
- examples.

### Gleam

Generate:

- idiomatic public custom types;
- functions returning typed Results rather than leaking raw FFI failure;
- Erlang-target externals/FFI modules;
- codecs;
- tests validating trusted external signatures against runtime behavior;
- examples.

### Elixir

Generate structs, protocols/typespecs, codecs and public API projections without becoming an obligatory bridge for Erlang/Gleam.

### Ash

Projection choice is semantic:

- scalar/constrained value -> `Ash.Type` / newtype;
- structured value -> typed struct/embedded value;
- lifecycle/identity/action domain entity -> `Ash.Resource`.

### Formal process models

Generate queryable/projectable representations for:

- OCEL/XES event logs;
- directly-follows graphs;
- Petri nets;
- POWL;
- PDDL deterministic planning;
- PPDDL stochastic planning;
- other admitted DDL/verification formalisms.

## Generated repository surfaces

Target repository shape:

```text
ontology/              authoritative semantic knowledge
specification/         authoritative product/process requirements
queries/               authoritative transformations
packs/                 reusable ggen manufacturing capability
ggen/                  project manufacturing config
generated/             projection output; never hand edited
examples/              generated executable specifications
playground/            generated end-to-end customer proof
tests/                 generated acceptance/property/conformance tests
receipts/              generated/observed evidence
```

The exact physical layout may evolve; the authority classification must not.

## Source authority policy

### Normal path

`change O* -> ggen run -> generated diff -> compile/test/execute -> receipt`

### Failure path

`generated failure -> locate missing/incorrect manufacturing rule -> repair upstream -> regenerate -> re-execute`

### Privileged exception

Direct source intervention is permitted only with a scoped capability object containing:

- subject/path;
- exact intended change;
- authorizing principal;
- reason manufacturing is currently disproportionate;
- acceptance command/behavior;
- pure-commit requirement;
- expiration.

The commit must contain only the admitted manual intervention. A Chicago execution must exercise the exact changed subject. Receipt and replay evidence are mandatory. Privilege terminates immediately after the intervention.

## Cross-language identity proof

Representative semantic objects must support cross-language identity tests, e.g.:

`canonical -> Erlang -> wire -> Gleam -> wire -> Elixir/Ash -> wire -> canonical`

Acceptance is semantic equality after canonicalization, with explicit rules for ordering, number representation, timestamps and tagged unions.

## Runtime integration semantics

beam4pm adapters expose native runtime/process semantics into the canonical event/process graph.

### BEAM

- OTP application/supervisor lifecycle;
- process start/stop/restart and ownership;
- `gen_statem` transitions;
- Telemetry events;
- Broadway message processing/acknowledgement/back-pressure;
- Oban durable job lifecycle;
- Reactor dependencies/retry/compensation/undo;
- Ash domain actions/resources.

### Cloud/runtime

- OpenTelemetry resources/spans/events/links;
- Weaver semantic-registry identities and validation;
- Kubernetes objects, owner references, watch events and runtime identity;
- eBPF/zero-code network/application observations;
- queues, databases, brokers and external APIs.

## Process inference boundary

Raw telemetry is evidence, not automatically admitted business semantics.

The system maintains separate dimensions:

- observed;
- inferred;
- admitted;
- executed;
- changed;
- verified;
- refused;
- blocked;
- unsupported.

An inferred causal path may be useful at `PARTIAL_ALIVE` while unresolved business meaning remains `UNKNOWN`.

## Planning and DO authority

Formal planners may produce candidate sequences or policies over the process twin. No planner, LLM, generated code, hook or semantic derivation receives ambient execution rights.

`SELECT != CONSTRUCT != DO`

BRCE is the exclusive DO path:

`candidate -> admission -> authority -> actuation -> consequence -> receipt -> replay`

## Manufacturing acceptance crowns

- `ERLANG_TYPES_ALIVE`
- `ERLANG_EXAMPLES_ALIVE`
- `GLEAM_TYPES_ALIVE`
- `GLEAM_FFI_ALIVE`
- `GLEAM_EXAMPLES_ALIVE`
- `ELIXIR_ASH_PROJECTIONS_ALIVE`
- `CROSS_LANGUAGE_ROUNDTRIP_ALIVE`
- `PLAYGROUND_ALIVE`
- `PROCESS_INFERENCE_ALIVE`
- `SOURCE_LOCKED_ALIVE`
- `BEAM4PM_GGEN_ONLY_ALIVE`

A crown requires observed execution against the exact generated subject, not generator existence or successful compilation alone.