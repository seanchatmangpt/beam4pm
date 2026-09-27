# ARD v26.9.18 — GALL-028: Multi-Clock Control

**Status:** FINAL_SPEC — closed for v26.9.24  
**Implementation standing:** OPEN in PR #80 (gall/implement-024-028-process-intelligence @ eca116ea; not on main)  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-019 prediction, GALL-026 conformance delta, GALL-027 attribution  
**Authority ceiling:** OBSERVE/RECOMMEND control candidates; no DO

## Architecture objective
beam4pm classifies findings into explicit fast, medium and slow control horizons, each with its own evidence threshold, state aggregation and downstream candidate contract.

## Components
- horizon classifier
- window/state aggregator
- FAST finding adapter
- MEDIUM predictive adapter
- SLOW redesign evidence builder
- multi-clock receipt

## Data/control flow
`Conformance/prediction/attribution evidence -> horizon classification -> windowed aggregation -> FAST/MEDIUM/SLOW candidate findings`

## Invariants
1. Define at least FAST conformance/refusal, MEDIUM prediction/adaptation and SLOW process-redesign horizons.
2. Bind every finding/control candidate to its horizon and evidence window.
3. FAST loop may surface immediate bounded intervention candidates but cannot redesign normative process law.
4. MEDIUM loop aggregates enough evidence for predictive/parameter adaptation candidates.
5. SLOW loop requires durable multi-run evidence before process redesign candidate issuance.
6. Prevent one observation from silently satisfying all three horizons.
7. Expose clock/window configuration as exact subject identity.

## Failure/refusal boundaries
- Evidence window insufficient => remain lower horizon/UNKNOWN
- Clock config missing => no standing
- Finding crosses horizon without threshold => REFUSED
- Control candidate attempts DO => architecture violation

## Qualification court
- single-event horizon test
- window threshold progression test
- clock-config identity test
- fast-to-slow leakage falsifier

## Boundary law
[
Finding \neq Admission \neq Authority,\quad Prediction \neq Fact,\quad SELECT \neq DO
]

Only GALL-030 may cross the process-intervention consequence boundary, and it must reuse the existing GALL-003 authority/receipt machinery.
