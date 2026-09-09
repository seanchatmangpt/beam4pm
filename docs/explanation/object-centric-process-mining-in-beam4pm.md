# Object-Centric Process Mining in beam4pm

Classical process mining assumes each event belongs to exactly one case. A hospital log has one
`patient_id` per event; an order-fulfillment log has one `order_id`. That assumption collapses the
moment a single process genuinely involves multiple interacting entities — an order that spawns
several packages, a package that gets consolidated with items from a different order, a driver who
carries packages belonging to unrelated orders on the same route. Forcing one case notion onto that
reality produces two well-documented distortions: **convergence**, where one event gets duplicated
across every case it touches (an order-shipped event appears once per package, inflating frequency
counts), and **divergence**, where a single case's trace interleaves activities from unrelated
sub-processes because they all happen to share the anchor case ID. Both distortions corrupt the
statistics a discovery algorithm depends on — directly-follows frequencies, variant counts, fitness
scores — without ever raising an error, because the pipeline swallows the mismodeling silently.

Object-centric process mining (OCPM) responds by dropping the single-case-notion assumption:
events relate to a *set* of objects, each carrying its own type, and a process is analyzed as
interactions between object types rather than as one linear case per object. Object Centric Event
Logs (OCEL 2.0) is the standard event/object shape this style of analysis operates over.

## What beam4pm actually models

`ontology.ttl` carries a real OCEL 2.0 event/object shape as three of its core `bpm:RecordType`
individuals:

- **`ocel_event`** (ontology.ttl:24-58) — `event_id`, `event_type`, `event_time` (all required),
  plus an optional `attributes` map.
- **`ocel_object`** (ontology.ttl:64-90) — `object_id`, `object_type` (both required), plus an
  optional `attributes` map. That map is a **flat snapshot**, not a time-indexed attribute
  history — a real, disclosed limitation rather than a hidden one.
- **`ocel_relationship`** (ontology.ttl:96-114) — the qualified event-to-object (or object-to-object)
  link: `qualifier` and `object_id`, both required. This is the record type that actually carries
  the object-centric structure: it is what lets one event point at many objects of different types,
  each with a role (`qualifier`) rather than a single undifferentiated case-ID foreign key.

These three types are manufactured, per beam4pm's usual pipeline, into per-language projections
(Erlang `src/`, Elixir `lib/`, Gleam `gleam/src/beam4pm/`) with validating constructors and into
JSON codecs (`beam4pm_codec` / `BeamPM.Codec`) — the same manufacturing discipline described in
`CLAUDE.md`, not something bespoke to OCPM.

## What actually computes over that shape

The object-centric analysis itself lives in `lib/beam4pm_pro_ocpm_discovery.ex`
(`BeamPM.Pro.OcpmDiscovery`), whose module doc states its scope plainly: "object-type
co-occurrence and per-object-type activity frequency (no OC-Petri-net synthesis)"
(lib/beam4pm_pro_ocpm_discovery.ex:1-27).

Two real functions:

- **`object_type_interactions/2`** (lib/beam4pm_pro_ocpm_discovery.ex:44) — takes event-object
  links and objects, returns a map from a *set of object types* to how often events touch that
  exact combination. Given `[{"e1","order-1"},{"e1","pkg-1"}]` and objects typed `"order"` and
  `"package"`, it returns `%{["order", "package"] => 1}` — a direct answer to "which object types
  actually co-occur on the same event, and how often." That is the object-centric analogue of a
  directly-follows edge: instead of asking "which activity follows which," it asks "which object
  types interact on the same event."

- **`object_type_activity_frequency/3`** (lib/beam4pm_pro_ocpm_discovery.ex:67) — returns a map
  keyed by `{object_type, activity}` pairs to a frequency count, i.e. how often each object type
  participates in each activity. This is the per-object-type analogue of activity frequency in a
  classical log, and it is the piece that starts to make convergence/divergence visible rather than
  silent: if `"package"` participates in an activity at a rate wildly different from `"order"`, that
  divergence is now a queryable number instead of an artifact buried in a distorted single-case
  trace.

