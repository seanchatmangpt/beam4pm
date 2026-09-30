# ARD v26.9.18 — GALL-026: Conformance Delta

**Status:** DRAFT ARCHITECTURE SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-025 normative/observed separation, GALL-017 OCPQ where used  
**Authority ceiling:** ANALYZE only

## Architecture objective
beam4pm emits a deterministic, typed, object-linked delta between an exact normative subject and an exact observed subject, suitable for diagnosis and downstream candidate intervention.

## Components
- normative/observed subject adapter
- conformance evaluator
- typed delta model
- rule/evidence linker
- canonical delta encoder
- delta receipt

## Data/control flow
`Exact normative subject + exact observed subject -> conformance -> typed deltas linked to rules/evidence -> canonical receipt`

## Invariants
1. Represent conformance result as a set of typed deltas rather than only an aggregate score.
2. Support at least missing-required-event, unexpected-event, ordering violation, cardinality violation, wrong object/qualifier and identity mismatch classes.
3. Link each delta to exact normative rule and observed event/object evidence.
4. Preserve multiple simultaneous deltas; do not collapse to first error.
5. Canonicalize delta set by semantic identity for deterministic digest.
6. Expose severity/priority only as analysis metadata, never authority.
7. Bind evaluator/query/model versions in receipt.

## Failure/refusal boundaries
- Normative/observed identity mismatch => REFUSED
- Required relation unavailable => PARTIAL/UNKNOWN
- Evaluator unsupported construct => UNSUPPORTED
- Score-only result => no GALL-026 standing

## Qualification court
- focused delta classification tests
- multi-violation fixture
- input-order permutation test
- missing-evidence falsifier
- repository-native beam4pm verify chain

## Boundary law
[
Finding \neq Admission \neq Authority,\quad Prediction \neq Fact,\quad SELECT \neq DO
]

Only GALL-030 may cross the process-intervention consequence boundary, and it must reuse the existing GALL-003 authority/receipt machinery.
