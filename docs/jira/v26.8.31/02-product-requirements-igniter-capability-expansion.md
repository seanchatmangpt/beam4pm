# Product Requirements — Igniter Capability Expansion v26.8.31

## Product objective

beam4pm's only current use of `ggen_igniter` is `scripts/igniter_sync.sh`'s `mix ggen_igniter.sync`
invocations — pure EEx templating over `ontology.ttl`'s admitted `bpm:RecordType`/`bpm:Field`
individuals, producing `lib/beam4pm_ash.ex` (31 `Ash.Resource` modules), a Chicago ExUnit CRUD
suite (`test/beam4pm_ash_test.exs`), and a cross-engine manifest identity probe. That is one thin
slice of the base `igniter` hex library (`~> 0.8`, vendored transitively via `ggen_igniter`
`26.8.30`) that `ggen_igniter` itself depends on: `Igniter.Code.*` (AST-precise patching),
`Igniter.Project.*` (deps/mix-project/config/application/formatter/task-alias codemods), and
`Igniter.Refactors.*` (structural rename) were, before this cycle, either unused in beam4pm or
untested anywhere in `ggen_igniter`.

A separate session in `~/ggen_igniter` (the research lab; beam4pm is the product) closed that gap
for real: 10 new test files, 37 tests, 0 failures, added to `~/ggen_igniter/test/` as
`ggen_igniter_base_*_test.exs`, driven against real content read from `~/ex4pm` (a differently
shaped ontology-driven umbrella project used purely as fixture material). That work also surfaced
four real defects in base `igniter` 0.8.3, each with an exact reproduction and, where one exists, a
verified workaround. This document is the evidentiary record of what beam4pm's manufacturing
pipeline should now adopt from that closed capability gap, and under what constraints. It does not
propose new research; the underlying capability tests already exist and pass. What is proposed here
is beam4pm-side adoption — new capability lanes in `scripts/igniter_sync.sh` and its siblings.

## Evidentiary basis

Before this cycle, only `~/ggen_igniter/lib/ggen_igniter/doctor_fixes.ex` touched any
`Igniter.Code.*` module, and only in production source — never under test. `Igniter.Project.*` and
`Igniter.Refactors.*` had zero usage anywhere in `~/ggen_igniter`, lib or test.
`~/ggen_igniter/docs/integrations/igniter/project-actuation.md` carried a table marking
`Igniter.Project.Module`/`Igniter.Code.*` as "NOT USED" in production before this session; the new
tests close exactly that gap, at the `ggen_igniter` layer. beam4pm's own manufacturing pipeline still
has the matching gap one layer up: `scripts/igniter_sync.sh` uses only `mix ggen_igniter.sync`'s EEx
templating path and none of the codemod surface below.

Real test files, `~/ggen_igniter/test/`:

| Test file | Capability exercised |
|---|---|
| `ggen_igniter_base_code_module_test.exs` | `Igniter.Code.Module` (`move_to_defmodule/1,2`, `move_to_module_using/2`, `module?/1`) |
| `ggen_igniter_base_code_function_test.exs` | `Igniter.Code.Function` (`move_to_def/2`, `move_to_defp/3`) |
| `ggen_igniter_base_code_keyword_map_list_tuple_test.exs` | `Igniter.Code.Keyword`/`.Map`/`.List`/`.Tuple` |
| `ggen_igniter_base_code_pattern_string_test.exs` | `Igniter.Code.Pattern` (ExAST pattern syntax), `Igniter.Code.String` |
| `ggen_igniter_base_project_deps_mixproject_test.exs` | `Igniter.Project.Deps`, `Igniter.Project.MixProject` |
| `ggen_igniter_base_project_config_application_test.exs` | `Igniter.Project.Config`, `Igniter.Project.Application` |
| `ggen_igniter_base_project_formatter_taskaliases_test.exs` | `Igniter.Project.Formatter`, `Igniter.Project.TaskAliases` |
| `ggen_igniter_base_project_test_test.exs` | `Igniter.Project.Test` (`ensure_test_support/1`) |
| `ggen_igniter_base_refactors_test.exs` | `Igniter.Refactors.Rename`, `Igniter.Refactors.Elixir` |
| `ggen_igniter_base_mix_task_end_user_test.exs` | `mix igniter.refactor.rename_function` via real subprocess CLI |

