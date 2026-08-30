# First-Principles Rewrite Rationale: BeamPM.Governor -> BeamPM.ProcessGovernor

## What was wrong (cited against the 4-lens audit)

The concurrently-merged `beam4pm-process-model-pack/templates/beam4pm_governor.ex.tmpl`
(`BeamPM.Governor`) was a second, independent implementation of the exact
Planner != Policy != Authority boundary `BeamPM.Actuation` already implements and had
already qualified (254/254 tests, a live self-mining script) the same day. Concretely:

1. **Zero shared code, zero delegation** (duplication, CONFIRMED_CRITICAL). `grep` for
   `BeamPM.Actuation|beam4pm-brce/v1|GymBridge` across both Governor template files
   returned zero hits. `apply_transition/5` re-derived its own plan/policy/authority/
   receipt/replay concepts from scratch instead of reusing the real, already-qualified
   pipeline.
2. **Zero I/O anywhere in `apply_transition/5`** (duplication, CONFIRMED_CRITICAL). The
   function's only work was four `Map`/string guard checks and a `canonical_hash` over
   joined strings - no `File`, `Port`, or network call anywhere in the module. It could
   not be a genuine DO/actuation path despite its own moduledoc calling it "a
   deterministic post-LLM execution boundary."
3. **Live render confirmed, not hypothetical** (duplication, CONFIRMED_CRITICAL). Running
   the real ggen 26.8.18 binary against beam4pm's own `ggen.toml`/`ontology.ttl`
   render-confirmed `lib/beam4pm_governor.ex` as a real output sitting alongside
   `beam4pm_types.ex`/`beam4pm_codec.ex`/`beam4pm_discovery.ex` - the collision was not
   speculative.
4. **`authority_digest` accepted with zero verification** (receipt-consistency,
   CONFIRMED_CRITICAL). `require_authority/2` only checked `is_binary/1` on a
   caller-supplied string - any attacker-suppliable value passed straight through to a
   full `standing: :alive` success receipt.
5. **Bare `is_map/1` guards, `KeyError` crashes instead of typed refusals**
   (receipt-consistency, CONFIRMED_CRITICAL). `apply_transition/5` crashed with
   `** (KeyError) key :transition_id not found` on `%{}` instead of returning
   `{:error, {:refused, ...}}` - proven by live execution of the extracted function
   body, contrasted against the established validating-constructor convention
   (`BeamPM.Types.PolicyDecision.new/1` etc.) used everywhere else in beam4pm the same
   day.
6. **A fourth, incompatible receipt shape** (receipt-consistency, CONFIRMED_CRITICAL).
   The Governor's receipt had no `events` list, no OCEL shape, and crashed
   `BeamPM.Codec.to_map/1`/`encode/1` (`FunctionClauseError` - no clause for a plain
   map) - it could never be mined by `BeamPM.Discovery` the way every other beam4pm
   consequence receipt is.
7. **Receipts never persisted; lost on crash/restart** (receipt-consistency,
   CONFIRMED_MODERATE). The receipt lived only inside `BeamPM.Runtime`'s transient
   GenServer state; the pack's own supervision-restart test proved this by only
   asserting the fresh process's *initial* state, never that any receipt survived.
8. **Vocabulary-only pack invariant broken** (ontology-pollution, CONFIRMED_MODERATE
   x4). Six new instance individuals (`bpm:governed_kernel` + 5 `bpm:TransitionSpec`s)
   were embedded directly in the *vendored pack's own* `ontology.ttl`, contradicting
   that same file's own header ("ships templates and vocabulary only... declares no
   ... individuals of its own") and the pack's README (never updated to acknowledge
   the new classes). 8 of 10 new classes had zero properties, zero SPARQL/gate
   references, and zero admission checks despite the merge's own stated purpose being
   governance rigor - and the `bpm:` namespace's documented meaning (process-mining
   records) was overloaded with an unrelated second meaning (execution-governance
   state machine) sharing only the English word "process."
9. **A third, mutually-incompatible reimplementation existed alongside it**
   (`beam4pm-post-llm-runtime-pack`'s `BeamPM.PostLLM.BRCE`, duplication,
   CONFIRMED_MODERATE) - independently authored within the same ~35-minute window,
   confirming genuinely uncoordinated concurrent construction rather than a
   deliberate layered design.

