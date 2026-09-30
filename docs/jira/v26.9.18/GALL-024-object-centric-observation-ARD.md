# ARD v26.9.18 — GALL-024: Object-Centric Observation

**Status:** DRAFT ARCHITECTURE SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-008 semantic telemetry, runtime/event sources  
**Authority ceiling:** OBSERVE only

## Architecture objective
beam4pm converts admitted runtime observations into canonical object-centric event evidence that preserves objects, event-object qualifiers, command/capability correlation and source provenance.

## Components
- runtime/telemetry source adapters
- identity correlation layer
- OCEL 2.0 event/object mapper
- canonicalizer
- provenance/receipt emitter
- roundtrip/schema court

## Data/control flow
`Runtime/semantic observations -> correlate identities -> map events/objects/qualifiers -> canonical OCEL 2.0 -> evidence receipt`

## Invariants
1. Define canonical mapping from runtime/semantic telemetry sources to OCEL event/object types.
2. Preserve stable source object IDs or manufacture deterministic surrogate IDs from admitted keys.
3. Carry semantic subject, capability, command/receipt and runtime identities as attributes/relations where applicable.
4. Preserve event-object qualifiers and multi-object relations; do not flatten to one case ID.
5. Canonicalize serialization without rewriting observed timestamps/values.
6. Record source adapter/version and raw evidence digest.
7. No observation adapter may grant authority or mutate normative process law.

## Failure/refusal boundaries
- Required identity unavailable => PARTIAL/UNATTRIBUTED
- Ambiguous object mapping => REFUSED
- Observation would require normative mutation => architecture failure
- Source provenance unavailable => evidence ceiling reduced

## Qualification court
- authorship/manufacture guard
- focused source-to-OCEL tests
- multi-object qualifier fixture
- input-order permutation test
- OCEL roundtrip/schema validation
- rebar3 eunit / mix test as applicable

## Boundary law
[
PortableExecution \neq Authority,\quad Observed \neq Normative,\quad QueryResult \neq FactBeyondItsSubject
]

No host/runtime/observer may silently expand the subject or rewrite process law.
