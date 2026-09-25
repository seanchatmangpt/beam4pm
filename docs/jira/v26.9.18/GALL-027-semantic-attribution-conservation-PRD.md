# PRD v26.9.18 — GALL-027: Semantic Attribution Conservation

**Status:** FINAL_SPEC — closed for v26.9.24  
**Implementation standing:** OPEN in PR #80 (gall/implement-024-028-process-intelligence @ eca116ea; not on main)  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-008 semantic telemetry, GALL-024 OCEL  
**Authority ceiling:** OBSERVE/ACCOUNT only

## Product outcome
Where the measurement domain is additive, beam4pm conserves resource attribution from semantic subject and capability through runtime spans/events to object-centric process consequences, with explicit unattributed residuals.

## Problem
Runtime resource measurements lose strategic value when CPU, BEAM reductions, memory, latency, energy or radio cost cannot be traced back to the exact semantic subject/capability/process objects that caused them.

## Functional requirements
1. Define typed measure dimensions and units; never sum incompatible measures.
2. Carry semantic subject/capability/command/receipt correlation through telemetry-to-OCEL mapping.
3. Support additive aggregation by capability, process object, command and semantic subject where mathematically valid.
4. Track unattributed residual separately rather than forcing assignment.
5. Bind sampling/measurement method and uncertainty.
6. Support BEAM reductions and extensible AtomVM/edge energy/radio measures when observed.
7. Do not infer authority or causality solely from correlation.

## Acceptance criteria
1. Fixture measure total equals attributed components plus explicit residual within declared tolerance.
2. Cross-capability mix does not leak attribution between identities.
3. Unit mismatch is rejected.
4. Missing correlation increases residual rather than arbitrary attribution.
5. BEAM reduction fixture maps to exact command/capability subject.
6. Repeated aggregation is order-independent for additive measures.

## Evidence product
Emit a content-addressed receipt binding exact finding/process/runtime/authority subjects, attempted falsifiers, outputs and evidence ceiling. Analysis and admission remain weaker than authority until the explicit GALL-030 boundary.

## Definition of done
Where the measurement domain is additive, beam4pm conserves resource attribution from semantic subject and capability through runtime spans/events to object-centric process consequences, with explicit unattributed residuals.
