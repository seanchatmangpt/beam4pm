# WBPR — GALL-004 Independent Observer / OCEL Seal

**Working-backwards target. This document describes the evidence state required for release.**

## Headline

**beam4pm verifies what actually happened instead of trusting the actuator that says it happened.**

## Subheadline

GALL-004 gives Semantic A2A an independent process-observation court: the command receipt, actual post-state, and observed execution are joined into OCEL 2.0 evidence and tested for identity, ordering, replay, and conformance.

## Announcement

At completion, `beam4pm` closes the independent-observation boundary:

`GALL-003 command receipt + independent post-state + observed events -> OCEL -> conformance -> observer receipt`

This is the point where “the actuator returned success” stops being sufficient evidence.

## Customer problem

Self-report collapses action and verification.

If the same subsystem both performs a consequence and declares that the consequence was correct, several failures can hide:

- success response with no state change;
- duplicate consequence hidden behind a single receipt;
- wrong capability causing a valid-looking mutation;
- missing prepared-receipt ordering;
- stale producer identity;
- incomplete process evidence.

A consequential machine system needs an observer whose evidence source is different from the actuator return path.

## Product

GALL-004 consumes one exact GALL-003 producer subject and independently binds:

- producer SHA and command receipt;
- semantic subject and capability;
- independent post-state;
- OCEL event/object relations;
- causal/ordering evidence;
- conformance query/model;
- falsifier results;
- observer receipt.

The observer does not gain authority to perform the consequence.

## Customer experience

The actuator does its job.

beam4pm then answers a separate question:

**What did the world actually show?**

It can establish whether:

- the expected state changed;
- the change belongs to the same command/capability;
- preparation preceded actuation;
- replay caused no second consequence;
- the process evidence is complete enough to support the claim.

## Core invariant

`ActuatorReport != PostconditionObservation`

And:

`PASS = AttemptObserved && ForbiddenOutcomeAbsent`

not merely:

`PASS = !ObservedViolation`

## Release proof

A releasable exact head must kill at least these falsifiers:

1. success report with unchanged independent post-state;
2. two post-state changes for one idempotency identity;
3. receipt/capability mismatch;
4. stale producer SHA or semantic subject;
5. observed DO without prepared-receipt predecessor;
6. replay causing a second consequence;
7. incomplete OCEL relation needed for reconstruction;
8. observer accidentally depending only on actuator return value.

If generated beam4pm source must change, the ontology/template/ggen manufacture path remains authoritative.

## Chicago relation

GALL-004 is the primary owner of Chicago's independent-postcondition and process-evidence proof. It also strengthens replay and receipt-binding evidence.

## Non-claims

This release does not:

- authorize DO;
- replace ash_a2a;
- create another planner;
- turn an OCEL file into authority;
- claim final cross-repository conformance by itself.

## Working-backwards definition of done

For one exact GALL-003 consequence, a separate observer can reconstruct enough of the event/post-state relation to decide whether the consequence actually occurred as claimed, once, under the right identity and ordering.

The result is an observer receipt that can be consumed without trusting the actuator's testimony.
