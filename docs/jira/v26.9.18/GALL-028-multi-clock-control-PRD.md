# PRD v26.9.18 — GALL-028: Multi-Clock Control

**Status:** FINAL_SPEC — closed for v26.9.24  
**Implementation standing:** OPEN in PR #80 (gall/implement-024-028-process-intelligence @ eca116ea; not on main)  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-019 prediction, GALL-026 conformance delta, GALL-027 attribution  
**Authority ceiling:** OBSERVE/RECOMMEND control candidates; no DO

## Product outcome
beam4pm classifies findings into explicit fast, medium and slow control horizons, each with its own evidence threshold, state aggregation and downstream candidate contract.

## Problem
Fast runtime conformance, medium-horizon adaptation and slow process redesign operate on different evidence horizons. Collapsing them into one feedback loop causes noise-driven redesign or slow response to immediate violations.

## Functional requirements
1. Define at least FAST conformance/refusal, MEDIUM prediction/adaptation and SLOW process-redesign horizons.
2. Bind every finding/control candidate to its horizon and evidence window.
3. FAST loop may surface immediate bounded intervention candidates but cannot redesign normative process law.
4. MEDIUM loop aggregates enough evidence for predictive/parameter adaptation candidates.
5. SLOW loop requires durable multi-run evidence before process redesign candidate issuance.
6. Prevent one observation from silently satisfying all three horizons.
7. Expose clock/window configuration as exact subject identity.

## Acceptance criteria
1. Single immediate violation reaches FAST but not automatically SLOW.
2. Repeated qualified evidence can satisfy MEDIUM/SLOW thresholds according to fixture configuration.
3. Changing horizon/window config changes subject identity.
4. FAST candidate cannot mutate normative law.
5. Slow redesign candidate cites aggregate evidence set.
6. Findings can be consumed by GALL-029 without authority.

## Evidence product
Emit a content-addressed receipt binding exact finding/process/runtime/authority subjects, attempted falsifiers, outputs and evidence ceiling. Analysis and admission remain weaker than authority until the explicit GALL-030 boundary.

## Definition of done
beam4pm classifies findings into explicit fast, medium and slow control horizons, each with its own evidence threshold, state aggregation and downstream candidate contract.
