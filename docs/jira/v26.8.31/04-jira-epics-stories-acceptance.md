# Jira Epics, Stories and Acceptance — v26.8.31

This backlog follows the same discipline as
`docs/jira/v26.8.29/09-jira-epics-stories-acceptance.md`: every story binds exact
subject, acceptance behavior, authority and evidence. Compilation or file existence
alone is not a crown. The highest epic number in the v26.8.29 backlog is
`B4PMP-2600`; this document adds one new epic above that range,
`B4PM-1000`-adjacent per this file's own numbering below reusing the free
`B4PM-10xx`-series slot the v26.8.29 file did not occupy for this concern
(K8s living topology already owns literal `B4PM-1000` in that file, so this
epic is issued as `B4PM-10xx` under a distinct family prefix, `B4PM-17xx`, to
avoid collision — see the story IDs below).

## Evidentiary basis (already real, already committed, not proposed)

A prior session in `~/ggen_igniter` (the base Elixir-native ontology-to-code engine
beam4pm vendors) found that beam4pm's own manufacturing pipeline exercises only one
thin slice of the `igniter` hex library (`~> 0.8`): `mix ggen_igniter.sync`'s EEx
templating over 31 Ash resources, driven by `scripts/igniter_sync.sh`. That session
then wrote 10 new real test files (37 tests, 0 failures, re-run and confirmed for
this document) to `~/ggen_igniter/test/ggen_igniter_base_*_test.exs`, exercising the
base `igniter` library's previously-untested capability surface — driven against
real content read from `~/ex4pm` (a differently-shaped ontology-driven umbrella
project used as the research lab; beam4pm remains the product). The same commit
(`4aa5f36`) also added two further test files not counted in the 10
(`test/ggen_igniter_install_task_test.exs`,
`test/ggen_igniter_upstream_rename_blocker_test.exs`) and a new production mix task,
`lib/mix/tasks/ggen_igniter.install.ex`, which itself calls
`Igniter.Project.Deps.add_dep/2`, `Igniter.Project.Config.configure_new/4`,
`Igniter.Project.Application.add_new_child/3`, and `Igniter.Project.Module`. Before
this session, `lib/ggen_igniter/doctor_fixes.ex` already called
`Igniter.Project.Config.modify_config_code/4` in production source (added in commit
`c591ecb`, 2026-08-28) — `Igniter.Project.*` was not at zero usage prior to this
session, only `Igniter.Refactors.*` was; `Igniter.Code.*` in production source
(never in a test) is otherwise correctly scoped to `doctor_fixes.ex`.
`docs/integrations/igniter/project-actuation.md` in that repo already marked
`Igniter.Project.Module`/`Igniter.Code.*` "NOT USED" in production — that table
predates commit `c591ecb`/`4aa5f36` and is itself now stale for `Igniter.Project.*`
and `Igniter.Code.*` alike, a fact this document notes but does not attempt to fix
in that other repo.

Real test file paths (all pass, `mix test test/ggen_igniter_base_*_test.exs` → `37
tests, 0 failures`):

- `test/ggen_igniter_base_code_function_test.exs` — `Igniter.Code.Function`
  (`move_to_def/2`, `move_to_defp/3`)
- `test/ggen_igniter_base_code_keyword_map_list_tuple_test.exs` —
  `Igniter.Code.Keyword`/`.Map`/`.List`/`.Tuple`
- `test/ggen_igniter_base_code_module_test.exs` — `Igniter.Code.Module`
  (`move_to_defmodule/1,2`, `move_to_module_using/2`, `module?/1`)
- `test/ggen_igniter_base_code_pattern_string_test.exs` — `Igniter.Code.Pattern`
  (ExAST pattern syntax), `Igniter.Code.String`
- `test/ggen_igniter_base_project_deps_mixproject_test.exs` — `Igniter.Project.Deps`,
  `Igniter.Project.MixProject`
- `test/ggen_igniter_base_project_config_application_test.exs` —
  `Igniter.Project.Config`, `Igniter.Project.Application`
- `test/ggen_igniter_base_project_formatter_taskaliases_test.exs` —
  `Igniter.Project.Formatter`, `Igniter.Project.TaskAliases`