Real beam4pm current state, verified this cycle by reading `~/beam4pm/mix.exs` and
`~/beam4pm/scripts/igniter_sync.sh` directly:

- beam4pm's root `mix.exs` uses `defp deps do [...] end` — the separate-function convention,
  **not** the inline-`deps:`-in-`project/0` shape that triggers defect #1 below. This must be
  re-verified (not assumed) before any future sub-app is added, since the trigger is per-file.
- beam4pm has no `Application` module with a `start/2` callback (its `mix.exs` `application/0`
  only declares `extra_applications: [:logger]`, no supervision tree) — defect #3's `children =
  [...]` binding requirement therefore does not yet apply to any real beam4pm file; it becomes
  live the day beam4pm gains a supervision tree.
- `mix.lock` pins `ggen_igniter` at `26.8.30`; real HEAD in `~/ggen_igniter` (where the new tests
  live) is `26.9.2`, confirmed by `git log -1` in that repo (`4aa5f36`, 2026-08-31) and the
  `version:` key in its `mix.exs`.
- beam4pm's source-authority doctrine (`~/beam4pm/CLAUDE.md`,
  `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`) treats `ontology.ttl`,
  `ggen.toml`, `rebar.config`, `mix.exs`, `src/beam4pm.app.src`, the vendored pack's templates, and
  the shell/Elixir sync scripts under `scripts/` as legitimate hand-editable manufacturing inputs.
  All PR items below target that same input surface — never a `GENERATED by ggen ... Do not
  edit.` file.

## Known base-`igniter` 0.8.3 defects (constraints, not assumptions)

Each defect below is cited by its PR item as a required pre-check or workaround, not restated as
folklore.

1. **`Igniter.Project.Deps.add_dep/2,3` crashes with an uncaught `CaseClauseError`** when the
   target `mix.exs` inlines `deps: [...]` directly in `project/0` instead of a separate `defp deps
   do [...] end`. Root cause: `Igniter.Project.Deps.get_dep/2`'s `with ... else _ -> nil end`
   fallback (`deps.ex:261-262`) returns bare `nil` instead of `{:ok, nil}`/`{:error, _}` when
   `Igniter.Code.Function.move_to_defp(zipper, :deps, 0)` fails, and `add_dependency/4`'s `case`
   (`deps.ex:60`) has no clause for bare `nil`. Reproduced against real
   `~/ex4pm/apps/ex4pm_contracts/mix.exs` (which inlines `deps:`).
2. **`Igniter.Project.MixProject.update/4`'s own documented example is broken for a real two-dot
   semver.** `{:code, quoted}` with a binary `quoted` is parsed as real Elixir source via
   `Sourceror.parse_string!/1` (`mix_project.ex:262-264`), not treated as an already-literal value.
   The library's own doc example passes a bare version string as `{:code, new_version}`, which
   breaks for any real semver with two dots as plain source text (e.g. `"26.8.28"`) — the exact
   style beam4pm's own version scheme uses. Verified workaround: wrap in `inspect/1` — `{:code,
   inspect(new_version)}`.
3. **`Igniter.Project.Application.add_new_child/2,3` cannot find an insertion point** when the
   target `start/2` inlines its child list directly into `Supervisor.start_link([], ...)` instead
   of binding `children = [...]` first. Degrades honestly (no crash, no silent misapplication) but
   produces no change if the caller doesn't check `igniter.warnings`.
4. **`Igniter.Refactors.Rename.rename_function/4` has two real bugs**: (a) crashes with
   `ArgumentError` (`length(nil)`) on any parenless zero-arity function definition (`def name do
   ... end`, not `def name() do`) — Elixir represents this as `args = nil`, and
   `update_refs/7`'s `length(args) == arity` guard (`rename.ex:322-326`) doesn't handle it; (b)
   silently skips renaming a guarded definition (`def name(x) when guard do`) — the function name
   sits inside a `:when`-wrapper AST node the rename pattern doesn't match — while still correctly
   renaming internal self-call sites, producing a real partial/inconsistent rename with no error
   surfaced.

## Igniter codemod adoption requirements

### PR-300 — Igniter.Code.Module/Function targeted patching for admitted record types

- `scripts/igniter_sync.sh` gains an opt-in patch mode that uses `Igniter.Code.Module` (
  `move_to_defmodule/2`) plus `Igniter.Code.Function` (`move_to_def/2`) to locate and replace a
  single admitted record type's `new_<type>/1` constructor clause inside the already-manufactured
  `lib/beam4pm_ash.ex`, instead of re-rendering the full file via `beam4pm_ash.ex.eex`.
- Scope: single-record-type patch only. A full-ontology change (new/removed record type, field-set
  change spanning types) still goes through the existing full-file `mix ggen_igniter.sync`
  EEx path — this PR item narrows only the single-record-type edit case.
- The patch path must produce output byte-identical to what a full `mix ggen_igniter.sync`
  regeneration would produce for that one constructor, proving the targeted patch is a pure
  refinement of the existing pipeline, not a divergent code path.

Acceptance: a new `scripts/igniter_patch_record.sh <record_type>` script exists; running it against
one admitted `bpm:RecordType` (e.g. `ocel_event`) followed by `git diff lib/beam4pm_ash.ex` shows
changes scoped to that one `new_ocel_event/1` function clause; a full `bash scripts/igniter_sync.sh`
re-run immediately after produces zero further diff (`git diff --exit-code lib/beam4pm_ash.ex`).

### PR-301 — Igniter.Project.Deps version pin/patch for vendored ggen_igniter

- `scripts/igniter_sync.sh` (or a new `scripts/igniter_deps_bump.sh`) gains a step that uses
  `Igniter.Project.Deps.add_dep/3` (or `update_dep`) to bump beam4pm's vendored `{:ggen_igniter,
  "~> 26.8", ...}` pin in `mix.exs` when a new `ggen_igniter` release is admitted.
- MUST run a pre-check confirming `~/beam4pm/mix.exs` still defines deps via `defp deps do [...]
  end` (the separate-function convention) before invoking `Igniter.Project.Deps.add_dep/2,3` —
  per defect #1, `add_dep` crashes with an uncaught `CaseClauseError` on the inline-`deps:`-in-
  `project/0` shape. The pre-check must fail closed (abort with a non-zero exit and a named error)
  rather than attempt the patch against an unverified mix.exs shape.
- This PR item does not itself change beam4pm's real pinned version (`26.8.30`); it establishes the
  automation and its guard rail for the next version bump.

Acceptance: `scripts/igniter_deps_bump.sh --check-only` run against the real
`~/beam4pm/mix.exs` prints a pass (`defp deps do` convention confirmed) and exits 0; a deliberately
mutated local copy of `mix.exs` with `deps:` inlined into `project/0` causes the same
`--check-only` invocation to exit non-zero with an explicit "inline deps: convention detected,
refusing add_dep (see defect #1)" message, without ever invoking `Igniter.Project.Deps.add_dep/2,3`.

### PR-302 — Igniter.Project.MixProject version-bump automation

- A new `scripts/igniter_version_bump.sh <new_version>` uses `Igniter.Project.MixProject.update/4`
  to rewrite the `version:` key in `~/beam4pm/mix.exs` in lockstep with a corresponding
  `src/beam4pm.app.src` `vsn` update, replacing today's implicit manual-edit convention.
- MUST call `Igniter.Project.MixProject.update/4` with `{:code, inspect(new_version)}`, never `
  {:code, new_version}` directly — per defect #2, passing the bare version string is parsed as
  real Elixir source via `Sourceror.parse_string!/1` and breaks on any real two-dot semver (exactly
  beam4pm's own version scheme, e.g. `"26.8.28"`).
- The script must refuse to run if the resulting `mix.exs` fails `mix compile
  --warnings-as-errors` after the patch, rolling back the write.

Acceptance: `bash scripts/igniter_version_bump.sh 26.8.32` run against a scratch clone of
`~/beam4pm` produces a `mix.exs` whose `version:` line reads `version: "26.8.32"` (confirmed via
`grep '  version:' mix.exs`), and `mix compile --warnings-as-errors` exits 0 immediately after.

### PR-303 — Igniter.Project.Config/Application future supervision-tree codegen

- Reserve `Igniter.Project.Config` / `Igniter.Project.Application` as the mechanism for future
  config-key and supervision-tree child insertion once beam4pm gains a real `Application` module
  with a `start/2` callback (it has none today — `~/beam4pm/mix.exs`'s `application/0` only
  declares `extra_applications: [:logger]`).
- This PR item is UNSUPPORTED today by design, not deferred by oversight: there is no real
  `start/2` target to patch yet. It becomes actionable the day a supervision tree is introduced.
- MUST require, as a precondition on the future implementing PR, that any generated
  `Application.start/2` bind its child list via `children = [...]` before calling
  `Supervisor.start_link(children, ...)` — per defect #3, `Igniter.Project.Application.
  add_new_child/2,3` cannot find an insertion point (degrades to a silent-if-unchecked warning,
  not a crash) when the child list is inlined directly into the `Supervisor.start_link` call.

Acceptance: this requirement stays UNSUPPORTED (no automation to run) until a future PR introduces
`lib/beam4pm/application.ex`; at that point, the acceptance check is that the new file's `start/2`
contains a `children = [` binding (verified by `grep -n "children = \[" lib/beam4pm/application.ex`)
before any `Igniter.Project.Application.add_new_child/2,3` call is added to the manufacturing
scripts.

### PR-304 — Igniter.Project.Formatter/TaskAliases auto-registration

- `scripts/igniter_sync.sh` gains a step, after the three existing `mix ggen_igniter.sync` calls,
  that uses `Igniter.Project.Formatter.import_dep/2` (or equivalent) and
  `Igniter.Project.TaskAliases.add_alias/3` to auto-register any newly manufactured output
  directory (e.g. a future `gleam/src/beam4pm/generated/` subtree, or a new `scripts/*_sync.sh`
  family) into `.formatter.exs` inputs and `mix.exs` `aliases/0`, replacing today's implicit
  manual-edit convention for those two files.
- Idempotent: running the step twice against an already-registered directory produces zero further
  diff.

Acceptance: after adding a new dummy output path (e.g. `tmp_probe_gen/`) to the sync step's known
outputs list and re-running `scripts/igniter_sync.sh`, `git diff .formatter.exs` shows the new path
added to `inputs:`; running the same sync a second time produces `git diff --exit-code
.formatter.exs` (no further change).

### PR-305 — Igniter.Refactors.Rename — NOT YET SAFE for automated use

- `Igniter.Refactors.Rename.rename_function/4` is explicitly marked **NOT YET SAFE** for
  unattended use inside beam4pm's manufacturing scripts, and no PR item in this document or any
  future beam4pm automation may invoke it without first passing the pre-check below.
- Per defect #4: (a) it crashes with `ArgumentError` (`length(nil)`) on any parenless zero-arity
  function definition (`def name do ... end`); (b) it silently skips renaming a guarded definition
  (`def name(x) when guard do ... end`) while still renaming internal self-call sites, producing a
  partial, inconsistent rename with no error surfaced.
- Any future PR item that proposes using `rename_function/4` as an automated codemod over beam4pm's
  generated Erlang/Elixir/Gleam projections MUST first run a static pre-check over the target
  file(s) for both patterns (parenless zero-arity `def`, and guarded `def ... when ...`) and refuse
  to proceed if either pattern is present in the rename's blast radius.

Acceptance: a `scripts/igniter_rename_precheck.sh <file> <function_name>` exists and, run against a
scratch fixture file containing both a parenless zero-arity `def foo do ... end` and a guarded `def
bar(x) when is_integer(x) do ... end`, exits non-zero and names both matched patterns by line
number; run against a fixture containing neither pattern, it exits 0. No other script in this
repository invokes `Igniter.Refactors.Rename.rename_function/4` directly.

### PR-306 — Igniter.Project.Deps guard rail for pro_capability_manifest_sync.sh's static template regen

- `scripts/pro_capability_manifest_sync.sh` currently does two full-file `mix ggen_igniter.sync`
  regenerations of `lib/beam4pm_pro_capability_manifest.ex` and
  `test/beam4pm_pro_capability_manifest_test.exs` from static (zero-binding) EEx templates on every
  run, producing byte-identical output each time — the audit found no existing per-run delta to
  justify AST-patch machinery today.
- Reserve `Igniter.Project.Deps.add_dep/2,3` as the mechanism for the one plausible future
  extension of this script: adding a new dependency declaration to `mix.exs` if
  `beam4pm_pro_capability_manifest.ex.eex` ever grows a real external collaborator. MUST run the
  same `defp deps do [...] end` pre-check as PR-301 before any such call — per defect #1,
  `add_dep` crashes with an uncaught `CaseClauseError` on the inline-`deps:`-in-`project/0` shape.
- This PR item is UNSUPPORTED today by design: the templates are confirmed fully static (per
  `beam4pm_pro_capability_manifest.ex.eex` line 9, "Bindings: NONE required — fully static") with
  no ontology-driven bindings substituted into the body, so there is no real dependency-add trigger
  yet. It becomes actionable the day a template revision makes these templates ontology-bound.

Acceptance: this requirement stays UNSUPPORTED (no automation to run) until a future revision adds a
real dependency to `beam4pm_pro_capability_manifest.ex.eex`; at that point, the acceptance check is
the same `--check-only` pre-check pattern as PR-301's Acceptance line, run against
`~/beam4pm/mix.exs` before any `Igniter.Project.Deps.add_dep/2,3` call is added to
`scripts/pro_capability_manifest_sync.sh`.

### PR-307 — Igniter.Project.Deps guard rail for pro_compatibility_sync.sh's ontology-driven regen

- `scripts/pro_compatibility_sync.sh` runs two full-file `mix ggen_igniter.sync` regenerations
  (`lib/beam4pm_pro_compatibility.ex`, `test/beam4pm_pro_compatibility_test.exs`) driven by
  `admitted_actions.rq` against `ontology.ttl`, both outputs stamped "GENERATED by ggen_igniter ...
  Do not edit." — a full-ontology-authoritative regen, not a targeted AST patch scenario.
- Reserve `Igniter.Project.Deps.add_dep/2,3` as the mechanism for adding a `mix.exs` dependency
  entry the day `beam4pm_pro_compatibility.ex.eex`'s admitted-actions binding set grows to require
  one. MUST run the `defp deps do [...] end` pre-check (per PR-301, defect #1) before any such
  call; the audit confirmed `~/beam4pm/mix.exs` deps() is already the safe separate-function
  convention (mix.exs:35-41), so the pre-check would pass today if exercised.
- This PR item is UNSUPPORTED today by design: no dependency-add trigger exists in the current
  `admitted_actions.rq` binding set for this template.

Acceptance: this requirement stays UNSUPPORTED (no automation to run) until a future ontology change
requires a new `mix.exs` dependency for `beam4pm_pro_compatibility.ex.eex`'s output; at that point,
the acceptance check is `scripts/igniter_deps_bump.sh --check-only` (per PR-301) run against
`~/beam4pm/mix.exs` before any `Igniter.Project.Deps.add_dep/2,3` call is added to
`scripts/pro_compatibility_sync.sh`.

### PR-308 — Igniter.Project.Deps guard rail for pro_license_sync.sh's brand-new-module regen

- `scripts/pro_license_sync.sh` regenerates `lib/beam4pm_pro_license.ex` and
  `test/beam4pm_pro_license_test.exs` wholesale from fully static templates
  (`beam4pm_pro_license.ex.eex`, `beam4pm_pro_license_test.exs.eex`, both declaring "Bindings: NONE
  required -- fully static") — brand-new self-contained modules with no pre-existing hand-authored
  AST for `Igniter.Code.*` to patch.
- Reserve `Igniter.Project.Deps.add_dep/2,3` as the mechanism for adding a `mix.exs` dependency the
  day `beam4pm_pro_license.ex.eex` grows a real external collaborator (e.g. a license-verification
  library). MUST run the same `defp deps do [...] end` pre-check as PR-301/PR-306/PR-307 before any
  such call — per defect #1.
- This PR item is UNSUPPORTED today by design: both templates are confirmed fully static with zero
  ontology bindings, so there is no real dependency-add trigger yet.

Acceptance: this requirement stays UNSUPPORTED (no automation to run) until a future revision adds a
real external dependency to `beam4pm_pro_license.ex.eex`; at that point, the acceptance check is the
same `--check-only` pre-check pattern as PR-301's Acceptance line, run against `~/beam4pm/mix.exs`
before any `Igniter.Project.Deps.add_dep/2,3` call is added to `scripts/pro_license_sync.sh`.

### PR-309 — Igniter.Refactors.Rename pre-check reuse for receipt_chain_sync.sh's generated targets

- `scripts/receipt_chain_sync.sh` orchestrates full-file regeneration of
  `lib/beam4pm_receipt_chain.ex` plus (by shelling to `actuation_sync.sh` and
  `process_governor_sync.sh`) `lib/beam4pm_actuation.ex` and `lib/beam4pm_process_governor.ex` — no
  rename step exists in its pipeline today, but the audit found `lib/beam4pm_process_governor.ex`
  already contains a real parenless zero-arity def (`def contracts, do: @contracts`, line 474) and
  multiple guarded defs (e.g. `def initial_snapshot(process_id, _opts \\ []) when is_binary(...)`,
  line 158) — exactly the two shapes defect #4 (`Igniter.Refactors.Rename.rename_function/4`)
  crashes on or silently mis-renames.
- Any future PR item that adds a `Igniter.Refactors.Rename.rename_function/4` pass over
  `beam4pm_process_governor.ex` (or any file `receipt_chain_sync.sh` transitively regenerates) MUST
  reuse the same `scripts/igniter_rename_precheck.sh` gate defined in PR-305, and MUST special-case
  the confirmed-present parenless `contracts/0` and the confirmed-present guarded defs before
  proceeding.
- This PR item is UNSUPPORTED today by design: no rename step exists anywhere in
  `receipt_chain_sync.sh`'s current pipeline, so there is nothing to gate yet — this item exists to
  record, ahead of need, that PR-305's precheck already covers this file's real hazard shapes.

Acceptance: `bash scripts/igniter_rename_precheck.sh lib/beam4pm_process_governor.ex contracts`
(reusing PR-305's script against this real file) exits non-zero and names the parenless `contracts/0`
definition at its real line number, without requiring any new precheck script; this requirement stays
UNSUPPORTED for actual rename automation until a future PR proposes a real
`Igniter.Refactors.Rename.rename_function/4` call over one of `receipt_chain_sync.sh`'s generated
targets.

### PR-310 — Igniter.Project.Deps guard rail for rf2_conformance_sync.sh's ontology-driven regen

- `scripts/rf2_conformance_sync.sh` runs `cargo build --release` for the RF2 Rust oracle, then two
  full-file `mix ggen_igniter.sync` regenerations (`lib/beam4pm_rf2_conformance.ex`,
  `test/beam4pm_rf2_conformance_test.exs`) driven by `rf2_spec.rq` against `ontology.ttl`, both
  outputs stamped "GENERATED by ggen_igniter ... Do not edit." — full-file, ontology-authoritative
  regen, not a targeted-patch scenario.
- Reserve `Igniter.Project.Deps.add_dep/2,3` as the mechanism for adding a `mix.exs` dependency
  entry if this script is ever extended to add deps to `mix.exs` programmatically (e.g. a new Rust
  NIF bridge crate wrapper). MUST run the `defp deps do [...] end` pre-check (per PR-301, defect
  #1) before any such call; the audit confirmed `~/beam4pm/mix.exs` deps() is the separate-function
  convention (mix.exs:30-36: `{:ggen_igniter, "~> 26.8", ...}`, `{:ash, "~> 3.0"}`,
  `{:wasmex, "~> 0.15"}`), so the pre-check would pass today if exercised.
- This PR item is UNSUPPORTED today by design: `rf2_conformance_sync.sh` never touches `mix.exs`
  today, so there is no real dependency-add trigger yet.

Acceptance: this requirement stays UNSUPPORTED (no automation to run) until a future revision adds a
`mix.exs`-editing step to `rf2_conformance_sync.sh`; at that point, the acceptance check is
`scripts/igniter_deps_bump.sh --check-only` (per PR-301) run against `~/beam4pm/mix.exs` before any
`Igniter.Project.Deps.add_dep/2,3` call is added to `scripts/rf2_conformance_sync.sh`.

### PR-311 — Igniter.Project.Deps guard rail preserved for gate_m2_check.sh's manufactured-file gate

- `scripts/gate_m2_check.sh` discovers every "GENERATED by ggen"-marked file across
  `SEARCH_DIRS=(src lib test gleam/src gleam/test schema docs/reference)`, sha256s them, deletes
  them, regenerates via `ggen sync run` plus 13 `bash scripts/*_sync.sh` invocations (including
  `igniter_sync.sh`, `receipt_chain_sync.sh`, the three `rf{1,2,3}_*_sync.sh` scripts, the two
  `revenue_*_sync.sh` scripts, `claude_workflow_reactor_sync.sh`, and five `pro_*_sync.sh` scripts),
  then re-sha256s and diffs for byte-identity — the gate script itself never edits `mix.exs`,
  config, or performs a rename.
- Reserve `Igniter.Project.Deps.add_dep/2,3` as the mechanism only inside whichever downstream
  `*_sync.sh` script it is later added to (per PR-301/306/307/308/310), never inside
  `gate_m2_check.sh` itself, which orchestrates but does not itself patch `mix.exs`. MUST require
  the same `defp deps do [...] end` pre-check as PR-301 at whichever downstream script gains the
  call — the audit confirmed `~/beam4pm/mix.exs` deps() is already the safe separate-function
  convention (`defp deps do [...] end`, mix.exs:~29-33), so the pre-check would pass today if
  exercised on the real file, but this fact is orthogonal to `gate_m2_check.sh` itself since it
  never touches `mix.exs`.
- This PR item is UNSUPPORTED today by design: `gate_m2_check.sh` has no mix.exs/config/rename step
  of its own to gate.

Acceptance: this requirement stays UNSUPPORTED (no automation to run) for `gate_m2_check.sh` itself;
it is satisfied by each downstream `*_sync.sh` script's own PR-301-style `--check-only` pre-check
(PR-306/307/308/310 above) running clean before `gate_m2_check.sh`'s regeneration pass invokes that
script, with no separate check needed inside `gate_m2_check.sh`.

## Standing and acceptance

Standing vocabulary follows `docs/jira/v26.8.29/02-product-requirements.md`'s "Standing and
acceptance" section unchanged: `UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`, `BUILD_BROKEN`,
`UNSUPPORTED`, typed `REFUSED_*`. As of this document's authorship, PR-300 through PR-311 are all
`UNKNOWN` from beam4pm's side (no implementing commit yet exists in `~/beam4pm/scripts/`) — the
underlying capability evidence they depend on (the 37 passing tests in `~/ggen_igniter/test/
ggen_igniter_base_*_test.exs`) is `ALIVE` at the `ggen_igniter` layer only, and does not transfer
standing to beam4pm's own scripts until each PR item's own Acceptance line is executed against real
beam4pm files.

## See also

- `docs/jira/v26.8.29/02-product-requirements.md` — the PR-001..PR-007 / PI-*/ENT-*/REV-* baseline
  this document's PR-3xx block extends without renumbering.
- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — the source-authority doctrine
  (generated vs. hand-editable manufacturing input) every PR item above stays inside.
- `docs/jira/v26.8.31/01-context-and-motivation.md` — companion evidentiary writeup (same cycle)
  of the `~/ggen_igniter` testing session this document draws its capability inventory and defect
  list from.
- `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` — companion defect writeup (same cycle)
  detailing the four base-`igniter` 0.8.3 defects this document's PR items cite as pre-checks and
  workarounds.
- `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the EPIC B4PM-1700 / story B4PM-1701..1704
  breakdown of this document's PR-300..PR-305 items.
- `docs/jira/v26.8.31/05-verification-and-gates.md` — the release-gate definitions for this
  document's Acceptance lines.
- `docs/jira/v26.8.31/06-script-by-script-capability-audit.md` — the per-script Igniter-candidacy
  audit (all `scripts/*.sh`/`*.exs` manufacturing and dogfood scripts) this document's PR-306
  through PR-311 items are drawn from.
