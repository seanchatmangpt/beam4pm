# GALL Checkpoint 004 — Independent Observer / OCEL Seal

Status: DRAFT IMPLEMENTATION CONTRACT
Repository: `seanchatmangpt/beam4pm`
Exact admitted base: `fc164d7d4cbb54b3b8ba3a92cc71200b9e5bbce2`
Branch: `gall/checkpoint-004-independent-observer`
Owner surface: independent postcondition observation + OCEL/process conformance evidence
Authority ceiling: observation/conformance; never DO

## Preserve

`beam4pm` application source is manufactured from `ontology.ttl` plus the admitted ggen-marketplace pack. Generated files MUST NOT be hand-edited. Any new manufactured runtime/source surface starts at ontology/template/generator authority and is regenerated.

The repository observes and evaluates process evidence. It does not acquire `ash_a2a` execution authority.

## Required transition

`ash_a2a command receipt + independently read post-state + observed execution events -> OCEL 2.0 evidence -> conformance verdict -> observer receipt`

The actuator report is not the postcondition observation. A successful CommandBus reply alone cannot satisfy this checkpoint.

## Required implementation

1. Define a small hand-authored qualification rail or manufactured equivalent that consumes an exact GALL-003 receipt plus the real observable post-state.
2. Bind observation to exact producer SHA, semantic subject, command fingerprint, capability ID, receipt ID, and consequence identity.
3. Emit/validate OCEL evidence for the observed execution without making a golden full trace the oracle.
4. Check ordering relations needed by the claim, especially prepared-receipt-before-DO and no-second-DO-on-replay.
5. Produce a deterministic observer/conformance receipt whose standing cannot exceed observed evidence.
6. Keep observer identity independent from the actuator self-report.
7. Refuse mismatched/stale producer subjects and incomplete receipt/post-state pairs.

## Required falsifiers

- actuator reports success but independent post-state is unchanged;
- post-state changed twice for one idempotency identity;
- receipt names capability A while observed consequence belongs to capability B;
- producer SHA/semantic subject differs from the exact admitted checkpoint subject;
- actuation event is observed without a prepared receipt predecessor;
- replay produces a second consequence;
- OCEL omits a load-bearing object/event relation needed to reconstruct the claim;
- observer uses actuator return value as the sole postcondition oracle;
- a generated beam4pm source file is hand-edited to make the court pass.

## GALL receipt fields

- beam4pm exact head SHA;
- exact GALL-003 producer SHA + receipt digest;
- independent observer implementation identity;
- post-state observation identity/digest;
- OCEL artifact digest + validator identity;
- conformance query/model identity;
- causal/order witnesses used by the verdict;
- falsifiers attempted/survived;
- replay result;
- commands/exits/toolchain identities;
- resulting standing.

## Verification ladder

1. submodule identity/fetchability check
2. `ggen sync run --dry-run` / manufacture guard as required
3. authorship gate
4. narrow observer/OCEL/conformance test
5. `rebar3 eunit` and/or focused `mix test` for touched BEAM surface
6. `just verify` when the full repository-native chain is required
7. determinism gate if generated surfaces changed

The recently repaired Ferroplan submodule transport is a prerequisite, not proof of this observer checkpoint.

## Dependencies

Requires an exact GALL-003 command/receipt subject. It must not silently track `ash_a2a/main`.

Outputs evidence consumed by GALL-005.

## Exclusions

- no authority grant;
- no CommandBus implementation;
- no new planner;
- no cross-repo execution standing;
- no merge/publication claim.

## Definition of done

Against one exact `ash_a2a` checkpoint subject, beam4pm independently observes the real consequence and ordering, validates its OCEL/process evidence, kills the required mismatched/double-DO/missing-prepared-receipt falsifiers, and emits a deterministic observer receipt. The court remains green only while the independent evidence relation is intact.

Standing on completion: `ALIVE` for the exact independent-observer subject only.

## 2026-09-18 Weaver semantic telemetry extension

The independent-observer checkpoint now has a stacked telemetry-semantic extension in `seanchatmangpt/beam4pm#76`:

`docs/jira/GALL-CHECKPOINT-independent-observer-004-WEAVER-SEMANTIC-COURT.md`.

For OTLP-backed observation, the strengthened relation is:

`observed OTLP -> Weaver Live-check -> validated telemetry + PolicyFinding evidence -> OTel/OCEL projection -> beam4pm conformance -> independent post-state -> observer receipt`.

The following propositions MUST remain separate:

`validated telemetry != process proof != postcondition proof != authority`.

Additional load-bearing falsifiers for the OTLP path include:

- recursive PolicyFinding emission loops;
- nondeterministic Weaver template renders;
- wrong OTel-to-OCEL identity/object relations;
- stale semantic subject or capability identity;
- required semantic identity missing from telemetry;
- authority secret/token leakage into telemetry.

Weaver registry/template generation remains subordinate to beam4pm's canonical ontology + ggen manufacturing authority. PolicyFindings are observational evidence only and cannot grant DO.
