# ARD v26.9.18 — GALL-004: Independent Observer / OCEL Seal

**Status:** FINAL_SPEC — closed for v26.9.24  
**Implementation standing:** OPEN in PR #75 (gall/checkpoint-004-independent-observer @ ed896969; Weaver court stacked in PR #76 @ 89d9e1fa; not on main)  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** Exact GALL-003 command/receipt subject  
**Authority ceiling:** OBSERVE/CONFORMANCE only; never DO

## Architectural objective

A deterministic observer receipt proves what independently changed, once, under the right capability/command/receipt identity.

The architecture follows the Chatman separation laws:

[
Received \neq Admitted,\quad Candidate \neq Authority,\quad SELECT \neq CONSTRUCT \neq DO
]

and every consequence/evidence claim is bounded by exact subject identity and replayable receipts.

## Load-bearing components

- `scripts/gall_checkpoint_004_observer.exs` — proposed qualification rail
- independent post-state adapter
- OCEL event/object evidence
- beam4pm conformance model/query
- `scripts/gate_authorship_check.sh` / `gate_m2_check.sh` manufacturing guards
- PR #76 Weaver court when OTLP path is included

## Data / control flow

`GALL-003 receipt + independent post-state + events -> OCEL identity/order checks -> conformance -> falsifiers -> observer receipt`

## Interfaces

- Input bundle: GALL-003 receipt, producer identity, post-state observation, OCEL
- Output: observer-receipt.json
- Downstream: GALL-005

## Required invariants

1. Consume exact GALL-003 receipt and independently obtain/read post-state from a system-of-record surface.
2. Bind producer SHA, semantic subject, capability, command, prepared/final receipt and consequence identities.
3. Represent load-bearing events/objects in OCEL 2.0 without requiring a golden total trace.
4. Prove prepared-receipt-before-DO and occurrence_count=1 for replay-safe subject.
5. Typed-refuse stale producer, unchanged post-state, capability mismatch, missing causal relation and self-report-only observation.
6. Keep generated beam4pm source ontology/ggen-owned.
7. When OTLP/Weaver is used, preserve telemetry-valid != process-valid != postcondition-valid != authority.

## Failure and refusal boundaries

- Only actuator response available => BLOCKED
- Generated source would need hand edit => REFUSED; change ontology/pack instead
- Exact GALL-003 subject unavailable => BLOCKED
- Identity correlation missing => REFUSED/UNKNOWN

A refusal is a valid architectural result. The implementation MUST NOT add model inference, private state, ambient dependencies, alternate authority paths or hand-written generated projections merely to make a court green.

## Repository-native qualification court

- `git submodule update --init --recursive`
- `bash scripts/gate_authorship_check.sh`
- `rebar3 eunit`
- `mix test`
- `just verify`
- `bash scripts/gate_m2_check.sh` when generated surfaces change
- exact PR #76 Weaver court when in subject

Each command is recorded with exact head SHA, relevant lock/toolchain identities, exit status and artifact digests. A later run against a different subject does not inherit this standing.

## Evidence contract

The checkpoint receipt MUST contain enough identity to let the next boundary validate:

- producer repository and exact SHA;
- semantic/manufacturer/runtime subject as applicable;
- predecessor receipt digests;
- court/falsifier identities;
- exact output artifact digests;
- standing and evidence ceiling.

## Security / authority

Authority is never inferred from capability, model output, successful parsing, observation, conformance, generated source or prior execution. Secrets and bearer credentials are never embedded into cross-repository evidence receipts; only opaque grant/principal identities needed for correlation are allowed.

## Definition of architectural closure

The architecture is closed only when the positive witness executes and every required negative witness is actually attempted against the exact subject. Configuration, source inspection or absence of a violation without an attempted falsifier is insufficient.
