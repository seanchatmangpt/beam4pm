# ARD v26.9.18 — GALL-025: Normative / Observed Separation

**Status:** FINAL_SPEC — closed for v26.9.24  
**Implementation standing:** OPEN in PR #80 (gall/implement-024-028-process-intelligence @ eca116ea; not on main)  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-016 POWL, GALL-024 OCEL observation  
**Authority ceiling:** COMPARE/OBSERVE only

## Architecture objective
beam4pm stores and compares normative process law and observed OCEL as distinct subjects, emitting deviations/findings without allowing observations to mutate the normative model.

## Components
- normative subject loader
- observed OCEL loader
- identity-fenced comparator
- typed finding/delta model
- immutability guard
- finding receipt

## Data/control flow
`Normative POWL subject + observed OCEL subject -> compare -> typed findings/deltas -> candidate evidence receipt`

## Invariants
1. Bind normative POWL/process-law subject and observed OCEL subject independently.
2. Represent comparison output as findings/deltas with explicit evidence class.
3. No observed event or discovered model may overwrite normative source.
4. Support cases where observation is valid reality but nonconformant to law.
5. Support law-version changes as new admitted subjects, not implicit updates.
6. Expose findings downstream as candidate evidence only.

## Failure/refusal boundaries
- Normative subject missing => BLOCKED
- Observed subject missing => UNKNOWN
- Observer attempts law write => REFUSED
- Versions mismatch without explicit admission => REFUSED

## Qualification court
- compliant/noncompliant fixture tests
- normative immutability mutation test
- version identity test
- generated-source authorship guard if touched

## Boundary law
[
PortableExecution \neq Authority,\quad Observed \neq Normative,\quad QueryResult \neq FactBeyondItsSubject
]

No host/runtime/observer may silently expand the subject or rewrite process law.
