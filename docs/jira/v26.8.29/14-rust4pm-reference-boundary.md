# Rust4PM Reference Boundary and Concept Extraction Worklist — v26.8.29

## Status

`UNKNOWN` — this is an admission worklist, not evidence that any concept below has been modeled,
generated or executed. Nothing here authorizes porting.

## Purpose

`03-architecture-and-ggen-manufacturing.md` states the reference-ingestion rule: Rust4PM's public
type/API surface (`https://rust4pm.aarkue.eu/docs/types`, v0.6.2) may be used as external semantic
evidence for what a modern process-mining type system needs to cover. It is **not** a source tree
to port. This document names the concrete concepts worth admitting into `O*` so that rule has a
real worklist instead of a general statement, and draws a hard line around what "reference" means
in practice.

```text
Rust4PM (docs/types, v0.6.2)  -->  observational/reference input  -->  admitted ontology concepts
                                                                          |
                                                                          v
                                                            ggen independently manufactures
                                                            the BEAM (Erlang/Gleam/Elixir/Ash)
                                                            realization
```

Never: `Rust4PM source code -> translation -> beam4pm source`. There is no beam4pm source for a
human or LLM to write in the first place (see `02-product-requirements.md`'s source-lock rule); a
"translation" step would itself be a prohibited manual authoring act, independent of what it was
translated from.

## What is and is not admitted by this document

- Admitted: concept **names**, their **role** in a process-mining type system, and a short
  original description of why each matters for `O*` (written here, not copied from the source).
- Not admitted: the source site's own prose descriptions, code, or API signatures reproduced
  verbatim. For exact semantics, field lists, and current signatures, read
  `https://rust4pm.aarkue.eu/docs/types` directly at the time modeling work happens — this
  document is a pointer and a worklist, not a mirror, and it will drift from the live site as that
  project evolves.
- Not admitted: any claim that a listed concept exists, is modeled, or is generated in beam4pm
  today. Promotion from "named here" to "in `O*`" to "projected by ggen" each requires its own gate
  in `11-release-gates-receipts.md` (`GATE M0`, `GATE M1`).

## Concept extraction worklist

Organized by the modeling role each concept plays, not by the source's own module layout — the
canonical graph in `03-architecture-and-ggen-manufacturing.md` is language- and library-neutral, so
grouping by semantic role keeps this list useful independent of any one library's structure.

### Event data / log identity

Concepts worth admitting: an object-centric event log as first-class type (OCEL-shaped: typed
events and objects, qualified event-to-object and object-to-object relationships, time-indexed
object attributes); a case-centric event log/trace projection distinct from the object-centric
form; activity/case/variant identity as used by classical process mining. The load-bearing
distinction to preserve (per `03`'s "reference ingestion" rule) is that **event types and object
types occupy separate namespaces** — the same name can validly denote both, and an admitted model
that collapses this loses information the source type system deliberately keeps.

### Process models

Concepts worth admitting: a Petri net as a bipartite place/transition/arc graph with initial and
final markings; a directly-follows graph (activities plus frequency-annotated follows-edges,
start/end activities) at both case-centric and object-centric granularity; a process tree as a
hierarchical control-flow structure; POWL as a partially-ordered alternative representation. The
distinction to preserve: **weighted arcs and markings are not decoration** — an admitted Petri net
type that drops arc weights or marking state cannot support the conformance/alignment concepts
below.

### Conformance and alignment

Concepts worth admitting: an alignment result type distinct from a raw fitness score (an alignment
is a sequence of moves — synchronous, model-only, log-only, silent — each with its own cost, not
just a number); fitness as a value computed *from* an alignment, not a primitive; declarative
object-centric constraints (OC-DECLARE-shaped) as an alternative conformance vocabulary to
procedural models. The distinction to preserve: **alignment moves and their costs are evidence**,
and an admitted model that only stores the final fitness score has thrown away the evidence a
downstream planner or explanation feature would need.

### Object-centric statistics and connections

Concepts worth admitting: a typed object/event relationship graph (a "type graph") as its own
addressable structure, separate from any one instance graph; path schemas as reusable, scored
(support/coverage/selectivity) connection patterns between types; conversion-rate and sojourn/
synchronization-time as first-class computed metrics rather than ad hoc query results. The
distinction to preserve: **type-level and instance-level graphs are different objects** — a schema
describes a pattern of connections, an instance is one concrete occurrence of it, and collapsing
the two loses the ability to score patterns before materializing every instance.

### Discovery algorithms (as capabilities, not code)

Concepts worth admitting as *capability categories* the admitted model should be able to express
results from: directly-follows-graph discovery, object-centric directly-follows discovery,
declarative constraint discovery, and heuristic/evolutionary net discovery (Alpha-family). These
are admitted as **result shapes and quality metrics**, never as ported algorithm implementations —
the algorithms themselves are exactly the kind of thing `03`'s doctrine expects ggen/BEAM-native
manufacturing to produce independently, potentially with a different accuracy/performance profile
than the reference.

### Persistence and interchange

Concepts worth admitting: a columnar/analytical export shape (DuckDB-style) for OCEL data,
independent of the in-memory representation used during inference; a "slim" or index-linked
in-memory representation optimized for repeated lookups, kept conceptually distinct from the
canonical/wire representation. The distinction to preserve: **storage/performance representations
are projections of the canonical model, not the canonical model itself** — this is the same rule
`03` applies to every generated language projection.

## Explicit non-goals for this document

- No line of Rust from the reference project is to be copied, transliterated, or "ported with
  syntax changes" into any beam4pm source. There is no beam4pm source for a human/LLM to place it
  in.
- No claim that beam4pm's eventual algorithms will match the reference project's performance,
  accuracy, or API shape. Independent manufacture may legitimately diverge.
- No dependency, license obligation, or attribution requirement is created by this worklist beyond
  citing the reference URL above for further reading. If any future work synthesizes ontology text
  that is close enough to the reference site's own wording to require attribution, add it at that
  time — this document does not pre-clear that.

## How this feeds the manufacturing pipeline

```text
this worklist (concept names + role) -> admitted ontology entries in ontology/ (O*)
                                       -> ggen projection (GATE M0, M1)
                                       -> Erlang/Gleam/Elixir/Ash types (03's projection matrix)
                                       -> cross-language identity proof (GATE M5)
```

A concept listed here has no standing until it clears `GATE M0` (admitted) and `GATE M1`
(manufactured) in `11-release-gates-receipts.md`. This document being thorough is not evidence that
any of it has been built.

## See also

- `03-architecture-and-ggen-manufacturing.md` — the reference-ingestion rule and projection matrix
  this worklist feeds.
- `08-process-intelligence-roadmap.md` — where discovery/conformance/planning capabilities are
  sequenced into an actual release roadmap.
- `11-release-gates-receipts.md` — the gates that convert "named here" into "admitted," "manufactured,"
  and eventually "proven against a customer workload."