Neither function performs OC-Petri-net synthesis, multi-instance DFG construction, divergence-free
log transformation, or convergence detection as a first-class output — the module says so directly
via its own `gaps/0` function (lib/beam4pm_pro_ocpm_discovery.ex:87):

```elixir
BeamPM.Pro.OcpmDiscovery.gaps()
# => [:object_centric_petri_net_synthesis,
#     :divergence_free_log_transformation,
#     :multi_instance_dfg,
#     :convergence_detection]
```

That is a deliberately narrow slice: co-occurrence counting and per-type activity frequency are the
two statistics that let a user *detect* that convergence/divergence is a live risk in their data
(by seeing multiple object types heavily co-occurring, or by seeing activity frequencies that
diverge sharply across types) — without claiming to have solved the harder downstream problem of
synthesizing an object-centric process model from that signal.

## How this sits next to beam4pm's classical (single-case) side

beam4pm's non-OCPM discovery path — `beam4pm_discovery` / `BeamPM.Discovery` /
`beam4pm/discovery` — builds `traces_from_events/2` and `dfg_from_traces/1` over the single-case
`dfg_edge` record type (ontology.ttl:120-146: `source_activity`, `target_activity`, `frequency`).
That pipeline is what a single-case-notion log needs and is where beam4pm's real conformance work
lives, including ETC (escaping-edges) precision via `beam4pm_precision:etc_precision/2,3` (Erlang/
Elixir) and `beam4pm/precision.etc_precision` (Gleam). `OcpmDiscovery` does not replace or wrap that
pipeline; it is a separate, additive analysis over the OCEL 2.0 shape (`ocel_event` / `ocel_object`
/ `ocel_relationship`) for the cases where forcing a single case notion would itself be the source
of error. Choosing between them is a modeling decision about the input log, not a maturity ranking
between two competing implementations of the same idea.

## Why the gaps matter, not just that they exist

The four gaps `OcpmDiscovery.gaps/0` names are not arbitrary omissions — they are the specific
capabilities that separate "count object-type co-occurrence" from "discover an object-centric
process model a user can reason about operationally":

- **Object-centric Petri net synthesis** is the step that would turn co-occurrence/frequency
  statistics into an executable model with places, transitions, and object-type-aware markings —
  the OCPM analogue of what `petri_place` / `petri_transition` / `petri_arc`
  (ontology.ttl:152-226) already represent for the single-case side, but there is no OC-aware
  synthesis algorithm producing those structures from OCEL input today.
- **Divergence-free log transformation** and **convergence detection** are the two techniques the
  broader OCPM literature uses to actually *repair* the distortions this page opened with, rather
  than merely surface a proxy signal for them (co-occurrence and skewed activity frequency are
  useful smoke detectors, not a fire suppression system).
- **Multi-instance DFG** would generalize `dfg_edge`'s single-case directly-follows edge into an
  object-type-aware directly-follows relation — the OCPM equivalent of beam4pm's existing
  `beam4pm_discovery` output, but for logs where a single case notion was never the right model.

Naming these as open rather than solved keeps `OcpmDiscovery` honest about what a caller can rely
on: object-type co-occurrence and per-type activity frequency are real, computed values today;
anything downstream of "build me an object-centric process model" is not yet implemented.

## See Also

- `CLAUDE.md` — manufacturing pipeline (ggen + ontology.ttl), record-type domains, and the
  classical `beam4pm_discovery` / precision pipeline this page contrasts against
- `ontology.ttl:24-114` — the three OCEL 2.0 record types (`ocel_event`, `ocel_object`,
  `ocel_relationship`) this page is grounded in
- `lib/beam4pm_pro_ocpm_discovery.ex` — the real `BeamPM.Pro.OcpmDiscovery` implementation and its
  own disclosed `gaps/0`
- `docs/reference/beam4pm_types_reference.md` — generated field-level reference for all 31 core
  `bpm:RecordType` individuals, including the OCEL identity domain
