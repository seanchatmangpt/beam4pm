# Verification and Gates — v26.8.31 Igniter Capability Expansion

## Purpose

Define one release gate per PR item in
`docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md` (already
committed in this repository as of this document — PR-300 through PR-305), so that
beam4pm's adoption of the wider `igniter`/`ggen_igniter` capability surface is tracked with
the same evidence discipline as `docs/jira/v26.8.29/11-release-gates-receipts.md` — never
confusing a passing test in the research lab (`~/ggen_igniter`) with an executed gate in the
product (`~/beam4pm`).

## Standing vocabulary (reused verbatim from v26.8.29 §"Standing vocabulary")

- `UNKNOWN` — evidence is insufficient.
- `PARTIAL_ALIVE` — some required execution is observed but closure is incomplete.
- `ALIVE` — exact admitted subject executed successfully against the stated acceptance boundary.
- `BLOCKED` — required external authority/capability is unavailable.
- `BUILD_BROKEN` — the admitted build/execution path fails.
- `UNSUPPORTED` — the capability is intentionally not provided.
- `REFUSED_*` — admission/authority explicitly rejects an operation.

`UNKNOWN != ADMITTED`. `UNSUPPORTED != REFUSED`. A checkpoint is not a crown.

## Evidence dimensions (reused verbatim from v26.8.29 §"Evidence dimensions")

Receipts for every gate below must preserve, where relevant: observed; admitted; executed;
changed; verified; inferred; refused; blocked; unsupported. Inspection is not execution. A
generated file is not a runtime proof. A passing test in `~/ggen_igniter` is not a passing
gate in `~/beam4pm` — it proves the underlying capability exists, not that beam4pm has
adopted it.

## What is already real evidence, and what is not

The only already-executed evidence this v26.8.31 document set may cite is:

- 37 passing tests, 0 failures, across 10 new real test files under
  `~/ggen_igniter/test/ggen_igniter_base_*_test.exs` (enumerated in
  `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` and
  `docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md`). These prove
  the base `igniter` (`~> 0.8`) capability surface — moved-to
  navigation, keyword/map/list/tuple codemods, module detection, pattern/string matching,
  deps/mix-project mutation, config/application mutation, formatter/task-alias mutation,
  test-support scaffolding, function/module renaming, and the end-user `mix
  igniter.refactor.rename_function` CLI path — is real and exercised against real content
  read from `~/ex4pm`.

This proves the **capability** works in the research lab. It proves nothing about beam4pm,
because beam4pm has not yet run any of these Igniter modules against its own tree. Every
gate below starts at `UNKNOWN` for that reason, not `PARTIAL_ALIVE` and not `ALIVE`, until
the exact command is actually executed against `~/beam4pm` and its output collected as a
receipt.

## Real current state this document set is scoped against

- beam4pm's only current use of ggen_igniter is `scripts/igniter_sync.sh`, which invokes
  `mix ggen_igniter.sync` three times (Ash-resource EEx templating into
  `lib/beam4pm_ash.ex`, the Chicago ExUnit CRUD suite into `test/beam4pm_ash_test.exs`, and
  a cross-engine manifest identity probe) — pure templating, zero use of any
  `Igniter.Code.*`, `Igniter.Project.*`, or `Igniter.Refactors.*` codemod.
- beam4pm vendors `ggen_igniter` at `26.8.30` (`mix.lock`); the real HEAD in `~/ggen_igniter`
  (where the 37 new tests live) is `26.9.2` (`~/ggen_igniter/mix.exs`).