- `test/ggen_igniter_base_project_test_test.exs` — `Igniter.Project.Test`
  (`ensure_test_support/1`)
- `test/ggen_igniter_base_refactors_test.exs` — `Igniter.Refactors.Rename`,
  `Igniter.Refactors.Elixir`
- `test/ggen_igniter_base_mix_task_end_user_test.exs` — `mix
  igniter.refactor.rename_function` via a real subprocess CLI invocation

Four real defects in base `igniter` (0.8.3) were found and reproduced during this
work, each with an exact root cause and (where one exists) a working workaround —
these are cited as constraints, not assumptions, throughout the stories below:

1. `Igniter.Project.Deps.add_dep/2,3` raises an uncaught `CaseClauseError` when the
   target `mix.exs` inlines `deps: [...]` directly in `project/0` instead of a
   separate `defp deps do [...] end`. Root cause: `Igniter.Project.Deps.get_dep/2`'s
   `with ... else _ -> nil end` fallback (`deps.ex:261-262`) returns bare `nil`
   instead of `{:ok, nil}`/`{:error, _}` when `Igniter.Code.Function.move_to_defp/3`
   fails to find `deps/0`, and `add_dependency/4`'s `case` (`deps.ex:60`) has no
   clause for bare `nil`. Reproduced against real
   `~/ex4pm/apps/ex4pm_contracts/mix.exs` (which inlines `deps:`).
2. `Igniter.Project.MixProject.update/4`'s own documented example is broken for a
   real two-dot semver: `{:code, quoted}` with a binary `quoted` is parsed as real
   Elixir source via `Sourceror.parse_string!/1` (`mix_project.ex:262-264`), not
   treated as an already-literal value — a bare version string with two dots (e.g.
   `"26.8.28"`) is not valid standalone source text. Verified workaround: wrap in
   `inspect/1` — `{:code, inspect(new_version)}`.
3. `Igniter.Project.Application.add_new_child/2,3` cannot find an insertion point
   when the target `start/2` inlines its child list directly into
   `Supervisor.start_link([], ...)` instead of binding `children = [...]` first. It
   degrades to a real, honest warning (no crash, no silent misapplication) — but
   produces no change if the caller doesn't inspect `igniter.warnings`.
4. `Igniter.Refactors.Rename.rename_function/4` has two real bugs: (a) it crashes
   with `ArgumentError` (`length(nil)`) on any parenless zero-arity function
   definition (`def name do ... end`) — Elixir represents `args` as `nil` for this
   shape, and `update_refs/7`'s `length(args) == arity` guard (`rename.ex:322-326`)
   does not handle `nil`; (b) it silently skips renaming a guarded definition (`def
   name(x) when guard do`) — the function name sits inside a `:when`-wrapper AST
   node the rename pattern does not match — while still correctly renaming internal
   self-call sites, producing a real partial/inconsistent rename with no error
   surfaced.

## beam4pm's real current state (verified for this document, not assumed)

- beam4pm's only use of `ggen_igniter` today is `scripts/igniter_sync.sh`, which
  runs `mix ggen_igniter.sync` (see `~/beam4pm/CLAUDE.md`'s Build/sync/test
  section) — pure EEx templating producing `lib/beam4pm_ash.ex` (31 `Ash.Resource`
  modules), zero use of any `Igniter.Code.*`/`Project.*`/`Refactors.*` codemod.
- `~/beam4pm/mix.exs` pins `{:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime:
  false}`; `mix.lock` resolves it to `26.8.30`. Real current HEAD of
  `~/ggen_igniter` (where the new tests live) is commit `4aa5f36`, `mix.exs` version
  `26.9.2` — beam4pm is two feature releases behind the tested capability surface.
