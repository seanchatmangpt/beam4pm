# Known Defects and Mitigations

Last updated: 2026-08-31.

## What this document is

Four real defects in the base `igniter` hex library (pinned at `0.8.3` in
`~/ggen_igniter/mix.lock`, vendored transitively by beam4pm's
`{:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime: false}` dependency
in `mix.exs`) were found and reproduced during a `~/ggen_igniter` testing
session that added 10 new real test files (37 tests, 0 failures) exercising
`igniter`'s previously-untested capability surface. That work is real,
committed, already-passing code in `~/ggen_igniter/test/ggen_igniter_base_*`
as of this session — it is the evidentiary basis for this document, not a
proposal.

Each defect below is stated as an **open defect in igniter 0.8.3 as
observed, with no upstream fix confirmed** — none are claimed fixed, and
none are claimed to have a confirmed upstream fix in flight. Standing labels
follow the vocabulary defined in
`docs/jira/v26.8.29/11-release-gates-receipts.md`:
`UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED | BUILD_BROKEN | UNSUPPORTED |
REFUSED_*`.

## Why this matters for beam4pm specifically

beam4pm's only present use of `ggen_igniter` is `scripts/igniter_sync.sh`,
which runs `mix ggen_igniter.sync` — pure EEx templating over 31 `Ash`
resources, producing `lib/beam4pm_ash.ex`. This path does not call any of
`Igniter.Code.*`, `Igniter.Project.*`, or `Igniter.Refactors.*` — the four
defects below do not affect beam4pm's manufacturing pipeline today. They
become load-bearing the moment beam4pm (or any future `scripts/*_sync.sh`
addition) adopts `Igniter.Project.Deps`, `Igniter.Project.MixProject`,
`Igniter.Project.Application`, or `Igniter.Refactors.Rename` — the exact
capability surface `~/ggen_igniter`'s new tests close the coverage gap on.
`~/ggen_igniter`'s own `docs/integrations/igniter/project-actuation.md`
already marked `Igniter.Project.Module` / `Igniter.Code.*` "NOT USED" in
production before this session; beam4pm's manufacturing pipeline has the
identical gap today.

