# PRD v26.9.18 — GALL-026: Conformance Delta

**Status:** FINAL_SPEC — closed for v26.9.24  
**Implementation standing:** OPEN in PR #80 (gall/implement-024-028-process-intelligence @ eca116ea; not on main)  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-025 normative/observed separation, GALL-017 OCPQ where used  
**Authority ceiling:** ANALYZE only

## Product outcome
beam4pm emits a deterministic, typed, object-linked delta between an exact normative subject and an exact observed subject, suitable for diagnosis and downstream candidate intervention.

## Problem
A single conformance score hides which exact process laws differ, which objects/events caused the difference, and whether a deviation is missing, extra, reordered or identity-mismatched.

## Functional requirements
1. Represent conformance result as a set of typed deltas rather than only an aggregate score.
2. Support at least missing-required-event, unexpected-event, ordering violation, cardinality violation, wrong object/qualifier and identity mismatch classes.
3. Link each delta to exact normative rule and observed event/object evidence.
4. Preserve multiple simultaneous deltas; do not collapse to first error.
5. Canonicalize delta set by semantic identity for deterministic digest.
6. Expose severity/priority only as analysis metadata, never authority.
7. Bind evaluator/query/model versions in receipt.

## Acceptance criteria
1. Each GALL-015/017 negative fixture maps to the expected delta type.
2. One fixture with two violations yields two independent deltas.
3. Input event ordering permutation does not change canonical delta set.
4. Removing a load-bearing observation changes delta subject predictably.
5. Aggregate score, if present, cannot substitute for delta evidence.
6. Output is consumable by GALL-029 as candidate finding evidence.

## Evidence product
Emit a content-addressed receipt binding exact finding/process/runtime/authority subjects, attempted falsifiers, outputs and evidence ceiling. Analysis and admission remain weaker than authority until the explicit GALL-030 boundary.

## Definition of done
beam4pm emits a deterministic, typed, object-linked delta between an exact normative subject and an exact observed subject, suitable for diagnosis and downstream candidate intervention.