- `~/beam4pm/mix.exs` is a **single-app** project (no `apps/` umbrella subdirectory
  — confirmed by directory listing) with exactly one non-`deps/` `mix.exs` at repo
  root. Its `deps()` are declared as a separate `defp deps do [...] end` function
  (the `mix new`/Phoenix convention), **not** inlined into `project/0` — this is the
  **safe** shape relative to defect #1's trigger (which requires deps to be inlined
  directly in `project/0`). Story B4PM-1701 below still requires this be re-verified
  as a standing gate, since the shape can drift as the file is hand-edited (a
  legitimate manufacturing input per beam4pm's source-authority doctrine).
- `~/beam4pm/mix.exs` declares `version: "0.1.0"`; `~/beam4pm/src/beam4pm.app.src`
  declares `{vsn, "0.1.0"}` — the two-dot-or-fewer version scheme that defect #2's
  `inspect/1` workaround must be exercised against before any automated version-bump
  task touches either file.
- beam4pm's source-authority doctrine (`~/beam4pm/CLAUDE.md`,
  `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`) treats
  `ontology.ttl`, `ggen.toml`, `rebar.config`, `mix.exs`, `src/beam4pm.app.src`, and
  the vendored pack's templates as legitimate hand-editable manufacturing inputs;
  files carrying the `GENERATED by ggen ... Do not edit.` header are never a direct
  editing surface — every story below that touches `mix.exs`, `beam4pm.app.src`, or
  a `bpm:RecordType`-derived file must respect this boundary.

## EPIC B4PM-1700 — Igniter capability-driven manufacturing expansion

### B4PM-1701 Mix.exs defect-trigger-shape audit

Audit every real `mix.exs` file in beam4pm (the single root `mix.exs`; re-run this
audit against any `apps/*/mix.exs` introduced later if the project is ever split
into an umbrella) against the two known `add_dep`/`rename_function` defect trigger
shapes documented above: (a) inlined `deps: [...]` in `project/0` vs. a separate
`defp deps do [...] end`; (b) any parenless zero-arity or guarded `def` inside
`mix.exs` itself that a future `rename_function`-based codemod could target. Emit a
machine-readable report (one row per `mix.exs`, one row per matched/non-matched
trigger shape) and wire it as a standing check (a `mix` task or shell script under
`scripts/`) so drift is caught on future hand-edits, not just this one snapshot.

Acceptance:

- report correctly classifies `~/beam4pm/mix.exs`'s `defp deps do [...] end` as
  **not** matching defect #1's inlined-`project/0` trigger shape, cited against the
  real file content read for this audit;
- report enumerates zero or more parenless-zero-arity/guarded-`def` matches inside
  `mix.exs` with exact line numbers, not a boolean pass/fail;
- the check is re-runnable as a standing script (added under `scripts/`) and is
  exercised by CI or `just verify` so a future hand-edit that reintroduces the
  trigger shape is caught before any `Igniter.Project.Deps` automation is added;
