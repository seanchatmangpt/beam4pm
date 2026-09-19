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

## Implementation specifics — refined 2026-09-18

Current docs-only PR head at this refinement: `6a5976ed4fc6f0aad9fa932c0d041edb124f0138`.

### Verified existing repository boundaries

The ticket MUST respect beam4pm's manufacturing law:

- `ontology.ttl` is canonical instance/semantic input.
- `vendor/ggen-marketplace/packs/beam4pm-process-model-pack` owns generated application projections.
- generated files are identified by the `GENERATED by ggen ... Do not edit.` header, not by directory.
- `scripts/gate_authorship_check.sh` enforces admitted hand-authored source.
- `scripts/gate_m2_check.sh` is the destructive determinism/regeneration court for generated surfaces.
- `scripts/roundtrip_check.sh` is the existing BEAM wire-format roundtrip court.
- `rebar3 eunit`, `mix test`, and `just verify` are the repository-native verification path.
- the OTLP/Weaver semantic extension is separately specified in PR #76 and remains subordinate to this observer claim.

### Smallest coherent implementation shape

Prefer a **hand-authored qualification rail under `scripts/`** so GALL-004 can consume external evidence without manufacturing a new application subsystem merely for the court.

Proposed entrypoint:

`scripts/gall_checkpoint_004_observer.exs`

Inputs:

```text
--gall-003-receipt <path>
--producer-sha <sha>
--post-state <adapter-or-artifact>
--ocel <path>
--out <observer-receipt.json>
```

The script MUST:

1. parse and validate the exact GALL-003 subject;
2. independently obtain/read the post-state;
3. load the OCEL/event evidence;
4. bind capability/command/receipt identities across both;
5. evaluate required ordering relations;
6. detect duplicate consequence/replay;
7. emit one deterministic observer receipt.

If implementation requires changes under generated roots, first modify `ontology.ttl` or the vendored pack and regenerate. If a new hand-authored fixture/source is added under a governed root, admit it through the repository's `bpm:HandAuthoredSource` mechanism before use.

### Independent post-state adapter contract

The observer MUST NOT call `ash_a2a` for “did it work?” as its only source.

A valid adapter returns a canonical observation such as:

```text
observer_id
observed_at
resource_identity
semantic_subject_digest
consequence_identity
post_state_digest
occurrence_count
source_type
source_locator
```

Allowed source types include a database read, filesystem state, external test HTTP service state, runtime telemetry source, or another real system-of-record surface appropriate to the consequence.

The adapter's own code/version identity MUST enter the observer receipt.

### OCEL minimum object/event vocabulary

For the GALL court, require at least:

Objects:
- `SemanticSubject`
- `Capability`
- `Command`
- `Receipt`
- `Consequence`
- `ObservedResource`

Events:
- `receipt_prepared`
- `do_attempted`
- `do_acknowledged` or equivalent observed consequence event
- `receipt_finalized` or `receipt_pending`
- `post_state_observed`
- `replay_attempted` when replay is tested

Load-bearing relations MUST make it possible to prove:

`receipt_prepared < do_attempted <= observed_consequence < post_state_observed`

and, for replay:

`count(observed_consequence for idempotency_key) = 1`.

Do not require a byte-for-byte golden total event trace; require only the causal/identity relations needed by the claim.

### Proposed court fixture

Use the exact real external consequence fixture already exercised by ash_a2a GALL-003 where practical.

Fixture bundle handed to beam4pm:

```text
gall-003-receipt.json
producer-runtime-identity.json
observed-post-state.json
events.ocel.json
```

Expected output:

`observer-receipt.json`

The output digest is the GALL-004 handoff to autofde-lab.

### Required falsifier corpus

Create a fixture set that changes one dimension at a time:

1. `wrong-capability-id`
2. `stale-producer-sha`
3. `missing-prepared-event`
4. `unchanged-post-state`
5. `double-consequence`
6. `missing-load-bearing-ocel-relation`
7. `actuator-self-report-only`
8. `weaver-valid-but-postcondition-invalid` when PR #76 path is exercised

Every falsifier must be attempted. Merely omitting invalid fixtures is not Chicago evidence.

### Exact acceptance commands