- Root `~/beam4pm/mix.exs` binds dependencies via `defp deps do [...] end` (a separate
  private function), not inlined `deps: [...]` inside `project/0` — this is the
  `mix new`/Phoenix convention that does **not** trigger the
  `Igniter.Project.Deps.add_dep/2,3` `CaseClauseError` documented in
  `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` (defect #1). Any future
  `beam4pm_pro` sub-app or additional umbrella app must be checked against this same
  convention before `Igniter.Project.Deps` automation is added for it — this gate document
  does not assert every future mix.exs in this repo will keep the safe shape, only that the
  one root `mix.exs` read for this document does.
- Root `~/beam4pm/mix.exs` pins `version: "0.1.0"` — a single-dot version, not the two-dot
  `26.8.28`-style scheme the brief flags as the `Igniter.Project.MixProject.update/4`
  defect #2 trigger shape. That defect remains a live constraint for any future
  `MixProject.update/4` automation regardless, since beam4pm's release versioning may adopt
  the two-dot scheme later; the workaround (`{:code, inspect(new_version)}`) must be applied
  at the call site, not assumed away by today's version string.

## Gates

Each gate names the exact PR item from
`docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md` it verifies,
using that document's real PR-300 through PR-305 numbering and its real Acceptance line —
not an invented mapping. There are six gates, not eleven; PR-303 is `UNSUPPORTED` by design
(no `start/2` target exists in beam4pm yet), so its gate has no runnable command today.

### GATE PR-300 — Igniter.Code.Module/Function single-record-type patch adoption

- **Command**: `scripts/igniter_patch_record.sh <record_type>` (new script, PR-300),
  invoking `Igniter.Code.Module.move_to_defmodule/2` and `Igniter.Code.Function.move_to_def/2`
  to replace one admitted record type's `new_<type>/1` constructor clause inside
  `lib/beam4pm_ash.ex`, followed by a full `bash scripts/igniter_sync.sh` re-run.
- **Pass/fail evidence**: `git diff lib/beam4pm_ash.ex` after the patch script shows changes
  scoped to only the one targeted `new_<record_type>/1` clause; `git diff --exit-code
  lib/beam4pm_ash.ex` after the subsequent full `igniter_sync.sh` re-run exits 0 (no further
  diff), proving the patch is byte-identical to full regeneration for that clause.
- **Standing**: `UNKNOWN` — not yet executed against beam4pm. Research-lab evidence:
  `~/ggen_igniter/test/ggen_igniter_base_code_module_test.exs` and
  `~/ggen_igniter/test/ggen_igniter_base_code_function_test.exs`.

### GATE PR-301 — Igniter.Project.Deps version-pin/patch guard-rail adoption

- **Command**: `scripts/igniter_deps_bump.sh --check-only` (new script, PR-301) run against
  the real `~/beam4pm/mix.exs`, then against a deliberately mutated local copy with `deps:`
  inlined into `project/0`.
- **Pass/fail evidence**: against the real `mix.exs`, the command prints a pass confirming
  the `defp deps do [...] end` convention and exits 0. Against the mutated inline-`deps:`
  copy, the command exits non-zero with an explicit "inline deps: convention detected,
  refusing add_dep (see defect #1)" message and never calls
  `Igniter.Project.Deps.add_dep/2,3` — the receipt must confirm defect #1's
  `CaseClauseError` is never triggered because the guard fails closed first.
- **Standing**: `UNKNOWN`. This document already confirmed root `~/beam4pm/mix.exs` uses the
  safe `defp deps do [...] end` shape (see "Real current state" above), so the pass-path
  outcome is expected but not yet observed as an executed gate. Research-lab evidence:
  `~/ggen_igniter/test/ggen_igniter_base_project_deps_mixproject_test.exs`.

### GATE PR-302 — Igniter.Project.MixProject version-bump automation adoption

- **Command**: `bash scripts/igniter_version_bump.sh 26.8.32` (new script, PR-302) run
  against a scratch clone of `~/beam4pm`, using `Igniter.Project.MixProject.update/4` with
  `{:code, inspect(new_version)}` (defect #2's documented workaround, not the bare
  `{:code, new_version}` form).
- **Pass/fail evidence**: the scratch clone's `mix.exs` `version:` line reads
  `version: "26.8.32"` (`grep '  version:' mix.exs`); `mix compile --warnings-as-errors`
  exits 0 immediately after the patch; the script rolls back the write if compilation fails.
- **Standing**: `UNKNOWN`. Research-lab evidence:
  `~/ggen_igniter/test/ggen_igniter_base_project_deps_mixproject_test.exs` (covers
  `Igniter.Project.MixProject`).

### GATE PR-303 — Igniter.Project.Config/Application supervision-tree codegen (UNSUPPORTED)

- **Command**: none runnable today. `~/beam4pm/mix.exs`'s `application/0` only declares
  `extra_applications: [:logger]` — there is no `start/2` target to patch.
- **Pass/fail evidence**: not applicable until a future PR introduces
  `lib/beam4pm/application.ex`. When it does, the acceptance check is that its `start/2`
  contains a `children = [` binding (`grep -n "children = \[" lib/beam4pm/application.ex`)
  before any `Igniter.Project.Application.add_new_child/2,3` call is added to the
  manufacturing scripts — per defect #3, the inline-child-list shape produces a silent,
  unchecked-exit-code no-op, not a crash.
- **Standing**: `UNSUPPORTED` — by design, not deferred by oversight; this is not
  `UNKNOWN` because the precondition (a real `start/2`) does not exist. Research-lab
  evidence: `~/ggen_igniter/test/ggen_igniter_base_project_config_application_test.exs`.

### GATE PR-304 — Igniter.Project.Formatter/TaskAliases auto-registration adoption

- **Command**: add a dummy output path (e.g. `tmp_probe_gen/`) to `scripts/igniter_sync.sh`'s
  known-outputs list, run it once, then run it a second time unchanged.
- **Pass/fail evidence**: after the first run, `git diff .formatter.exs` shows the new path
  added to `inputs:`; after the second (idempotent) run, `git diff --exit-code
  .formatter.exs` exits 0 (no further change).
- **Standing**: `UNKNOWN`. Research-lab evidence:
  `~/ggen_igniter/test/ggen_igniter_base_project_formatter_taskaliases_test.exs`.

### GATE PR-305 — Igniter.Refactors.Rename pre-check adoption (NOT YET SAFE without it)

- **Command**: `scripts/igniter_rename_precheck.sh <file> <function_name>` (new script,
  PR-305) run against a scratch fixture containing both a parenless zero-arity
  `def foo do ... end` and a guarded `def bar(x) when is_integer(x) do ... end`, then against
  a fixture containing neither pattern.
- **Pass/fail evidence**: against the fixture with both patterns, the script exits non-zero
  and names both matched patterns by line number (defect #4's two failure modes — the
  `length(nil)` `ArgumentError` crash and the silent guarded-definition partial rename).
  Against the clean fixture, it exits 0. A repo-wide grep confirms no other script invokes
  `Igniter.Refactors.Rename.rename_function/4` directly, bypassing the pre-check.
- **Standing**: `UNKNOWN` — this gate proves the guard rail exists, not that
  `rename_function/4` itself is safe; PR-305 explicitly marks the underlying function
  **NOT YET SAFE** for unattended use regardless of gate outcome. Research-lab evidence:
  `~/ggen_igniter/test/ggen_igniter_base_refactors_test.exs` and
  `~/ggen_igniter/test/ggen_igniter_base_mix_task_end_user_test.exs`.

## Success state

This v26.8.31 package — this document, the referenced product-requirements and
known-defects documents, and the PR-300 through PR-305 gates above — is design and
requirements evidence only. Five of the six gates stand at `UNKNOWN` because none of their
commands has yet been executed against `~/beam4pm`; PR-303 stands at `UNSUPPORTED` by design
because its precondition (a real `start/2`) does not yet exist. The sole executed evidence
available anywhere in this document set is the 37 passing tests in `~/ggen_igniter`, and
those tests prove the underlying `igniter`/`ggen_igniter` capability surface works in the
research lab, not that beam4pm has adopted any part of it. This package becomes real
manufacturing evidence only when each runnable gate's exact command is run against beam4pm,
its diff/exit-code/receipt evidence is collected as specified, and the standing above is
updated from `UNKNOWN` to whatever the observed outcome actually supports — never assumed
forward from a research-lab pass.

## See Also

- `docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md` — the
  PR-300 through PR-305 items this document defines one gate per
- `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` — full write-up of the 37-test
  research-lab evidence and all four documented `igniter` 0.8.3 defects
- `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the EPIC B4PM-1700 / story
  breakdown this document's gates support
- `docs/jira/v26.8.29/11-release-gates-receipts.md` — the standing vocabulary and evidence
  dimensions this document reuses verbatim
- `docs/jira/v26.8.29/16-gate-closure-m0-m6.md` — the existing M0-M6 manufacturing gate
  closure this document's gates are additive to, not a replacement for
- `~/beam4pm/CLAUDE.md` — source-authority doctrine and existing `scripts/*_sync.sh`
  inventory this document's new probe scripts must follow
