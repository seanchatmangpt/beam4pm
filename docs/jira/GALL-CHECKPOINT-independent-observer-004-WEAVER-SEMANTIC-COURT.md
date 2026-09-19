# GALL-004 Extension — Weaver Semantic Court Before OCEL Conformance

Status: DRAFT IMPLEMENTATION CONTRACT  
Repository: `seanchatmangpt/beam4pm`  
Stacked base: `gall/checkpoint-004-independent-observer@6a5976ed4fc6f0aad9fa932c0d041edb124f0138`  
Owner surface: OpenTelemetry semantic validation + deterministic telemetry projection  
Authority ceiling: observation / validation / manufacture only; never DO

## 1. Subject

GALL-004 already requires:

`GALL-003 receipt + independently read post-state + observed events -> OCEL -> conformance -> observer receipt`.

This extension inserts an independent semantic telemetry court before OCEL admission:

`observed OTLP -> Weaver live-check -> semantically validated telemetry + PolicyFinding evidence -> OTel/OCEL projection -> beam4pm conformance -> observer receipt`.

The purpose is not to make Weaver authoritative over beam4pm. The purpose is to prevent arbitrary or malformed telemetry from silently acquiring the standing of process evidence.

## 2. Prior-art fence

Use OpenTelemetry Weaver for what it already owns:

- semantic-convention registry resolution and validation;
- deterministic registry-driven template rendering;
- `registry generate` over materialized resolved schema;
- Live-check over OTLP observations;
- custom runtime advice through Rego;
- typed `PolicyFinding` output;
- optional OTLP log emission for findings;
- generated-artifact drift checks.

Upstream references:

- https://github.com/open-telemetry/weaver
- https://github.com/open-telemetry/weaver/blob/main/crates/weaver_live_check/README.md
- https://github.com/open-telemetry/weaver/blob/main/crates/weaver_live_check/docs/dog-fooding.md
- https://github.com/open-telemetry/opentelemetry-weaver-examples
- https://github.com/open-telemetry/weaver/blob/main/schemas/semconv-schemas.md

Do not reimplement Weaver registry resolution, MiniJinja rendering, live semantic validation, or Rego policy evaluation inside beam4pm.

## 3. Canonical authority

The beam4pm canonical graph remains the authority.

```text
ontology.ttl / ontology/**/*.ttl
          |
          | ggen manufacture
          v
beam4pm canonical projections
          |
          +----------------------------+
          |                            |
          v                            v
application/runtime artifacts      OTel semconv projection
                                       |
                                       v
                                  Weaver registry
                                       |
                          +------------+-------------+
                          |                          |
                          v                          v
                   registry generate           live-check
                          |                          |
                          v                          v
                 telemetry artifacts          PolicyFinding
```

Weaver is a subordinate specialist manufacturer and validator over a projection of admitted beam4pm semantics.

The prohibited inversion is:

`Weaver registry -> becomes beam4pm ontology authority`.

The required direction is:

`beam4pm O* -> deterministic semconv projection -> Weaver`.

## 4. Manufacturing split

Preserve two distinct manufacturing functions:

`mu_ggen(O*) -> beam4pm application/process artifacts`

`mu_weaver(O*_telemetry) -> telemetry-specific generated artifacts`

Examples of Weaver-generated targets MAY include:

- Erlang attribute/event constants;
- Elixir attribute/event constants;
- Gleam telemetry constants;
- Rust/eBPF semantic IDs;
- AtomVM telemetry vocabulary;
- Rego policy support data;
- generated semantic-convention documentation.

These targets are projections. They do not become independent semantic authority.

If generated application source is required, normal beam4pm source-authority rules remain in force: repair ontology/template/generator input and regenerate. Do not hand-edit generated projections.

## 5. Runtime evidence pipeline

Required runtime relation:

