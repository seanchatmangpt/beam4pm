# ARD v26.9.18 — GALL-027: Semantic Attribution Conservation

**Status:** DRAFT ARCHITECTURE SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-008 semantic telemetry, GALL-024 OCEL  
**Authority ceiling:** OBSERVE/ACCOUNT only

## Architecture objective
Where the measurement domain is additive, beam4pm conserves resource attribution from semantic subject and capability through runtime spans/events to object-centric process consequences, with explicit unattributed residuals.

## Components
- typed measurement schema
- semantic correlation join
- OCEL measure relation model
- additive aggregation engine
- residual/uncertainty accounting
- attribution receipt

## Data/control flow
`Semantic telemetry + OCEL correlations -> typed measurements -> identity join -> additive aggregation + residual -> attribution evidence`

## Invariants
1. Define typed measure dimensions and units; never sum incompatible measures.
2. Carry semantic subject/capability/command/receipt correlation through telemetry-to-OCEL mapping.
3. Support additive aggregation by capability, process object, command and semantic subject where mathematically valid.
4. Track unattributed residual separately rather than forcing assignment.
5. Bind sampling/measurement method and uncertainty.
6. Support BEAM reductions and extensible AtomVM/edge energy/radio measures when observed.
7. Do not infer authority or causality solely from correlation.

## Failure/refusal boundaries
- Unit/domain incompatible => REFUSED
- Correlation missing => residual/unattributed
- Sampling uncertainty unavailable => lower evidence ceiling
- Correlation presented as causal/authority proof => architecture failure

## Qualification court
- measurement unit tests
- conservation equation fixture
- identity cross-contamination falsifier
- missing-correlation residual test
- BEAM reductions integration fixture

## Boundary law
[
Finding \neq Admission \neq Authority,\quad Prediction \neq Fact,\quad SELECT \neq DO
]

Only GALL-030 may cross the process-intervention consequence boundary, and it must reuse the existing GALL-003 authority/receipt machinery.