The one thing worth keeping: **exact-state-hash fencing and a real, currently-passing
Chicago test suite** (receipt-consistency lens's own fairly-noted finding) - the
Governor's rendered code, when actually compiled and run, produced a genuinely
mock-free 6/6 ExUnit pass with real OTP supervision. The problem was never "untested
code"; it was "a second, competing implementation of an already-solved authority
boundary, missing that boundary's own safety properties."

## Why this design does not just restate that intent

Restating "delegate to Actuation" as a comment is not the same as actually removing
every place the original module could still make its own admission/execution/receipt
decision. Concretely, in `BeamPM.ProcessGovernor`:

- **Admission has exactly one source of truth.** `admitted_requires/1` calls
  `BeamPM.Actuation.admitted_actuations/0` directly - it does not carry its own copy
  of the allowlist, so a transition can never be admitted (or refused) by anything
  other than the actuation module's own graph-derived data. If that map changes,
  `BeamPM.ProcessGovernor` changes with it automatically; there is no second file to
  keep in sync.
- **There is no authority token of any kind, verified or not.** `apply_transition/3`
  takes exactly three arguments (`snapshot`, `candidate`, `actuation_opts`) - none of
  them is a caller-supplied "grant." The only gate is (a) an exact-state-hash
  comparison against a hash `plan_transition/2` itself computed, and (b) whether
  `candidate.actuation_name` is a member of `BeamPM.Actuation.admitted_actuations/0`'s
  keys. Nothing resembling `require_authority/2`'s unverified string exists.
- **Every I/O-causing consequence is a single call to `BeamPM.Actuation.run/2`.**
  `grep` for `Port.open`, `GymBridge`, or any gym-protocol string
  (`"op"`/`"reset"`/`"step"`) across `beam4pm_process_governor.ex.eex` returns zero
  hits - the only way this module can touch the real environment is by calling the
  already-qualified reactor.
- **The consequence receipt is not reinvented.** `apply_transition/3`'s embedded
  `actuation` reference is exactly `%{run_id: ..., receipt_path: ..., receipt_schema:
  "beam4pm-brce/v1"}` - copied from what `BeamPM.Actuation.run/2` returned, never
  recomputed from a canonical-hash scheme. `replay/2` re-opens that exact file and
  checks its real `receipt_schema`/`action_name` fields; it does not maintain its own
  parallel hash chain.
- **Fail-closed, no crashes on malformed input.** Every branch of
  `apply_transition/3` (fencing failure, unadmitted actuation name, `BeamPM.Actuation`
  refusal, execution failure, and a defensive catch-all) returns a typed
  `{:error, tag, receipt}` tuple with a real receipt written to disk - there is no
  bare `Map.fetch!`/dot-access path that can raise `KeyError` on a caller-supplied
  candidate the way the original `apply_transition/5` did.
- **The one closed gap the original left open is closed here without duplicating
  anything.** Every `apply_transition/3` call - applied, refused, or
  execution-failed - writes a real `beam4pm-process-governor/v1` receipt to disk
  (`<receipts_dir>/process/<process_id>-t<ordinal>-<run_id>.json`), so a governed
  process's own attempt history survives a crash the way the original's in-memory-only
  receipt did not, without inventing a second hash/identity scheme for the
  UNDERLYING consequence (that identity always stays `BeamPM.Actuation`'s own
  `run_id`/`receipt_path`).
- **The ontology fragment lives in the CONSUMER's graph, not the pack's.**
  `project/ontology-process-governor-fragment.ttl` is written to be appended into
  beam4pm's OWN `ontology.ttl`, mirroring exactly how `bpma:increment_counter_aa`/
  `bpma:observe_counter_aa` are already admitted there (lines 913-922) - it is never
  embedded in the vendored `beam4pm-process-model-pack`'s own `ontology.ttl`. The new
  `bpmg:` vocabulary is two classes and five properties, the minimum needed to express
  "an ordered sequence of transition -> already-admitted-actuation-name mappings";
  every admission/execution/receipt concept is reused from `bpma:`/`BeamPM.Actuation`
  rather than reinvented, closing the ontology-pollution findings without producing a
  fifth vocabulary.

## What is deliberately NOT solved here

- `admitted_requires/1`'s `{:refused, ...}` path from `BeamPM.Actuation.run/2` itself
  is defensively handled but not exercised by any test in this rewrite: because
  `apply_transition/3` always supplies exactly the precondition facts
  `BeamPM.Actuation.admitted_actuations/0` requires for the chosen actuation name, that
  branch cannot currently be reached from `BeamPM.ProcessGovernor`'s own call site. It
  is real, typed, receipted code kept for defensive completeness against
  `BeamPM.Actuation.run/2`'s documented contract, not dead code removed for coverage
  vanity - but it is honestly unverified by this rewrite's own test suite, and should
  be named as such rather than implied to be qualified.
- Per-transition OCEL `event_id`s are not made globally unique across a multi-transition
  process run (each transition's real actuation receipt keeps its own independent
  `event_id`s, scoped to that transition's own `run_id`). This does not corrupt mining
  (event ordering is resolved by real `event_time`, with `event_id` only as a
  tie-break, and the two transitions' `run_id`s already differ lexicographically in a
  way that produces the correct order) but is a known, disclosed limitation rather
  than a claimed global-uniqueness guarantee.