```text
SA2A intent
   |
SELECT / authority / BRCE
   |
   v
  DO
   |
   v
World'
   |
   +---------------------+
   |                     |
   v                     v
independent post-state   OTLP observations
                              |
                              v
                    Weaver live-check
                              |
                 +------------+-------------+
                 |                          |
                 v                          v
          validated telemetry          PolicyFinding
                 |                          |
                 +------------+-------------+
                              |
                              v
                         OTel -> OCEL
                              |
                              v
                           beam4pm
                              |
                 process reconstruction
                    + conformance
                    + consequence profile
                              |
                              v
                       observer receipt
```

This creates separate propositions:

1. telemetry is structurally and semantically valid;
2. telemetry can be projected into process evidence;
3. process evidence supports the claimed ordering/consequence;
4. independent post-state supports the claimed world change.

No proposition implies the next one automatically.

## 6. Evidence algebra

Let:

- `T` = observed telemetry;
- `S` = admitted semantic-convention registry;
- `W(T,S)` = Weaver validation result;
- `F` = emitted PolicyFindings;
- `O(T)` = OTel-to-OCEL projection;
- `C(O)` = beam4pm process/conformance result;
- `P` = independent post-state observation.

A GALL-004 observer receipt may reach ALIVE only if the subject-specific court proves all required predicates:

`W(T,S) = PASS`

and

`C(O(T)) = PASS`

and

`Postcondition(P) = PASS`

and

`Identity(T, O, P, receipt, capability, exact_subject) = PASS`.

A Weaver pass alone is never sufficient.

## 7. Semantic identity

The semconv projection SHOULD preserve opaque identifiers for:

- exact repository/runtime subject;
- semantic objective;
- semantic task;
- semantic action;
- capability ID;
- receipt correlation ID;
- authority-grant ID or digest;
- actor/role identity;
- runtime node/process/device identity;
- trace/span/link identity where present.

Do not place authority tokens, credentials, secrets, or bearer material into telemetry. Only opaque IDs/digests may cross the observation boundary.

## 8. BEAM semantic consequence surface

The first repository-native implementation should target BEAM rather than invent a generic multi-runtime abstraction first.

Candidate additive BEAM measures include:

- reductions;
- process heap words;
- mailbox length / mailbox delta;
- messages sent/received;
- garbage-collection count/time where available;
- scheduler/runtime duration;
- process start/stop/restart observations;
- supervisor relationship;
- node identity.

These are runtime measures, not business meaning.

Semantic responsibility comes from the admitted semantic path.

Target relation:

`BEAM runtime effects + semantic path -> SemanticOperation -> conserved profile`.

PID identity is transport identity, not semantic responsibility identity.

## 9. AtomVM extension boundary

AtomVM is an admitted extension target, not required for the first closure.

The same semantic identity MAY later carry typed edge measures such as:

- wakeups;
- radio bytes;
- flash writes;
- GPIO transitions;
- sensor reads;
- elapsed awake time;
- energy observations where the hardware supplies them.

Do not coerce incomparable measures into one unit.

`reductions != wasm fuel != joules`.

The shared key is semantic identity, not unit equivalence.

## 10. Weaver Live-check findings as process evidence

A `PolicyFinding` may be projected into OCEL as an observation object/event so that beam4pm can study process variants associated with semantic violations.

Examples:

- missing required semantic attribute;
- wrong attribute type;
- entity/convention mismatch;
- custom Rego finding;
- missing runtime identity;
- missing semantic-action identity.

A finding remains observational evidence.

`PolicyFinding != authority != refusal to DO`

unless a separate admitted policy consumes that finding and reaches a lawful SELECT/BRCE decision.

## 11. Loop isolation

If Weaver emits findings as OTLP logs, the pipeline MUST prevent recursive finding ingestion from creating an infinite validation loop.

Required invariant:

`weaver finding telemetry` is identifiable as validator output and cannot be reintroduced as an unbounded new subject to the same live-check stream.

The implementation court must include a loop falsifier.

