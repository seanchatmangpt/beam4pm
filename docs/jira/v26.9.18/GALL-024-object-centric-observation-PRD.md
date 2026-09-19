# PRD v26.9.18 — GALL-024: Object-Centric Observation

**Status:** DRAFT IMPLEMENTATION SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-008 semantic telemetry, runtime/event sources  
**Authority ceiling:** OBSERVE only

## Product outcome
beam4pm converts admitted runtime observations into canonical object-centric event evidence that preserves objects, event-object qualifiers, command/capability correlation and source provenance.

## Problem
Flat traces lose the multi-object relations that matter in enterprise processes. Runtime effects must be projected into OCEL 2.0 with stable object/event identities and exact semantic correlation.

## Functional requirements
1. Define canonical mapping from runtime/semantic telemetry sources to OCEL event/object types.
2. Preserve stable source object IDs or manufacture deterministic surrogate IDs from admitted keys.
3. Carry semantic subject, capability, command/receipt and runtime identities as attributes/relations where applicable.
4. Preserve event-object qualifiers and multi-object relations; do not flatten to one case ID.
5. Canonicalize serialization without rewriting observed timestamps/values.
6. Record source adapter/version and raw evidence digest.
7. No observation adapter may grant authority or mutate normative process law.

## Acceptance criteria
1. One fixture links a single event to multiple object types with correct qualifiers.
2. Correlation from GALL-003/008 identities survives projection.
3. Input transport ordering does not alter canonical object/event relation set.
4. Missing required identity yields typed unattributed/partial evidence.
5. Raw source digest and adapter identity are present.
6. OCEL output passes repository-native schema/roundtrip checks.

## Evidence product
Emit a content-addressed receipt binding exact source/query/process/module/runtime identities, positive witness, attempted falsifiers, outputs and evidence ceiling. Portability means semantic identity, not merely successful execution.

## Definition of done
beam4pm converts admitted runtime observations into canonical object-centric event evidence that preserves objects, event-object qualifiers, command/capability correlation and source provenance.