beam4pm vendors `ggen_igniter` at `26.8.30` (per `mix.lock`); the real
`~/ggen_igniter` HEAD where these defects were reproduced is `26.9.2`
(per `~/ggen_igniter/mix.exs`'s `version:` key) — the defects are in the
`igniter` base library itself (pinned `0.8.3` in both repos' lockfiles), not
in `ggen_igniter`, so this version gap does not affect applicability.

## Defect 1 — `Igniter.Project.Deps.add_dep/2,3` crashes with an uncaught `CaseClauseError`

**Root cause.** `Igniter.Project.Deps.get_dep/2`'s `with ... else` fallback
(`deps.ex:261-262`) returns a bare `nil` instead of `{:ok, nil}` or
`{:error, _}` when `Igniter.Code.Function.move_to_defp(zipper, :deps, 0)`
fails to find a `defp deps do [...] end` function. `add_dependency/4`'s
`case` statement (`deps.ex:60`) has no clause for a bare `nil` result, so
the call raises `CaseClauseError` instead of returning a typed error or
degrading to a warning.

**Trigger condition.** The target `mix.exs` declares its dependency list
inline in `project/0` (`deps: [...]`) rather than via a separate
`defp deps do [...] end` function — the `mix new` / Phoenix convention
`Igniter.Project.Deps` assumes and that `deps.ex:404-410`'s
`move_to_defp(zipper, :deps, 0)` call requires.

**Reproduction evidence.** `~/ggen_igniter/test/ggen_igniter_base_project_deps_mixproject_test.exs`,
describe block `"Igniter.Project.Deps.add_dep/2 (real ex4pm_contracts mix.exs, inline deps convention)"`.
Seeded via `Igniter.Test.test_project(files: %{"mix.exs" =>
Ex4pmFixture.read!("apps/ex4pm_contracts/mix.exs")})` — the real,
unmodified content of `~/ex4pm/apps/ex4pm_contracts/mix.exs`, which inlines
`deps: [...]` directly in `project/0`. The test asserts
`Igniter.Project.Deps.add_dep(igniter, {:jason, "~> 1.4"}, error?: false)`
raises `CaseClauseError` matching `~r/no case clause matching:\s*nil/`.

**Standing.** `BUILD_BROKEN` for the inline-`deps:` shape — the admitted
execution path (`add_dep/2,3` against that real project shape) fails with
an uncaught exception rather than a typed refusal or a degraded warning.

**beam4pm applicability.** `~/beam4pm/mix.exs` was read directly for this
document: it declares `defp deps do [{:ggen_igniter, ...}, {:ash, ...},
{:wasmex, ...}] end` — the separate-function convention `Igniter.Project.Deps`
expects, not the inline shape that triggers this defect. beam4pm is a
single, non-umbrella Mix project (no `apps/` directory), so there is exactly
one `mix.exs` to audit, and as read today it does not trigger this defect.

**Required mitigation.** Before any future `scripts/*_sync.sh` addition
calls `Igniter.Project.Deps.add_dep/2,3` against `~/beam4pm/mix.exs` (or any
new sub-project's `mix.exs`), re-verify that file still uses the
`defp deps do [...] end` convention — a hand-edit that inlines `deps:` back
into `project/0` (a legitimate manufacturing-input edit per this repo's
source-authority doctrine) would silently reintroduce the crash trigger.
Do not call `Igniter.Project.Deps.add_dep/2,3` against any `mix.exs` without
first grepping it for `defp deps do`.

## Defect 2 — `Igniter.Project.MixProject.update/4`'s own documented example is broken for a real two-dot semver

**Root cause.** Passing `{:code, quoted}` with a binary `quoted` value
causes `Sourceror.parse_string!/1` (`mix_project.ex:262-264`) to parse that
binary as literal Elixir *source text*, not to treat it as an
already-literal value. The library's own documented `update/4` example
returns `{:ok, {:code, new_version}}` where `new_version` is a bare version
string (e.g. `"0.1.1"`) — that example itself breaks for any real semver
containing two dots, because `26.8.28` (two `.` characters) is not valid
bare Elixir source when parsed as an expression this way.

**Trigger condition.** Calling `Igniter.Project.MixProject.update/4` with
`{:code, new_version}` where `new_version` is an un-`inspect`ed version
string, exactly as the library's own doc example shows.

**Reproduction evidence.** `~/ggen_igniter/test/ggen_igniter_base_project_deps_mixproject_test.exs`,
describe block `"Igniter.Project.MixProject.update/4 (real ex4pm root mix.exs, path-based codemod)"`.
Seeded with `Ex4pmFixture.mix_exs_source()` (real `~/ex4pm` root `mix.exs`
content, real version string `"26.8.28"`). The verified working form is
`{:ok, {:code, inspect(new_version)}}` — wrapping the string in `inspect/1`
before returning it — which the test uses and which produces the correct
patched `version: "26.8.29",` in the resulting source.

**Standing.** `PARTIAL_ALIVE` — the underlying patch mechanism works when
called correctly (`inspect/1`-wrapped), but the library's own documented
call shape, as documented, does not produce the intended result against a
real two-dot semver; closure is incomplete without the workaround.

**beam4pm applicability.** `~/beam4pm/mix.exs`'s `version: "0.1.0"` is
itself a two-dot semver — the same shape that breaks under the
undocumented, un-`inspect`ed call form. (There is no `CHANGELOG.md` in
this repo; the `26.8.28`/`26.8.29`/`26.8.30`-style two-dot strings visible
elsewhere in this repo are `docs/jira/vNN.N.N/` release-doc directory
names, not the package's own `mix.exs` version, but they share the same
two-dot shape and would trigger the same defect if ever passed through
this call form.)

**Required mitigation.** Any future automation that patches
`~/beam4pm/mix.exs`'s `version:` key via `Igniter.Project.MixProject.update/4`
must return `{:ok, {:code, inspect(new_version)}}`, never
`{:ok, {:code, new_version}}` — following the library's own documented
example verbatim will silently misparse against beam4pm's real version
strings.

## Defect 3 — `Igniter.Project.Application.add_new_child/2,3` cannot find an insertion point when the child list is inlined

**Root cause.** `add_new_child/2,3` requires the target `start/2` to assign
its child list to a `children = [...]` variable before passing it to
`Supervisor.start_link/2`. When the child list is passed inline
(`Supervisor.start_link([], ...)`, no `children =` binding), the codemod
cannot locate an insertion point.

**Trigger condition.** The target OTP `Application` module's `start/2`
calls `Supervisor.start_link` with the child list written directly inline
rather than bound to a `children` variable first.

**Reproduction evidence.** `~/ggen_igniter/test/ggen_igniter_base_project_config_application_test.exs`,
describe block `"Igniter.Project.Application.add_new_child/2,3 (real Ex4pm.Runtime.Application)"`,
test `"produces a real warning against real code with no children = [...] binding"`.
Reproduced against real `Ex4pm.Runtime.Application`-shaped source (inline
`Supervisor.start_link([], ...)`). The call degrades honestly — it does not
crash and does not silently misapply a patch — but produces a real warning
(`Enum.any?(igniter.warnings, &(&1 =~ "Could not find a \`children = [...]\`"))`)
and, critically, **no code change**, with nothing forcing the caller to
inspect `igniter.warnings` before treating the run as successful.

**Standing.** `PARTIAL_ALIVE` — the call completes without crashing and
surfaces a real, correctly-worded warning, but the requested mutation does
not happen; a caller that does not check `igniter.warnings` would observe
what looks like a silent no-op.

**beam4pm applicability.** No beam4pm OTP `Application` module currently
receives any `ggen_igniter`-driven child insertion (the only present use is
EEx templating of Ash resources, not Application-module codemods). This
becomes load-bearing only if a future manufacturing script targets
`Ex4pm.Runtime.Application`-style modules or any equivalent beam4pm
supervisor module for automated child insertion.

**Required mitigation.** Any future beam4pm `Application` module intended
to receive ggen_igniter-driven child insertion must use the
`children = [...]` binding convention in its `start/2`, not an inline child
list. Any caller of `add_new_child/2,3` must check `igniter.warnings` for
this specific message before treating the call as having applied.

## Defect 4 — `Igniter.Refactors.Rename.rename_function/4` has two real bugs

**Root cause (a) — parenless zero-arity crash.** `update_refs/7`'s
`length(args) == arity` guard, matched against
`{:def, _, [{^old_function, _, args}, _body]}` (`rename.ex:322-326`), does
not handle Elixir's own AST representation of a parenless zero-arity
function definition (`def name do ... end`): Elixir represents that form's
`args` as `nil`, not `[]`, and `length(nil)` raises `ArgumentError`.

**Root cause (b) — guarded definitions silently skipped.** A guarded
definition (`def name(x) when guard do ... end`) is represented in Elixir's
AST as `{:def, _, [{:when, _, [{name, _, args}, guard]}, body]}` — the
function name sits one level deeper, inside a `:when`-wrapper node, than
the direct `{^old_function, _, args}` pattern `update_refs/7` matches at
`rename.ex:322`. The definition itself is left completely untouched, while
internal self-call sites referencing the same function name ARE correctly
renamed — a real partial, inconsistent rename with no error surfaced.

**Trigger conditions.** (a) renaming a function declared without
parentheses at zero arity (`def name do`, not `def name() do`); (b)
renaming a function whose definition carries a `when` guard clause
(`def name(x) when guard do`).

**Reproduction evidence.** `~/ggen_igniter/test/ggen_igniter_base_refactors_test.exs`.
Seeded via `Igniter.Test.test_project` with two real, unmodified ex4pm
files that both call the real `Ex4pm.Contracts.verify/0` function —
`~/ex4pm/apps/ex4pm/lib/ex4pm.ex` (real production caller, line 26) and
`~/ex4pm/apps/ex4pm_contracts/test/contracts_test.exs` (real test caller,
line 5) — plus the real `Ex4pm.Contracts` module itself, driving
`Igniter.Refactors.Rename.rename_function/4`. Bug (a) is reproduced against
`Ex4pm.Contracts.verify/0`, declared as idiomatic parenless `def verify do`
in the real module. Bug (b) is reproduced in a second describe block
against `Ex4pm.Contracts.read/1`, whose real definition is
`def read(id) when is_atom(id) do` — the rename succeeds cleanly at the
call site (`verify_required_terms/0`'s `with {:ok, bytes} <- read(id) do`
is correctly rewritten to `fetch(id)`) but the guarded `def read(id) when
is_atom(id) do` definition itself is left unchanged, with no warning or
error raised.

**Standing.** `BUILD_BROKEN` for the parenless-zero-arity case (uncaught
`ArgumentError` crash on real, idiomatic code); `PARTIAL_ALIVE` for the
guarded-definition case (the call completes, but produces a real
inconsistent partial rename with no error surfaced to the caller).

**beam4pm applicability.** No beam4pm manufacturing script currently uses
`Igniter.Refactors.Rename` in any form. This becomes load-bearing only if
`rename_function/4` (or the underlying `Igniter.Refactors.Rename` module)
is adopted as an automated codemod over beam4pm's generated Erlang, Elixir,
or Gleam projections — all four language projections define zero-arity
functions in idiomatic parenless style, and beam4pm's generated Elixir
modules (`lib/*.ex`) are exactly the kind of real, idiomatically-styled code
these two bugs were found against (real ex4pm modules), not the
parenthesized synthetic style the library's own examples always use.

**Required mitigation.** `rename_function/4` is NOT yet safe to use as an
automated codemod over any beam4pm-generated source without a pre-check
step that scans the target definition for (a) parenless zero-arity form and
(b) a `when` guard clause, and refuses or hand-verifies the rename in both
cases rather than trusting the codemod's silent success.

## Summary table

| # | API | Trigger | Standing | beam4pm exposure today |
|---|------|---------|----------|--------------------------|
| 1 | `Igniter.Project.Deps.add_dep/2,3` | inline `deps: [...]` in `project/0` | `BUILD_BROKEN` | none (`mix.exs` uses `defp deps do`) |
| 2 | `Igniter.Project.MixProject.update/4` | un-`inspect`ed two-dot semver in `{:code, ...}` | `PARTIAL_ALIVE` | latent (beam4pm uses two-dot versions) |
| 3 | `Igniter.Project.Application.add_new_child/2,3` | inline child list, no `children =` binding | `PARTIAL_ALIVE` | none (no automated child insertion yet) |
| 4 | `Igniter.Refactors.Rename.rename_function/4` | parenless zero-arity def / guarded def | `BUILD_BROKEN` (a) / `PARTIAL_ALIVE` (b) | none (no rename codemod adopted yet) |

None of these four defects are claimed fixed, patched, or scheduled for an
upstream fix — they are open defects in `igniter 0.8.3` as directly
observed against real ex4pm content, with no upstream fix confirmed as of
this writing.

## See also

- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — the
  source-authority doctrine governing which beam4pm files are legitimate
  hand-editable manufacturing inputs (including `mix.exs`).
- `docs/jira/v26.8.29/11-release-gates-receipts.md` — the standing
  vocabulary (`UNKNOWN` / `PARTIAL_ALIVE` / `ALIVE` / `BLOCKED` /
  `BUILD_BROKEN` / `UNSUPPORTED` / `REFUSED_*`) used throughout this
  document.
- `docs/jira/v26.8.31/01-context-and-motivation.md` (this release's
  companion doc) — the full new test-file inventory these defects were
  found while building.
- `docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md`
  (this release's companion doc) — recommended adoption path for the newly
  test-covered `Igniter.Project.*` / `Igniter.Refactors.*` surface, gated
  on the mitigations above.
- `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — epics/stories
  tracking the mitigations required before adopting this capability
  surface.