## 12. Template-render court

The Weaver generation side must prove determinism separately from live runtime validation.

Required checks:

1. same exact registry + same exact templates + same Weaver subject -> byte-identical outputs;
2. generated output drift is detected by regenerate-and-diff;
3. a registry semantic change causes the expected generated delta;
4. unrelated registry order does not create nondeterministic output;
5. generated artifact cannot silently introduce a semantic key absent from the resolved registry;
6. template failure is BUILD_BROKEN, not silently skipped;
7. generated files remain projections, never canonical authority.

The first implementation MAY use Weaver's published container image pinned by digest or exact version, provided the exact producer identity is receipted.

## 13. Live-check court

Required narrow runtime proof:

1. start a pinned Weaver live-check subject against the exact semconv registry;
2. emit one valid BEAM semantic operation over OTLP;
3. prove it passes semantic validation;
4. project it to OCEL;
5. preserve semantic responsibility identity;
6. independently observe the post-state required by GALL-004;
7. emit one deterministic observer receipt;
8. replay without second DO.

Negative fixtures must demonstrate that malformed or semantically incomplete telemetry does not acquire equivalent standing.

## 14. Required falsifiers

The exact-head court must kill at least:

- required semantic action ID absent;
- exact subject ID stale or mismatched;
- capability ID mismatched;
- telemetry attribute type invalid;
- unknown/invalid semantic key accepted as authoritative process meaning;
- Weaver passes while independent post-state is unchanged;
- actuator self-report used as sole postcondition observation;
- valid telemetry projected to wrong OCEL object relation;
- required prepared-receipt ordering absent;
- replay produces a second consequence;
- PolicyFinding recursively re-enters live-check indefinitely;
- Weaver template output changes across identical runs;
- generated telemetry constant exists without registry authority;
- actual authority secret leaks into telemetry;
- generated beam4pm application source is hand-edited to make the court pass.

## 15. Proposed repository surfaces

This contract does not require these exact paths, but the implementation should preserve this separation:

```text
ontology/
  ... canonical beam4pm facts

schema/otel/
  ... generated semantic-convention registry projection

templates/weaver/
  ... admitted Weaver templates, or generated projection thereof

qualification/weaver/
  ... narrow fixtures / Rego advice / live-check harness

receipts/weaver/
  ... exact-subject generation/live-check evidence

docs/reference/
  ... generated telemetry reference if admitted
```

If any proposed path falls under an existing generated/manufactured root, follow the repository's authorship gate and ggen authority rules rather than bypassing them.

## 16. Relationship to GALL-004

Base GALL-004 remains responsible for:

`receipt + independent post-state + observed process -> OCEL -> conformance -> observer receipt`.

This extension adds a semantic admission court for telemetry before OCEL:

`raw OTLP -> Weaver -> semantically bounded observations`.

Therefore:

`GALL-004-Weaver` does not replace GALL-004.

It strengthens the observation chain.

## 17. Relationship to Semantic A2A

Semantic A2A supplies admitted semantic identity and authority context.

Weaver validates the runtime telemetry projection of that identity.

beam4pm reconstructs and evaluates the resulting process evidence.

The boundaries are:

`SA2A = semantic intent / policy / authority context`

`Weaver = telemetry semantic validation / specialized render`

`beam4pm = process evidence / conformance / independent observation`

`BRCE = exclusive DO boundary`.

## 18. Relationship to semantic consequence profiling

The AutoFDE semantic consequence profiler and this court are complementary.

Weaver asks:

`Does observed telemetry conform to the declared semantic telemetry contract?`

The profiler asks:

`What additive computational/physical consequences belong to this semantic responsibility?`

beam4pm asks:

`What independently observed process and post-state does the evidence establish?`

A valid Weaver finding or valid telemetry record is input evidence, not process standing by itself.

## 19. Verification ladder

