---
name: New bpm:RecordType proposal
about: Propose a new admitted bpm:RecordType for beam4pm's ontology.ttl
title: "[RecordType] "
labels: ["ontology", "record-type-proposal"]
assignees: ""
---

<!--
This proposes a new admitted bpm:RecordType individual for beam4pm's own
ontology.ttl (NOT the vendored pack's ontology.ttl, which holds only the
bpm: vocabulary itself, no record individuals). It does not itself change
generated/ -- once admitted, it enters through ontology.ttl and is projected
via `rm ggen.lock && ggen sync run`. See CONTRIBUTING.md / the PR template
for the sync + verification steps required to land it.
-->

## Record name

<!-- snake_case, e.g. purchase_order -- matches the existing convention
(ocel_event, dfg_edge, petri_place, ...). This becomes the Erlang record/type
name and the Elixir module name (CamelCased automatically), so it must be a
valid identifier fragment in both languages. -->

## One-line doc

<!-- A single sentence: what real-world process-mining/runtime concept does
this record represent, and why does it need to exist as its own type rather
than reusing an existing one (check generated/docs/beam4pm_types_reference.md
for the current full list before proposing)? -->

## Proposed fields

<!--
List every field in the exact order you want them (this becomes bpm:fieldOrder,
1-based). `type` MUST be one of the 8 closed enum values below -- no other
value is admitted (see gates/020_field_type_enum.rq in the vendored pack).
`required` must be the plain string "true" or "false".

Closed type enum: string | integer | float | boolean | datetime | atom |
list_string | map
-->

| order | name | type | required | doc |
| --- | --- | --- | --- | --- |
| 1 | `id` | `string` | true | Unique identifier for this record. |
| | | | | |

## Relationships to existing types

<!-- Does this record reference an existing record by id (as a plain string
field, the way bpm:ocel_relationship references object_id, or
bpm:dfg_edge references activity names by string)? beam4pm's ontology has no
typed cross-record reference mechanism yet -- references are string
identifiers by convention, not RDF object properties to another
bpm:RecordType individual. -->

## Admission checklist

- [ ] `record_name` does not duplicate an existing admitted `bpm:RecordType`
      (check `generated/docs/beam4pm_types_reference.md`)
- [ ] Every proposed field has a `fieldOrder`, `fieldName`, `fieldType` (one of
      the 8 closed enum values), `fieldRequired` (`"true"`/`"false"` as a plain
      string), and a one-line `fieldDoc`
- [ ] This record type has at least one real use case named above
- [ ] I understand this issue only proposes the ontology change; landing it
      requires a PR that edits `ontology.ttl` and re-runs `ggen sync run`
      (see the PR template's checklist)
