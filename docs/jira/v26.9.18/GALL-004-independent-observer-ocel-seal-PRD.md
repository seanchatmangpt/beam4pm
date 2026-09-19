# PRD v26.9.18 — GALL-004: Independent Observer / OCEL Seal

**Status:** DRAFT IMPLEMENTATION SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** Exact GALL-003 command/receipt subject  
**Authority ceiling:** OBSERVE/CONFORMANCE only; never DO

## Product thesis

A deterministic observer receipt proves what independently changed, once, under the right capability/command/receipt identity.

## Problem

An actuator cannot be the sole witness of its own success. The release needs independent post-state plus object-centric process evidence that binds the observed world change to the exact command subject and ordering.

## User / consumer

The primary consumer is another machine boundary in the GALL chain. Human maintainers need the same artifact to be inspectable, falsifiable and executable through repository-native courts. No downstream consumer is allowed to infer stronger standing than this checkpoint emits.

## Required product behavior

1. Consume exact GALL-003 receipt and independently obtain/read post-state from a system-of-record surface.
2. Bind producer SHA, semantic subject, capability, command, prepared/final receipt and consequence identities.
3. Represent load-bearing events/objects in OCEL 2.0 without requiring a golden total trace.
4. Prove prepared-receipt-before-DO and occurrence_count=1 for replay-safe subject.
5. Typed-refuse stale producer, unchanged post-state, capability mismatch, missing causal relation and self-report-only observation.
6. Keep generated beam4pm source ontology/ggen-owned.
7. When OTLP/Weaver is used, preserve telemetry-valid != process-valid != postcondition-valid != authority.

## Acceptance criteria

1. Actuator success + unchanged independent state fails.
2. Double consequence for one idempotency identity fails.
3. Wrong capability/producer SHA fails.
4. Missing prepared predecessor or load-bearing OCEL relation fails.
5. Real independent post-state + valid OCEL yields deterministic observer receipt.
6. Weaver-valid telemetry cannot compensate for invalid postcondition evidence.

## Product outputs

The implementation MUST emit a machine-readable, content-addressed checkpoint artifact/receipt that binds the exact subject, evidence ceiling, falsifiers attempted, commands/courts executed and resulting standing. Prose documentation is explanatory only and cannot confer standing.

## Success metrics

- 100% observer PASS cases contain independent post-state evidence
- 0 actuator-only successes promoted to observer PASS
- All required falsifiers actually attempted

## Non-goals

- Authority
- CommandBus implementation
- Planner
- Re-actuation to verify

## Release semantics

- A configured workflow is not execution evidence.
- Source presence is not runtime standing.
- Local PASS, hosted PASS, runtime standing, merge and publication remain separate evidence classes.
- Any changed base/head SHA is a changed subject unless explicitly re-admitted.
- UNKNOWN/PARTIAL/REFUSED/BLOCKED states are preserved rather than collapsed into generic failure.

## Definition of done

A deterministic observer receipt proves what independently changed, once, under the right capability/command/receipt identity.

The exact v26.9.18 subject earns only the bounded standing proven by its repository-native court. No cross-repository promotion is implied.