1. exact stacked base identity;
2. source-authority / generated-file classification;
3. ggen dry-run / deterministic manufacture gate as required;
4. semconv projection validation;
5. Weaver registry generation determinism;
6. narrow valid telemetry live-check;
7. required malformed-telemetry falsifiers;
8. OTel-to-OCEL identity projection;
9. GALL-004 independent postcondition court;
10. replay/no-second-DO court;
11. authorship gate;
12. focused BEAM tests;
13. `just verify` when repository-native full closure is required.

## 20. Standing

At PR creation this document is architecture/implementation-contract evidence only.

It does not claim:

- Weaver installed in beam4pm;
- semconv registry generation executed;
- Live-check executed;
- OTLP ingested;
- BEAM reductions observed;
- AtomVM observed;
- OTel-to-OCEL projection ALIVE;
- GALL-004 observer closure;
- cross-repository Semantic A2A standing;
- merge;
- publication;
- deployment.

Target standing after the required exact-head courts:

`ALIVE` for the exact beam4pm Weaver semantic-observation subject only.

## 21. Definition of done

For one exact Semantic A2A / GALL-003 consequence, beam4pm can:

1. manufacture or resolve the exact admitted telemetry semantic convention;
2. validate real OTLP observations with Weaver Live-check;
3. preserve findings without recursive loops;
4. project validated observations into OCEL without semantic identity loss;
5. independently verify the relevant post-state and ordering;
6. emit a deterministic GALL-004 observer receipt;
7. replay the evidence without additional actuation;
8. kill every required semantic-telemetry and process falsifier.

The resulting court proves:

`validated telemetry != process proof != postcondition proof != authority`.

Each relation must be earned independently.

## 22. Code-review rebasing — 2026-09-18

Reviewed beam4pm base implementation at `gall/checkpoint-004-independent-observer@96150118eeeabc9d5b296399232d745d61b5e833`, whose code review was grounded on source subject `054022550bc069de4b03609f514dfa8e1442a27a`.

The implementation order is now narrowed by what exists:

1. `BeamPM.OcelIngest.Router` is real but accepts repository-native snake_case OCEL relationship keys (`object_id`), while standard OCEL 2.0 exporters in the ecosystem use `objectId`. Normalize this at an admitted adapter/generator boundary before using generic "OCEL2 accepted" as a court predicate.
2. `BeamPM.Ocel` has process/object query and envelope validation logic, but its general encode/decode signature does not carry the nested relationship pairs used by the query API. GALL-004-Weaver must prove relationship-preserving ingress rather than event/object parseability alone.
3. network ingest does not persist observer state. The Weaver court needs a durable or exact immutable observation artifact that can be independently re-read after the actuator path is gone.
4. there is no reviewed beam4pm implementation of Weaver Live-check / OTLP semantic admission yet.

Therefore the first implementation slice is NOT "BEAM reductions" yet. The dependency order is:

`standard OTLP/OCEL identity -> Weaver semantic court -> relationship-preserving normalized OCEL artifact -> independent GALL-004 observer`

then:

`BEAM semantic consequence measures`.

BEAM reductions/mailbox/heap/etc. remain the first consequence-profile extension after the semantic observation path itself has standing.

### New load-bearing falsifiers from code review

- standard OCEL `objectId` enters and emerges as the same relationship identity after normalization;
- snake_case/internal representation is never mistaken for a second semantic authority;
- an event/object round trip that drops E2O/O2O relations MUST fail;
- an ingest response without durable/exact observer evidence MUST NOT satisfy independent-observer standing;
- no claim of Weaver execution is permitted from architecture/docs alone.

### Revised review standing

- current beam4pm OCEL substrate: `PARTIAL_ALIVE`;
- standard OCEL wire normalization: `UNKNOWN`;
- Weaver Live-check runtime: `UNKNOWN`;
- semantic BEAM consequence profiling in beam4pm: `UNKNOWN`;
- GALL-004-Weaver exact subject: `UNKNOWN`.