Base path:

```bash
git submodule update --init --recursive
bash scripts/gate_authorship_check.sh
rebar3 eunit
mix test
just verify
```

If generated surfaces changed:

```bash
bash scripts/gate_m2_check.sh
```

If the OTLP/Weaver path is part of the exact subject, additionally execute the exact Weaver court defined by PR #76. Do not substitute a JSON-schema parse for Weaver Live-check.

### Handoff artifact to GALL-005

Minimum observer receipt:

```text
beam4pm_repo_sha
gall_003_receipt_digest
gall_003_producer_sha
semantic_subject_digest
capability_id
command_fingerprint
independent_observer_id
post_state_digest
ocel_digest
conformance_model_or_query_digest
ordering_witnesses[]
occurrence_count
falsifiers_attempted[]
replay_result
standing
```

### Stop conditions

Stop rather than absorbing authority or planner behavior when:

- no independent system-of-record/post-state can be read;
- the only evidence is the actuator response;
- required OCEL identities cannot be correlated;
- the needed source change would require hand-editing generated beam4pm code;
- the exact GALL-003 producer subject is unavailable.

The result is `BLOCKED`, `UNSUPPORTED`, or typed refusal. beam4pm does not compensate by re-actuating the command.

## 2026-09-18 exact-head code review

Reviewed source subject: `054022550bc069de4b03609f514dfa8e1442a27a`.

### Observed implementation

beam4pm already has real pieces of the observer substrate:

- the generated `BeamPM.OcelIngest.Router` exposes admitted network routes for events/objects and validates them into generated OCEL record types;
- `BeamPM.Ocel` provides object traces, relationship queries, dangling-reference validation, and a general event/object JSON codec surface;
- Rust4PM/POWL/conformance surfaces exist for downstream process analysis.

However, these pieces do not yet constitute GALL-004 independent-observer standing.

### Wire-identity gap

The generated network ingest uses repository-native snake_case keys, including relationship `object_id`. Standard OCEL 2.0 exporters in the current ecosystem (including `GgenIgniter.Telemetry.Ocel2Export`) use `objectId`.

Therefore:

`standard OCEL2 relationship != current /ocel/events relationship wire shape`.

The court must either admit a deterministic normalization adapter or change the generated wire projection at its canonical source. It must then falsify dropped/misbound E2O/O2O relations. Silent key coercion is not acceptable.

### Relationship round-trip gap

`BeamPM.Ocel.encode/1` and `decode/1` operate on event/object structs, while relationships are carried separately by the query API as `{record, rels}` pairs. The generic codec does not itself bind those nested relations through its public signature.

Because GALL-004 ordering/postcondition evidence depends on relationships, its court must prove relationship-preserving round trip rather than treating event/object parse success as sufficient OCEL evidence.

### Observer-state gap

The network ingest router decodes and returns records but owns no durable observation store. That is an explicit design choice in the module docs. GALL-004 therefore still needs an exact observer artifact/state boundary from which an independent court can reconstruct what happened after the actuator returns.

### Weaver/OTLP gap

No reviewed beam4pm source path implements Weaver Live-check or OTLP semantic admission. PR #76 is currently an implementation contract, not runtime code.

The strengthened court remains:

`raw OTLP -> Weaver semantic validation -> normalized OCEL -> process/conformance -> independent post-state -> observer receipt`.

Each arrow requires observed evidence; a valid OCEL decode is not a substitute for independent post-state observation.

### Revised next action

1. canonicalize the standard-OCEL2-to-internal relationship adapter through ontology/ggen ownership;
2. add a relationship-preserving OCEL falsifier;
3. define the durable/read-once observer artifact used by the independent court;
4. implement the PR #76 Weaver semantic-validation rail against real OTLP;
5. bind the validated telemetry identity to one exact GALL-003 receipt and an independently observed post-state;
6. emit the deterministic observer receipt.

### Review standing

- OCEL ingest/query/conformance substrate: `PARTIAL_ALIVE` by source inspection;
- independent postcondition observer: `UNKNOWN`;
- Weaver/OTLP semantic court: `UNKNOWN`;
- cross-repository GALL-004 seal: `UNKNOWN`.