- the audit script itself is proven against a real fixture reproducing defect #1's
  trigger shape (an inlined-`deps:` `mix.exs`, e.g. a copy of
  `~/ex4pm/apps/ex4pm_contracts/mix.exs`'s shape) to confirm it actually detects the
  positive case, not only the negative case beam4pm's own file currently exhibits.

### B4PM-1702 Single-record-patch codemod via Igniter.Code.Module/Function

Add an `Igniter.Code.Module`/`Igniter.Code.Function`-based codemod as an alternative
manufacturing path to full EEx re-render, scoped to exactly one admitted
`bpm:RecordType` chosen from `ontology.ttl`. Given one field addition/rename on that
single record type, the codemod must locate the existing generated module via
`Igniter.Code.Module.move_to_defmodule/2`, locate the target function via
`Igniter.Code.Function.move_to_def/2` (or `move_to_defp/3` for private
constructors), and apply a targeted AST patch — leaving every other generated file
byte-identical to a full `mix ggen_igniter.sync` re-render.

Acceptance:

- the codemod is invoked via a new named script/mix task (not folded into
  `scripts/igniter_sync.sh`'s existing EEx path) scoped to exactly one chosen
  `bpm:RecordType`;
- for that one record type, the codemod's patched output and a full
  `mix ggen_igniter.sync` regeneration from the same updated `ontology.ttl` produce
  byte-identical generated source for the touched module;
- for every other admitted `bpm:RecordType`, the codemod makes zero changes (proven
  by a diff against `bash scripts/gate_m2_check.sh`'s pre-patch baseline);
- the patched file still carries the `GENERATED by ggen ... Do not edit.` header
  (or an equivalent provenance marker naming the codemod path), so source-authority
  classification is not silently broken by the alternative manufacturing path;
- the codemod is exercised by a real ExUnit test asserting on the actual patched
  file content, not on which `Igniter.Code.*` functions were called.

### B4PM-1703 Version-bump automation via inspect/1-wrapped MixProject.update

Implement a version-bump mix task using `Igniter.Project.MixProject.update/4`
against the verified `{:code, inspect(new_version)}` workaround for defect #2 (the
library's own documented `{:code, new_version}` example is broken for beam4pm's real
two-dot semver, `"0.1.0"`/`"26.8.28"`-style strings, because `Sourceror.parse_string!/1`
parses the bare string as source, not a literal). The task must bump both
`~/beam4pm/mix.exs`'s `version:` key and `~/beam4pm/src/beam4pm.app.src`'s `{vsn,
...}` tuple in the same invocation, keeping them in sync per the existing hand-authored
comment convention in `mix.exs` documenting that these two values must match.

Acceptance:

- running the task with a target version (e.g. `"0.1.1"`) updates
  `~/beam4pm/mix.exs`'s `version: "0.1.0"` to `version: "0.1.1"` and
  `~/beam4pm/src/beam4pm.app.src`'s `{vsn, "0.1.0"}` to `{vsn, "0.1.1"}`, verified by
  reading the actual post-run file content, not the task's exit code;
- a version proven to break the library's own undocumented-example path (a
  two-dot-plus string, e.g. `"26.8.28"`) is exercised as the test's chosen target
  version specifically because it reproduces defect #2 if the `inspect/1` wrap is
  omitted;
- a regression test asserts that removing the `inspect/1` wrap (i.e., passing
  `{:code, new_version}` directly) reproduces the documented `Sourceror.parse_string!/1`
  failure against the same fixture, so the workaround's necessity stays falsifiable
  rather than asserted;
- the task refuses (typed refusal, not a silent no-op) if `mix.exs`'s `version:` and
  `beam4pm.app.src`'s `{vsn, ...}` do not already match before the bump is applied.

### B4PM-1704 Pre-flight guard for rename_function-based automation

Write a documented pre-flight check script that inspects the AST of every candidate
target function before any `rename_function`-based automation is permitted to run
against it, refusing execution if the target matches either of the two known-bad
shapes from defect #4: (a) a parenless zero-arity definition (`def name do ... end`,
where Elixir's AST represents `args` as `nil`); (b) a guarded definition (`def
name(x) when guard do ... end`, where the function name sits inside a `:when`-wrapper
node `Igniter.Refactors.Rename`'s pattern does not match). This gate is a prerequisite
for `rename_function`-based automation being marketplace-safe against beam4pm's
generated Erlang/Elixir/Gleam projections — it must run before, not instead of, any
future story that actually wires `rename_function` into beam4pm's manufacturing
pipeline.

Acceptance:

- the script accepts a target module + function name/arity and correctly refuses
  (non-zero exit, typed message naming which of the two shapes matched) against a
  real fixture reproducing shape (a) — a parenless zero-arity `def` — proven by
  actually running the script against that fixture, not by inspecting its source;
- the script correctly refuses against a real fixture reproducing shape (b) — a
  guarded `def` — proven the same way;
- the script permits (zero exit) a real fixture matching neither shape (a normal
  parenthesized, unguarded `def name(x) do ... end`), proven by actually running it;
- the script's refusal for shape (b) is cross-checked against the actual documented
  failure mode — a silent partial rename (internal call sites renamed, the
  definition itself left unrenamed, no error surfaced) — reproduced once via a real
  `mix igniter.refactor.rename_function` subprocess invocation against the same
  guarded-def fixture, matching the evidence method already used in
  `test/ggen_igniter_base_mix_task_end_user_test.exs`;
- the script is wired as a mandatory precondition (not an optional flag) in any
  future mix task or CI step that invokes `rename_function`-based automation against
  beam4pm's own generated source, so a marketplace consumer of this capability
  cannot bypass it by omission.

### B4PM-1705 Ontology-binding trigger for `pro_capability_manifest_sync.sh`

`scripts/pro_capability_manifest_sync.sh` currently full-file-regenerates
`lib/beam4pm_pro_capability_manifest.ex` and its test from two static EEx templates
(`vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_capability_manifest.ex.eex`,
`..._test.exs.eex`) that interpolate none of `admitted_actions.rq`'s SPARQL bindings
into the rendered body, so the regen is byte-identical on every run even though the
underlying `bpma:AdmittedActuation` graph is queried. Implement the ontology-binding
change identified as this script's own reconsideration trigger: make the template
interpolate `admitted_actions.rq`'s `?action_name`/`?gym_op` bindings into
`capabilities/0`, and add a standing check that fails the moment the template stops
being static without a corresponding capability-manifest story update.

Acceptance:

- the manifest audit's finding — "both templates confirmed fully static (no
  ontology-driven bindings substituted into the body, per the template's own comment
  at line 9)" — is cited verbatim as the precondition motivating this story, checked
  against the real template content before any change is made;
- `beam4pm_pro_capability_manifest.ex.eex` is edited to interpolate at least one
  `admitted_actions.rq` binding into `capabilities/0`'s returned list, proven by
  reading the real post-edit rendered `lib/beam4pm_pro_capability_manifest.ex` and
  confirming its content differs from the pre-edit byte-identical baseline;
- a regression fixture adds one new `bpma:AdmittedActuation` individual to
  `ontology.ttl` and asserts the regenerated file's `capabilities/0` reflects it,
  proven by running `mix ggen_igniter.sync` and reading the actual output, not by
  inspecting the template source;
- `scripts/pro_capability_manifest_sync.sh` itself is left unmodified (per the audit's
  own recommendation that the full-file `ggen_igniter.sync` mechanism, not Igniter's
  AST-patch surface, remains correct here) — only the template and ontology fixture
  change.

### B4PM-1706 Ontology-binding trigger for `pro_compatibility_sync.sh`

Same reconsideration trigger as B4PM-1705, applied to
`scripts/pro_compatibility_sync.sh`'s pair of full-file regenerations
(`lib/beam4pm_pro_compatibility.ex`, `test/beam4pm_pro_compatibility_test.exs`),
which the audit found driven by the same `admitted_actions.rq` query against
`ontology.ttl` but marked "GENERATED by ggen_igniter from the beam4pm_pro_compatibility
static template. Do not edit." with no bindings substituted into the body.

Acceptance:

- the audit's finding that both outputs carry the literal header confirming a fully
  static template is cited as this story's precondition, checked against the real
  file content at `lib/beam4pm_pro_compatibility.ex:1` and
  `test/beam4pm_pro_compatibility_test.exs:1` before any change;
- `beam4pm_pro_compatibility.ex.eex` is edited so at least one
  `admitted_actions.rq` binding reaches the rendered module body, proven by reading
  the actual regenerated file and diffing it against the pre-edit static baseline;
- `mix.exs`'s confirmed non-inlined `defp deps do [...] end` shape (cited in the
  audit as making defect #1 inapplicable) is re-checked and still holds after this
  change, since this story does not touch `mix.exs` but must not silently break that
  precondition via an unrelated `ggen sync` side effect;
- `scripts/pro_compatibility_sync.sh` is left unmodified; only the template and any
  ontology fixture addition change.

### B4PM-1707 Ontology-binding trigger for `pro_license_sync.sh`

Same reconsideration trigger as B4PM-1705/1706, applied to
`scripts/pro_license_sync.sh`'s regeneration of `lib/beam4pm_pro_license.ex` and
`test/beam4pm_pro_license_test.exs` from templates both headed "Bindings: NONE
required -- fully static," where the audit noted the pipeline generates brand-new,
self-contained files with zero bindings and explicitly deferred adoption "only if a
future revision makes these templates ontology-bound."

Acceptance:

- the audit's own deferred-adoption clause is cited verbatim as this story's
  precondition — "only if a future revision makes these templates ontology-bound...
  would targeted patching become worth reconsidering" — checked against the real
  template headers before any change;
- `beam4pm_pro_license.ex.eex` is edited to interpolate at least one
  `admitted_actions.rq` binding, proven by reading the real regenerated
  `lib/beam4pm_pro_license.ex` and confirming it differs from the previously
  byte-identical static output;
- the audit's confirmation that no `start/2`/supervision tree exists anywhere the
  script touches (defect #3 moot) and no function rename occurs (defect #4 moot) is
  re-verified against the post-change file, since this story adds new generated
  content that must not introduce either shape without a corresponding pre-flight
  guard per B4PM-1704;
- `scripts/pro_license_sync.sh` is left unmodified; only the template and any
  ontology fixture addition change.

### B4PM-1708 Byte-identity regression guard for `receipt_chain_sync.sh`'s dependent pipeline

`scripts/receipt_chain_sync.sh` chains its own `ggen_igniter.sync` full-file regen of
`lib/beam4pm_receipt_chain.ex` with two nested invocations of
`scripts/actuation_sync.sh` and `scripts/process_governor_sync.sh` (themselves each a
full-file regen gated by `mix compile --warnings-as-errors`/`mix test`), then a final
regen of `test/beam4pm_receipt_chain_test.exs`. The audit found real
`Igniter.Refactors.Rename`-hazard shapes already present in one of the chained
targets — a parenless zero-arity `def contracts, do: @contracts` at
`lib/beam4pm_process_governor.ex:474` and multiple guarded defs (e.g. line 158, line
362) — but confirmed no rename step exists in the current pipeline. Add a standing
regression guard so that if a future story ever wires `Igniter.Refactors.Rename` into
this chained pipeline, it cannot run against `beam4pm_process_governor.ex` without
first passing the B4PM-1704 pre-flight guard.

Acceptance:

- the audit's exact citation — "`lib/beam4pm_process_governor.ex:474` ...
  `def contracts, do: @contracts`" and "line 158 ... `when is_binary(process_id)`" —
  is checked against the real file content and reproduced verbatim as this story's
  precondition;
- a new standing check (script under `scripts/`, wired into `bash scripts/gate_m2_check.sh`
  per that script's own dispatch list) asserts that no `Igniter.Refactors.Rename`
  call exists anywhere in `scripts/receipt_chain_sync.sh`, `scripts/actuation_sync.sh`,
  or `scripts/process_governor_sync.sh` without the B4PM-1704 pre-flight guard script
  also being invoked in the same code path, proven by running the check against the
  real current (guard-free, rename-free) state of all three scripts and confirming a
  pass;
- the check is proven to actually refuse by a fixture that inserts an unguarded
  `Igniter.Refactors.Rename` call into a copy of one of the three scripts without the
  pre-flight guard, run for real and confirmed to fail;
- none of `receipt_chain_sync.sh`, `actuation_sync.sh`, or `process_governor_sync.sh`
  is otherwise modified — this story is guard-only, consistent with the audit's own
  "do not adopt" recommendation for all three scripts' current pipelines.

### B4PM-1709 Ontology-binding trigger for `rf2_conformance_sync.sh`'s deferred `MixProject.update` path

`scripts/rf2_conformance_sync.sh` today performs two full-file `ggen_igniter.sync`
regenerations of `lib/beam4pm_rf2_conformance.ex` and its test, both headed
"GENERATED by ggen_igniter ... Do not edit," driven by `rf2_spec.rq` against
`ontology.ttl`. The audit found the one plausible future fit is
`Igniter.Project.MixProject.update/4`/`Igniter.Project.Deps.add_dep` for
programmatic `mix.exs` dependency management, and confirmed that path is currently
safe against defect #1 because `mix.exs:30-36`'s `defp deps do [...] end` is already
a separate, non-inlined function. Implement that deferred path: a mix task that adds
the `RF2_ORACLE_BIN`-adjacent Rust NIF/port dependency to `mix.exs` programmatically
via `Igniter.Project.Deps.add_dep`, using B4PM-1703's `inspect/1`-wrapped
`MixProject.update` pattern for any accompanying version pin.

Acceptance:

- the audit's exact citation of `mix.exs`'s real `defp deps do [...] end` shape
  (lines 30-36, reproduced verbatim in the audit) is checked against the current
  file content and used as the precondition proving defect #1 will not trigger
  before the new task is written;
- the new mix task, run for real, adds a dependency entry to `mix.exs`'s
  `defp deps do [...] end` block (not inlined into `project/0`), proven by reading
  the actual post-run `mix.exs` content;
- a regression test reproduces defect #1 by pointing the same `Igniter.Project.Deps.add_dep`
  call at a fixture `mix.exs` with `deps: [...]` inlined in `project/0` (the shape
  the audit names as `~/ex4pm/apps/ex4pm_contracts/mix.exs`'s style) and confirms the
  documented crash occurs, so the mitigation stays falsifiable per B4PM-1701's
  methodology;
- `scripts/rf2_conformance_sync.sh`'s two existing `ggen_igniter.sync` full-file
  regen steps are left unmodified — the new mix task is additive, invoked separately,
  not folded into the sync script per the audit's own "Do not adopt Igniter... for
  this script's actual two ggen_igniter.sync steps" finding.

### B4PM-1710 Manufactured-file-marker false-positive guard for `gate_m2_check.sh`

`scripts/gate_m2_check.sh` discovers "manufactured" files to delete-and-regenerate by
a case-insensitive substring match on "GENERATED by ggen" across the first 3 lines of
every file under `SEARCH_DIRS`. The audit flagged this as the script's own
reconsideration trigger: the marker-based `find_manufactured()` sweep (lines 24-38)
has no verification that a matched file's *actual* regeneration source is one of the
13 dispatched `*_sync.sh` scripts it goes on to invoke — a file carrying the marker
text but no corresponding sync script (e.g. a future hand-copied header, or a marker
string appearing inside a comment/docstring rather than a real generated-file
preamble) would be silently deleted with no regeneration path, a data-loss risk the
current pass-4 byte-identity diff only detects after the fact.

Acceptance:

- the audit's own finding — that `gate_m2_check.sh`'s marker discovery
  (`find_manufactured()`, lines 24-38) precedes deletion (`rm -f "$f"` loop, line
  ~92) with no per-file provenance check tying the match to one of the 13 dispatched
  sync scripts — is reproduced against the real script content as this story's
  precondition;
- a new pre-deletion provenance check is added: for every file matched by
  `find_manufactured()`, the check confirms at least one of the 13 dispatched
  `*_sync.sh` scripts' declared `--out` target (per each script's own
  `mix ggen_igniter.sync --out ...` invocation, or `ggen sync run`'s manifest output
  list) covers that exact path, refusing (non-zero exit, named orphan file path) if
  not, proven by running the check against the real current tree and confirming zero
  orphans today;
- the check is proven to actually refuse by a fixture: a file under one of
  `SEARCH_DIRS` carrying the literal "GENERATED by ggen" marker in its first 3 lines
  but with no matching `--out` target in any of the 13 dispatched scripts, run for
  real through the new check and confirmed to fail before any `rm -f` occurs;
- `gate_m2_check.sh`'s existing pass 1-4 structure (marker sweep, sha256, delete,
  regenerate-and-reverify) is otherwise left unmodified — the provenance check is
  inserted between pass 2 and pass 3 (before `rm -f`, not after), consistent with the
  audit's finding that this script's own mix.exs (`defp deps do [...] end`, non-inlined)
  makes defect #1 inapplicable to any future change here.

## Definition of Chicago

The v26.8.29 backlog's Definition of Chicago (`docs/jira/v26.8.29/09-jira-epics-stories-acceptance.md`,
final section) applies unmodified to every story in this document: resolve exact
repo/ref/SHA and admitted subject; manufacture the change through the lawful path;
execute the actual user/customer path, not merely unit internals; permit failure to
become observed evidence; perform RCA at the failed transition; repair the narrow
cause upstream; reexecute exact subject; produce receipt/replay evidence; expand
validation only after the narrow path succeeds; do not crown ALIVE from CI/status
metadata alone.

## See also

- `docs/jira/v26.8.29/09-jira-epics-stories-acceptance.md` — the prior epics/stories
  backlog this document extends; source of the Definition of Chicago reused above.
- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — the source-authority
  doctrine every story touching `mix.exs`/`beam4pm.app.src`/generated files must
  respect.
- `docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md` — the
  capability-coverage table and PR requirements this backlog's stories are scoped against.
- `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` — the full reproduction
  detail for the four defects cited throughout this backlog.
- `docs/jira/v26.8.31/06-script-by-script-capability-audit.md` — the per-script
  candidacy findings (not-applicable/weak-candidate) that B4PM-1705 through
  B4PM-1710 are scoped against.
- `~/beam4pm/CLAUDE.md` — build/sync/test commands and source-authority summary.
