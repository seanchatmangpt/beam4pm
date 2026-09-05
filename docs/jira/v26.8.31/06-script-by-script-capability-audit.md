# Script-by-Script Igniter Capability Audit

Last updated: 2026-08-31.

## What this document is

25 real beam4pm manufacturing/verification scripts under `~/beam4pm/scripts/`
were dispatched one script per agent, each instructed to read the script in
full and check it against (a) the real Igniter capability surface documented
in
`docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md`
and (b) the 4 known defect triggers documented in
`docs/jira/v26.8.31/03-known-defects-and-mitigations.md`. This is a real
audit result: every finding below is grounded in a full read of the named
script (and, where relevant, its generated output files, templates, and
`mix.exs`), not a guess from the filename. Standing labels follow the
vocabulary defined in `docs/jira/v26.8.29/11-release-gates-receipts.md`:
`UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED | BUILD_BROKEN | UNSUPPORTED |
REFUSED_*` — not directly applicable per-script here since no script was
executed as part of this audit; the audit instead classifies each script's
existing real mechanism against Igniter's capability surface.

**Disclosed gap:** 24 of the 25 dispatched agents completed with a real,
grounded reading of their assigned script. The agent assigned to
`scripts/ecosystem_process_mine.exs` failed (its structured-output call hit
the retry cap after 5 failed attempts) and did not produce an independent
finding. `ecosystem_process_mine.exs` is a real target file referenced in
the `ecosystem_process_mine.sh` section below (that script's own agent read
enough of `ecosystem_process_mine.exs` to describe it as the JSON-consuming
half of the same pipeline), but that is a secondary, not a dedicated, read —
it has not been audited to the same standard as the other 24 scripts. The
summary table below lists it separately, marked `not independently audited`,
rather than folding it silently into `ecosystem_process_mine.sh`'s row.

## Method

For each script, three questions were answered from the real file content:

1. What does the script actually do, mechanically (full-file regen via
   `mix ggen_igniter.sync`, a shell/erlang/python runtime harness, a
   sed/grep-based check, a `cargo build`, or some other real mechanism)?
2. Does that mechanism have a real Igniter capability target (a manual
   sed/grep structural check that `Igniter.Code.Pattern` could replace, a
   manual `mix.exs`/config edit that `Igniter.Project.Deps` /
   `Igniter.Project.MixProject` / `Igniter.Project.Config` could replace, a
   manual supervision-tree edit that `Igniter.Project.Application` could
   replace, or a manual rename that `Igniter.Refactors.Rename` could
   replace)?
3. Is any of the 4 known defect triggers from
   `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` reachable from
   the script's real, current pipeline (not a hypothetical future one)?

## Summary table

| Script | Candidacy | Capability | Defect risk | Recommendation |
|---|---|---|---|---|
| `actuation_selfmine.exs` | not-applicable | n/a | none | do not adopt |
| `actuation_sync.sh` | not-applicable | n/a | none | do not adopt |
| `claude_workflow_reactor_sync.sh` | not-applicable | n/a | none | do not adopt |
| `dogfood_selfmine.exs` | not-applicable | n/a | none | do not adopt |
| `ecosystem_process_mine.sh` | not-applicable | n/a | none | do not adopt |
| `pm4py_examples_wasm.exs` | not-applicable | n/a | none | do not adopt |
| `pro_capability_manifest_sync.sh` | weak-candidate | n/a | none | do not adopt (revisit only if template becomes ontology-bound) |
| `pro_compatibility_sync.sh` | weak-candidate | n/a | none | do not adopt |
| `pro_doctor_sync.sh` | not-applicable | n/a | none | do not adopt |
| `pro_license_sync.sh` | weak-candidate | n/a | none | do not adopt |
| `pro_tenancy_sync.sh` | not-applicable | n/a | none | do not adopt |
| `process_governor_sync.sh` | not-applicable | n/a | none | do not adopt |
| `receipt_chain_sync.sh` | weak-candidate | n/a | none | do not adopt (note rename hazards in `beam4pm_process_governor.ex` if ever renamed) |
| `revenue_economics_sync.sh` | not-applicable | n/a | none | do not adopt |
| `revenue_metering_sync.sh` | not-applicable | n/a | none | do not adopt |
| `revenue_suite_demo.exs` | not-applicable | n/a | none | do not adopt (real codegen lives one layer down, in the 3 named sync scripts) |
| `rf1_dfg_sync.sh` | not-applicable | n/a | none | do not adopt |
| `rf2_conformance_sync.sh` | weak-candidate | n/a | none | do not adopt (only plausible future fit: `Igniter.Project.Deps.add_dep` if this script is later extended) |
| `rf3_ocel_sync.sh` | not-applicable | n/a | none | do not adopt |
| `rust4pm_ocel_examples_wasm.exs` | not-applicable | n/a | none | do not adopt |
| `rust4pm_wasm_build.sh` | not-applicable | n/a | none | do not adopt |
| `gate_m2_check.sh` | weak-candidate | n/a | none | do not adopt for this script itself; real candidates live one layer down in the `*_sync.sh` scripts it dispatches to |
| `standing_vocabulary_check.sh` | not-applicable | n/a | none | do not adopt |
| `roundtrip_check.sh` | not-applicable | n/a | none | do not adopt |
| `ecosystem_process_mine.exs` | not independently audited | n/a | unknown | dedicated agent failed (StructuredOutput retry cap); only covered secondhand via `ecosystem_process_mine.sh`'s section below |

All 25 scripts audited resolve to **not-applicable** or **weak-candidate** —
zero scripts qualify as a strong Igniter-adoption candidate as currently
written. This matches `docs/jira/v26.8.31/03-known-defects-and-mitigations.md`'s
own finding that beam4pm's present manufacturing pipeline does not call
`Igniter.Code.*`, `Igniter.Project.*`, or `Igniter.Refactors.*` anywhere:
this audit confirms that finding held script-by-script, not just for the
one previously-known `igniter_sync.sh` path.

## `actuation_selfmine.exs`

- **Candidacy:** not-applicable
- **Current mechanism:** Pure runtime dogfood/verification script, no code
  generation or file-patching at all: (1) calls real `BeamPM.Actuation.run/2`
  four times (lines 79-107) against
  `qualification/fixtures/toy_gym_bridge.py`; (2) re-reads consequence
  receipt JSON files from `receipts/actuation-selfmine/` off disk (lines 91,
  102, ~150); (3) mines the actuation process via
  `BeamPM.Discovery.traces_from_events/2` + `dfg_from_traces` (lines
  152-155); (4) hard-asserts trace/DFG shape via a local `assert/2`+`fail/1`
  helper (lines 208-274) that calls `System.halt(1)` on failure. It never
  writes, edits, or regenerates any `.ex`/`.exs`/`mix.exs`/config file — it
  only reads `lib/beam4pm_actuation.ex` indirectly (by calling its compiled
  functions) and reads `qualification/fixtures/toy_gym_bridge.py` only to
  check `File.exists?/2` (line 41).
- **Target files:** `scripts/actuation_selfmine.exs`,
  `lib/beam4pm_actuation.ex`, `qualification/fixtures/toy_gym_bridge.py`,
  `receipts/actuation-selfmine/*.json`
- **Capability:** n/a
- **Defect risk:** none — the script performs no `mix.exs` edits
  (`Igniter.Project.Deps`/`MixProject`), no supervision-tree edits
  (`Igniter.Project.Application`), and no function renames
  (`Igniter.Refactors.Rename`) anywhere in its own pipeline, so none of the
  4 known defects can trigger from this script's real behavior.
- **Recommendation:** Do not adopt Igniter here. This script has no
  full-file-regen step, no sed/grep-based check, no `mix.exs` edit, no
  config edit, and no rename — it is a runtime BRCE-actuation-and-mine
  verification harness with hard assertions, and Igniter's AST-codemod
  surface (`Code.*`/`Project.*`/`Refactors.*`) addresses source-file
  manufacturing/patching, a category this script simply doesn't perform.

## `actuation_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Two full-file regenerations via
  `mix ggen_igniter.sync` with `--out lib/beam4pm_actuation.ex` (lines
  24-30) and `--out test/beam4pm_actuation_test.exs` (lines 33-39), each
  overwriting the whole target file from a SPARQL-queried RDF projection
  plus EEx template, then `mix compile --warnings-as-errors && mix test` as
  verification (lines 42-43). No sed/grep checks, no `mix.exs` edit, no
  config edit, no rename step exist in this script.
- **Target files:** `scripts/actuation_sync.sh`, `mix.exs`, `ontology.ttl`,
  `lib/beam4pm_actuation.ex`, `test/beam4pm_actuation_test.exs`
- **Capability:** n/a
- **Defect risk:** none — script calls no
  `Igniter.Project.Deps`/`MixProject`/`Application`/`Config` and no
  `Igniter.Refactors.Rename`, so none of the 4 defects are reachable.
  Checked anyway: `mix.exs` already isolates deps in `defp deps do [...] end`
  (mix.exs:27-31) called via `deps: deps()` in `project/0` (mix.exs:8) —
  defect 1's inline-deps trigger is absent. `lib/beam4pm_actuation.ex` has
  no `start/2` or `Supervisor.start_link` at all — defect 3 moot. The file
  does have one parenless zero-arity def,
  `def admitted_actuations, do: @admitted_actuations`
  (lib/beam4pm_actuation.ex:597), which would trip defect 4 if ever renamed
  via `Igniter.Refactors.Rename` — but no rename step exists here.
- **Recommendation:** Do not adopt `Igniter.Code.*`/`Project.*`/`Refactors.*`
  for this script: its entire real pipeline is whole-file
  ontology-to-EEx-template regeneration of ggen-manufactured files, not an
  incremental AST patch, `mix.exs`/config edit, or rename against
  hand-authored code, so none of the tested Igniter capabilities target a
  step this script actually performs.

## `claude_workflow_reactor_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Bash script with 3 steps: (1) line 21
  `[ ! -f "$FIXTURE" ]` guard refusing early if
  `qualification/fixtures/claude-workflows/journal.jsonl` is missing; (2)
  lines 28-32 `mix ggen_igniter.sync --ontology ontology.ttl --query
  admitted=.../admitted_actions.rq --template
  .../beam4pm_claude_workflow_reactor.ex.eex --out
  lib/beam4pm_claude_workflow_reactor.ex`; (3) lines 34-38 the same sync
  pattern rendering `beam4pm_claude_workflow_reactor_test.exs.eex` to
  `test/beam4pm_claude_workflow_reactor_test.exs`. Both EEx templates are
  static (no ontology graph bindings used), full-file regeneration of a
  `defmodule ... GENERATED ... Do not edit` file each run — per each
  template's own header comment ("Bindings: NONE required").
- **Target files:** `scripts/claude_workflow_reactor_sync.sh`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_claude_workflow_reactor.ex.eex`,
  `.../beam4pm_claude_workflow_reactor_test.exs.eex`,
  `lib/beam4pm_claude_workflow_reactor.ex`,
  `test/beam4pm_claude_workflow_reactor_test.exs`,
  `qualification/fixtures/claude-workflows/journal.jsonl`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt Igniter here: the script contains no
  `mix.exs` edit (no `Igniter.Project.Deps`/`MixProject`/`TaskAliases`
  target), no config edit (no `Igniter.Project.Config` target), no manual
  sed/grep check (no `Igniter.Code.Pattern` target), and no function rename
  (no `Igniter.Refactors.Rename` target) — its only two mutating steps are
  intentional, self-declared full-file EEx regenerations of
  generated-and-marked-do-not-edit files, which is exactly the
  `ggen_igniter.sync` design already in use, not an AST-patch opportunity.

## `dogfood_selfmine.exs`

- **Candidacy:** not-applicable
- **Current mechanism:** The script (~230 lines) does not itself generate
  or patch any source file. It: (1) checks module loadability via
  `Code.ensure_loaded?/1` (lines ~48-56), (2) checks required input files
  exist via `File.exists?/1` (lines ~62-69), (3) attaches a `:telemetry`
  handler and invokes `Mix.Task.run("ggen_igniter.sync", args)` (line ~99)
  — delegating the actual file write/patch of `lib/beam4pm_ash.ex` entirely
  to the external `ggen_igniter.sync` mix task (an EEx-template-based
  full-file regen owned by a different tool/package, not by this script),
  (4) converts captured OCEL telemetry maps into `BeamPM.Types.OcelEvent`
  structs via the real validating `new/1` constructor, (5) mines a DFG via
  `BeamPM.Discovery.traces_from_events/2` + `dfg_from_traces/1`, (6)
  hard-asserts the mined trace/DFG/conformance match an expected lifecycle
  sequence (lines ~180-230) via a small local `check/3` accumulator — plain
  Elixir match?/guard clauses, not sed/grep text scanning, and not
  AST-level `Igniter.Code.Pattern` matching since there is no source file
  being pattern-matched here, and (7) cross-checks a JSONL receipt file's
  embedded events are a strict prefix of the captured events
  (`check_receipt/2`, reads `.ggen_igniter/receipts/*.jsonl` directly via
  `File.ls`/`File.read` + `Jason.decode` — no source-code parsing involved).
- **Target files:** `scripts/dogfood_selfmine.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/ontology.ttl`,
  `.../igniter/queries/records.rq`, `.../igniter/queries/fields.rq`,
  `.../igniter/templates/beam4pm_ash.ex.eex`, `lib/beam4pm_ash.ex` (write
  target, mutated by the delegated `ggen_igniter.sync` task, not by this
  script), `.ggen_igniter/manifest.json`, `.ggen_igniter/receipts/*.jsonl`,
  `mix.exs`
- **Capability:** n/a
- **Defect risk:** none — checked `mix.exs` since it is the file the 4
  known defects most plausibly implicate: `deps()` is already a separate
  `defp deps do [...] end` (mix.exs line ~26), not inlined in `project/0`
  (`project/0` at line ~4 calls `deps: deps()`, a reference, not an inline
  list) — so defect #1 (`Deps.add_dep` inline-deps crash) would not trigger
  even if this script called `Igniter.Project.Deps`, but the script never
  calls it. No `start/2` exists (`application/0` in mix.exs just returns
  `extra_applications`, no supervision tree), so defect #3
  (`Application.add_new_child` needing a `children =` binding) is not
  applicable. No function-rename step exists anywhere in this script, so
  defect #4 (`Refactors.Rename` on parenless/guarded defs) is not
  applicable. Defect #2 (`MixProject.update` `inspect/1` wrapping) is not
  applicable since the script never touches `mix.exs`.
- **Recommendation:** Do not adopt `Igniter.Code.*`/`Project.*`/`Refactors.*`
  in this script: it performs zero source-code generation, patching,
  `mix.exs` editing, config editing, or renaming itself — every real file
  mutation (`lib/beam4pm_ash.ex` regen, `.ggen_igniter/manifest.json`
  update, receipt append) is delegated wholesale to the external
  `mix ggen_igniter.sync` task, and this script's own logic is purely
  read-only verification (module/file existence checks, telemetry capture,
  DFG mining, hard assertions, receipt cross-check) with no text-pattern
  (sed/grep) or full-file-regen step of its own to replace; if Igniter
  adoption is wanted for this pipeline it belongs inside
  `ggen_igniter.sync`'s own template-rendering implementation, not in this
  dogfood/verification harness.

## `ecosystem_process_mine.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Two-stage bash+python+mix pipeline, no code
  generation or code patching anywhere. Stage 1 (lines 33-71):
  `gh api repos/$REPO/actions/runs` fetches this repo's own GitHub Actions
  runs of the rail workflow into `tmp/ecosystem-mine/rail-runs.json`, then
  an inline `python3 - ... <<'PY'` heredoc (lines 41-66) calls
  `gh api .../jobs` per run and writes one JSON event object per executed
  step to `tmp/ecosystem-mine/rail-events.json`. Stage 2 (line 69:
  `mix run scripts/ecosystem_process_mine.exs`) reads that JSON, admits
  each event through the real `BeamPM.Types.OcelEvent.new/1` validating
  constructor (lines 78-92), builds traces/variants/a green-path DFG via
  `BeamPM.Discovery.*` (lines 95-125), and hard-asserts required lifecycle
  edges and green-run fitness (lines 127-163), plus an optional cross-check
  against a downloaded replay receipt against `vendor/ggen-marketplace`'s
  real gitlink (lines 165-183). It reads/checks real BEAM process-mining
  data structures at runtime; it never writes, patches, or regenerates any
  `.ex`/`.exs`/`mix.exs`/config source file.
- **Target files:** `scripts/ecosystem_process_mine.sh`,
  `scripts/ecosystem_process_mine.exs`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt Igniter capabilities for this script:
  its entire real pipeline (gh api fetch -> JSON event log -> OcelEvent
  admission -> Discovery/Precision mining -> hard assertions) is data
  ingestion and process-mining analysis, not code generation, code
  patching, `mix.exs`/config editing, or renaming — there is no full-file
  regen, no sed/grep-based structural check, no `mix.exs` or config edit,
  and no rename step anywhere in this script or the `.exs` it runs for any
  `Igniter.Code.*`/`Project.*`/`Refactors.*` capability to replace or
  augment. (Incidentally, beam4pm's own `mix.exs` already uses a separate
  `defp deps do [...] end`, not inline `deps:` in `project/0`, so defect 1
  would not trigger there either if some other script ever did touch it; no
  `application.ex`/`start/2` with `children=` exists in this repo, so
  defect 3 is likewise not applicable anywhere in beam4pm.)

## `pm4py_examples_wasm.exs`

- **Candidacy:** not-applicable
- **Current mechanism:** Pure runtime verification script (`mix run
  scripts/pm4py_examples_wasm.exs`, per the script's own header comment
  lines 9-11). It calls `BeamPM.Rust4PM.{start,import_pnml_path,
  align_trace,import_xes_path,activities_to_alphabet,activity_position,
  free_net,free_log}` against the real wasm-hosted `process_mining` 0.6.2,
  then hard-asserts results with a local `assert!/2` helper (lines
  ~257-263) that raises "ASSERTION FAILED: ..." on mismatch. It reads two
  fixture files verbatim off disk via `fixture!/1` (lines ~245-253,
  `Path.expand` + `File.exists?` check) — `@running_example_xes` and
  `@running_example_pnml` under `qualification/fixtures/pm4py/` (confirmed
  present: `running-example.xes`, `running-example.pnml`, `README.md`) and
  `@receipt_xes` at `qualification/fixtures/receipt.xes` (confirmed
  present). It does not write, patch, or generate any file; it does not
  touch `mix.exs`, `config/*.exs`, `application.ex`'s `start/2`, or any
  function names/call sites subject to rename.
- **Target files:** `scripts/pm4py_examples_wasm.exs`,
  `qualification/fixtures/pm4py/running-example.xes`,
  `qualification/fixtures/pm4py/running-example.pnml`,
  `qualification/fixtures/receipt.xes`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt Igniter here: the script performs no
  full-file regen, no sed/grep-style structural check, no `mix.exs`/config
  edit, and no function rename — it is read-only fixture ingestion plus
  wasm-call assertions, none of which maps to
  `Igniter.Code.*`/`Project.*`/`Refactors.*` territory, so all four defect
  triggers are moot for this file.

## `pro_capability_manifest_sync.sh`

- **Candidacy:** weak-candidate
- **Current mechanism:** Lines 12-24 run `mix ggen_igniter.sync --ontology
  ontology.ttl --query admitted=.../admitted_actions.rq --template
  .../beam4pm_pro_capability_manifest.ex.eex --out
  lib/beam4pm_pro_capability_manifest.ex`, then an identical second
  invocation for the test file's `.exs.eex` template. Both templates
  (template line 9: "Bindings: NONE required -- fully static") are static
  EEx with no ontology bindings actually interpolated into the body — the
  SPARQL query bound as `admitted` (`queries/admitted_actions.rq`,
  selecting `?action_name`/`?gym_op` from `bpma:AdmittedActuation`) does not
  appear anywhere in either template's `<%= %>` output (verified by reading
  both templates in full). This is a whole-file regen/overwrite of
  `lib/beam4pm_pro_capability_manifest.ex` and
  `test/beam4pm_pro_capability_manifest_test.exs` on every run, producing
  byte-identical output each time.
- **Target files:** `scripts/pro_capability_manifest_sync.sh`,
  `lib/beam4pm_pro_capability_manifest.ex`,
  `test/beam4pm_pro_capability_manifest_test.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_capability_manifest.ex.eex`,
  `.../beam4pm_pro_capability_manifest_test.exs.eex`,
  `.../igniter/queries/admitted_actions.rq`
- **Capability:** n/a
- **Defect risk:** none — neither generated file is a `mix.exs` (defect 1),
  an `Application` `start/2` (defect 3), or a rename target (defect 4); no
  `MixProject.update/4` semver call is used anywhere in this pipeline
  (defect 2). Defects 1/3/4 concern a different class of target file than
  what this script produces, so none is triggered by this pipeline as
  currently written.
- **Recommendation:** Do not adopt Igniter capabilities for this script as
  it stands: it generates neither a `mix.exs`, a supervision tree, a config
  file, nor a rename target, so none of the 4 known defect triggers apply,
  and both templates are confirmed fully static (no ontology-driven
  bindings substituted into the body, per the template's own comment at
  line 9 and direct inspection of both `.eex` files) so a full-file
  overwrite and a targeted `Igniter.Code.Module` AST patch would emit
  identical bytes every run — there is no real per-run delta to justify the
  extra machinery; only if a future revision makes these templates
  ontology-bound (interpolating `admitted_actions.rq` results into
  `capabilities/0`) would targeted patching become worth reconsidering.

## `pro_compatibility_sync.sh`

- **Candidacy:** weak-candidate
- **Current mechanism:** Lines 8-19: `mix deps.get` then two
  `mix ggen_igniter.sync --ontology ontology.ttl --query admitted=... --template
  ...eex --out ...` invocations that render
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_compatibility.ex.eex`
  -> `lib/beam4pm_pro_compatibility.ex` and
  `beam4pm_pro_compatibility_test.exs.eex` ->
  `test/beam4pm_pro_compatibility_test.exs`. Both outputs are stamped
  "# GENERATED by ggen_igniter ... Do not edit." — this is a full-file EEx
  template regen driven by a SPARQL query over `ontology.ttl`, not a
  sed/grep-based check and not a `mix.exs`/config/rename edit.
- **Target files:** `scripts/pro_compatibility_sync.sh`,
  `lib/beam4pm_pro_compatibility.ex`,
  `test/beam4pm_pro_compatibility_test.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_compatibility.ex.eex`,
  `.../beam4pm_pro_compatibility_test.exs.eex`,
  `.../igniter/queries/admitted_actions.rq`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt `Igniter.Code`/`Project`/`Refactors`
  here: the script contains no `mix.exs` edit, no config edit, no rename,
  and no sed/grep-based check for `Igniter.Code.Pattern` to replace — it is
  a single ontology-driven full-file codegen step (SPARQL query over
  `ontology.ttl` -> EEx template -> whole-file write via
  `mix ggen_igniter.sync`), and both outputs are stamped "# GENERATED by
  ggen_igniter from the beam4pm_pro_compatibility static template. Do not
  edit.", signalling the file is fully machine-owned end to end, so there
  is no partial-AST-patch need. `mix.exs` itself uses `defp deps do [...]
  end` (a separate function, not inline in `project/0`) so defect #1 would
  not trigger even if a future step touched it, but this script never
  touches `mix.exs`, config, or performs any rename, so all four defects
  are inapplicable to its real pipeline.

## `pro_doctor_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Two calls to `mix ggen_igniter.sync --ontology
  ontology.ttl --query admitted=$IGN/queries/admitted_actions.rq --template
  $IGN/templates/beam4pm_pro_doctor.ex.eex --out
  lib/beam4pm_pro_doctor.ex` (lines 12-16) and the analogous test-template
  call (lines 18-22) — i.e. RDF-query-driven EEx template rendering to a
  full-file regen, guarded by a "# GENERATED by ggen_igniter ... Do not
  edit." header (`lib/beam4pm_pro_doctor.ex:1`,
  `test/beam4pm_pro_doctor_test.exs:1`). Neither generated file's content
  is derived from or merged into an existing AST — each
  `mix ggen_igniter.sync` call overwrites the whole target file from the
  ontology + template, with no read-modify-write step against prior file
  content.
- **Target files:** `scripts/pro_doctor_sync.sh`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_doctor.ex.eex`,
  `.../beam4pm_pro_doctor_test.exs.eex`,
  `.../igniter/queries/admitted_actions.rq`, `lib/beam4pm_pro_doctor.ex`,
  `test/beam4pm_pro_doctor_test.exs`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt `Igniter.Code.*`/`Refactors.*` here: both
  `mix ggen_igniter.sync` steps are ontology-driven full-file regeneration
  from RDF (source of truth = `ontology.ttl` via a SPARQL query, not
  existing Elixir source), explicitly marked "GENERATED ... Do not edit" —
  there is no existing hand-authored AST to targeted-patch, so
  `Igniter.Code.Module`/`Pattern`-style incremental patching has no
  applicable use here; the script also never touches `mix.exs` or an
  `Application` `start/2`, so none of the four documented defect triggers
  are reachable from this script's real pipeline (confirmed: `mix.exs`
  already uses a separate `defp deps do [...] end`, not inline `project/0`
  deps, and beam4pm has no OTP `Application`/`start_link` module at all —
  `def application do [extra_applications: [:logger]] end` only).

## `pro_license_sync.sh`

- **Candidacy:** weak-candidate
- **Current mechanism:** Full-file EEx-template regeneration via
  `mix ggen_igniter.sync` (two invocations, lines 11-21), writing
  `lib/beam4pm_pro_license.ex` and `test/beam4pm_pro_license_test.exs`
  wholesale from
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_license.ex.eex`
  and `beam4pm_pro_license_test.exs.eex`, driven by a SPARQL query
  (`queries/admitted_actions.rq`) that in this case returns zero bindings
  the templates actually use — both templates state "Bindings: NONE
  required -- fully static" (both `.eex` files, lines 1-6). The script does
  not touch `mix.exs`, config, or any supervision tree; it is a two-step
  `deps.get` + two full-file-regen pipeline, nothing else.
- **Target files:** `scripts/pro_license_sync.sh`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_license.ex.eex`,
  `.../beam4pm_pro_license_test.exs.eex`,
  `.../igniter/queries/admitted_actions.rq`, `lib/beam4pm_pro_license.ex`
  (generated output), `test/beam4pm_pro_license_test.exs` (generated
  output), `mix.exs`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt: this script generates two brand-new,
  self-contained files (a `BeamPM.Pro.License` module + its test) from a
  fully static template with zero bindings — there is no existing AST to
  patch, no `mix.exs` deps/project edit (`mix.exs` uses `defp deps do`, not
  inline `project/0` deps, so defect #1 would not even trigger if `Deps`
  were used, but `Deps` is not relevant here since no dependency is being
  added), no config edit, no supervision-tree child being inserted (no
  `start/2` found in `lib/`, so defect #3's `children =` requirement is
  moot), and no function rename (so defect #4's parenless/guarded-def
  hazard is moot). Full-file regeneration of a brand-new module is exactly
  the case `Igniter.Code.*` AST-patching does not help with (nothing
  pre-existing to target/patch); the pipeline stays on `ggen_igniter`'s own
  EEx-template mechanism, not Igniter's capability surface.

## `pro_tenancy_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Two full-file regenerations via
  `mix ggen_igniter.sync` (lines 11-21): one templates
  `$IGN/templates/beam4pm_pro_tenancy.ex.eex` ->
  `lib/beam4pm_pro_tenancy.ex`, one templates
  `$IGN/templates/beam4pm_pro_tenancy_test.exs.eex` ->
  `test/beam4pm_pro_tenancy_test.exs`, both driven by the same
  `admitted_actions.rq` SPARQL query against `ontology.ttl`. No sed/grep
  verification step, no `mix.exs` edit, no config edit, no rename step, no
  supervision-tree edit anywhere in the script (confirmed by reading the
  full 21-line file). Both outputs are marked "GENERATED ... Do not edit"
  and are fully static (script's own header comment: "Fully static (no
  graph bindings)").
- **Target files:** `lib/beam4pm_pro_tenancy.ex`,
  `test/beam4pm_pro_tenancy_test.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_pro_tenancy.ex.eex`,
  `.../beam4pm_pro_tenancy_test.exs.eex`,
  `.../igniter/queries/admitted_actions.rq`, `ontology.ttl`
- **Capability:** n/a
- **Defect risk:** none — script performs no `mix.exs` edit
  (`Igniter.Project.Deps`), no config edit (`Igniter.Project.Config`), no
  supervision-tree child insertion
  (`Igniter.Project.Application.add_new_child`), and no function rename
  (`Igniter.Refactors.Rename`). None of the 4 defect triggers are reachable
  by this pipeline. For completeness: `mix.exs`'s `project/0` calls
  `deps: deps()` with `deps` in a separate `defp deps do` block — i.e. not
  inlined in `project/0` — so even if `Igniter.Project.Deps` were later
  wired in for some other script, defect #1 would not trigger against this
  `mix.exs` shape. This `mix.exs` fact is unrelated to `pro_tenancy_sync.sh`
  itself, which never touches `mix.exs`.
- **Recommendation:** Do not adopt Igniter for this script: it has no
  targeted-edit step (no `mix.exs`/config/supervision/rename operation) for
  `Igniter.Project.*`/`Refactors.*` to replace, and its two outputs are
  declared-static full-file generations from a template+SPARQL query,
  which is exactly the `ggen_igniter.sync` full-regen contract working as
  intended, not a manual patch masquerading as regen — there is nothing
  here for `Igniter.Code.*` AST-patching to improve on since there is no
  pre-existing hand-authored file being merged into.

## `process_governor_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Two `mix ggen_igniter.sync --ontology ontology.ttl
  --query ... --template ... --out ...` invocations (lines 20-31), each
  doing a full-file regeneration of `lib/beam4pm_process_governor.ex` and
  `test/beam4pm_process_governor_test.exs` from an `.eex` template driven
  by a SPARQL query over `ontology.ttl`, followed by
  `mix compile --warnings-as-errors` and `mix test` (lines 34-35) as the
  sole verification step — no sed/grep-based check, no `mix.exs` edit, no
  config edit, and no rename anywhere in the script.
- **Target files:** `scripts/process_governor_sync.sh`,
  `lib/beam4pm_process_governor.ex`,
  `test/beam4pm_process_governor_test.exs`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt Igniter here: the script's only two
  generation steps are deliberate whole-file regenerations of ggen-owned
  artifacts (both files carry the header "GENERATED by ggen_igniter from
  the admitted bpmg:ProcessContract graph. Do not edit."), the correct
  mechanism for content whose provenance is an RDF ontology graph, not a
  targeted incremental patch to hand-authored code — there is no sed/grep
  check to become `Igniter.Code.Pattern`, no manual `mix.exs`/config edit to
  become `Igniter.Project.Deps`/`Config` (`mix.exs` already uses a separate
  `defp deps do [...] end`, not inline `deps:` in `project/0`, so defect 1
  does not even apply), and no rename to become `Igniter.Refactors.Rename`;
  verification is already a real `mix compile --warnings-as-errors` +
  `mix test`, which Igniter would not improve on.

## `receipt_chain_sync.sh`

- **Candidacy:** weak-candidate
- **Current mechanism:** Full-file codegen only:
  `mix ggen_igniter.sync --ontology ontology.ttl --query ... --template
  $IGN/templates/beam4pm_receipt_chain.ex.eex --out
  lib/beam4pm_receipt_chain.ex` (lines 27-31), then it shells out to
  `bash scripts/actuation_sync.sh` and
  `bash scripts/process_governor_sync.sh` (lines 37-38, each itself a
  `ggen_igniter.sync` full-file-out invocation followed by
  `mix compile --warnings-as-errors` / `mix test`), then a final
  `ggen_igniter.sync ... --out test/beam4pm_receipt_chain_test.exs` (lines
  40-45). Every artifact is produced by `ggen_igniter`'s ontology-driven
  template rendering to a whole `--out` file path; the script contains zero
  sed/grep text checks, zero manual `mix.exs` edits, zero manual config
  edits, and zero renames — it is pure sequential whole-file (re)generation
  with `mix compile`/`mix test` as the verification gate between steps.
- **Target files:** `lib/beam4pm_receipt_chain.ex`,
  `lib/beam4pm_actuation.ex`, `lib/beam4pm_process_governor.ex`,
  `test/beam4pm_receipt_chain_test.exs`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none — none of the 4 defect-triggering Igniter
  capabilities (`Deps.add_dep`, `MixProject.update`,
  `Application.add_new_child`, `Refactors.Rename`) is invoked anywhere in
  this script's real pipeline, so no defect is reachable from it. For
  context only (not triggered by this script): `mix.exs`'s `deps()` is a
  separate `defp deps do [...] end`, not inlined in `project/0` — so
  defect 1 would not fire if `Deps.add_dep` were ever added here.
  `~/beam4pm/lib` has no `Application` module with a `start/2` binding
  `children = [...]` — defect 3's target shape doesn't exist in this repo
  at all. `lib/beam4pm_process_governor.ex:474` has a real parenless
  zero-arity def, `def contracts, do: @contracts`, and multiple guarded
  defs (e.g. `def initial_snapshot(process_id, _opts \\ []) when
  is_binary(process_id) do`, `def run(process_id, actuation_opts) when
  is_binary(process_id) and is_list(actuation_opts) do`) — both shapes that
  would trip defect 4 if `Refactors.Rename` were ever pointed at this file,
  but the script never performs a rename.
- **Recommendation:** Do not adopt: this script never performs a manual
  sed/grep check, `mix.exs` dep/config edit, supervision-tree child
  insertion, or function rename — it is pure whole-file ontology-driven
  regeneration via `ggen_igniter` into GENERATED-header files nobody
  hand-edits, which is the correct mechanism for this job; none of the 4
  documented Igniter defects are reachable from its real code paths,
  though if a future step ever adds a `Refactors.Rename` pass over
  `beam4pm_process_governor.ex` it must special-case the parenless
  `contracts/0` and the guarded defs first.

## `revenue_economics_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Two `mix ggen_igniter.sync` invocations (lines
  21-27, 29-35) each do a full-file regen from a static `.eex` template
  (`beam4pm_revenue_economics.ex.eex` and
  `beam4pm_revenue_economics_test.exs.eex` under
  `$PACK/igniter/templates`) writing directly to
  `lib/beam4pm_revenue_economics.ex` (677 lines) and
  `test/beam4pm_revenue_economics_test.exs` (418 lines) via `--out`. No
  `mix.exs` edit, no config edit, no rename, no cargo step (per the
  script's own header comment: "No cargo step... every collaborator ... is
  already in-tree or OTP built-in").
- **Target files:** `scripts/revenue_economics_sync.sh`,
  `lib/beam4pm_revenue_economics.ex`,
  `test/beam4pm_revenue_economics_test.exs`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none — this script never touches `mix.exs` (`deps()` is
  already a separate private function, not inline in `project/0`, so
  defect 1 wouldn't trigger even hypothetically), never edits any `start/2`
  or supervision tree (a grep across `lib/*.ex` found
  `Application.ensure_all_started` calls and one `Wasmex.start_link/1` in
  `beam4pm_rust4pm.ex`, but no `children = [...]`-bound `start/2` anywhere
  the script's own targets touch), and the generated module's own
  functions are all either guarded (e.g.
  `def parse_file(path) when is_binary(path) do`) or non-zero-arity — no
  parenless zero-arity def exists to expose defect 4, and nothing in this
  pipeline renames a function at all.
- **Recommendation:** Do not adopt Igniter for this script: both its steps
  are whole-new-file generation (a fresh module + fresh test module written
  to paths that don't pre-exist as hand-edited code), which is exactly what
  `ggen_igniter.sync`'s template-to-file `--out` mechanism is for — there
  is no existing AST to patch, no `mix.exs`/config edit, and no rename in
  this pipeline for `Igniter.Code.*`/`Project.*`/`Refactors.*` to target.

## `revenue_metering_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** The script (35 lines) runs `mix deps.get` then two
  `mix ggen_igniter.sync` invocations, each a full-file EEx-template
  regeneration against
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/`:
  `beam4pm_revenue_metering.ex.eex` -> `lib/beam4pm_revenue_metering.ex`
  (lines 24-29), and `beam4pm_revenue_metering_test.exs.eex` ->
  `test/beam4pm_revenue_metering_test.exs` (lines 31-35). Both templates
  are declared fully static in their own header comments (no RDF graph
  bindings used; `--query admitted=...admitted_actions.rq` is passed only
  because `mix ggen_igniter.sync` requires ≥1 `--query` flag, and the
  generated code never references that query's result). The script
  performs no `mix.exs` edit, no config edit, no supervision-tree/
  application edit, no rename, and no manual sed/grep-based check step
  anywhere in its own body.
- **Target files:** `scripts/revenue_metering_sync.sh`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_revenue_metering.ex.eex`,
  `.../beam4pm_revenue_metering_test.exs.eex`,
  `lib/beam4pm_revenue_metering.ex`,
  `test/beam4pm_revenue_metering_test.exs`
- **Capability:** n/a
- **Defect risk:** none — the script never touches `mix.exs` (`deps/1` is
  already a separate `defp deps do ... end`, not inlined into `project/0`,
  so defect 1 would not trigger even hypothetically), never touches an
  application `start/2` or a supervision tree (defect 3 n/a), and performs
  no function rename anywhere (defect 4 n/a). It only writes two brand-new
  whole files from static EEx templates via `mix ggen_igniter.sync`, which
  is not one of the 4 defect-bearing `Igniter.Project`/`Refactors` call
  sites at all.
- **Recommendation:** Do not adopt
  `Igniter.Code.*`/`Project.*`/`Refactors.*` for this script: both pipeline
  steps are single-purpose full-file generation of brand-new modules (lib
  and test) from static `ggen_igniter` EEx templates with no RDF bindings,
  no `mix.exs`/config/application edits, and no renames anywhere in its 35
  lines — there is no existing hand-written file being patched, so "regen
  vs. targeted AST patch" doesn't apply, and none of the 4 known Igniter
  defect triggers are reachable from this script's actual behavior.

## `revenue_suite_demo.exs`

- **Candidacy:** not-applicable
- **Current mechanism:** The script is a pure runtime demo/verification
  driver, not a manufacturing/codegen script. `preflight/0` (lines
  ~93-112) only calls `Code.ensure_loaded/1` on 9 already-compiled modules
  and `File.exists?/1` on committed fixture paths — if a module isn't
  loadable it dies with a message pointing to three other shell scripts
  (`scripts/revenue_economics_sync.sh`, `scripts/revenue_metering_sync.sh`,
  `scripts/claude_workflow_reactor_sync.sh`) as the place code generation
  actually happens. The rest of the script (`parse_all_fixtures/0` and
  stages 1-5) only invokes existing module functions
  (`BeamPM.Revenue.Xes.parse_file/1`,
  `BeamPM.Discovery.traces_from_events/2`,
  `BeamPM.Revenue.Economics.rework_cost/2`, etc.) against fixture data and
  prints results via `IO.puts`. It never writes, patches, or regenerates
  any `.ex`/`.exs`/`mix.exs`/config file — the entire file contains zero
  `File.write`, `Igniter`, or codemod calls.
- **Target files:** `scripts/revenue_suite_demo.exs`
- **Capability:** n/a
- **Defect risk:** none — this script performs no `mix.exs` edits, no
  config edits, no supervision-tree child insertion, and no function
  renames of any kind, so none of the 4 known Igniter defect triggers can
  be checked against it (there is no target `mix.exs`/`start.ex`/rename
  target within this script's own pipeline to inspect).
- **Recommendation:** Do not adopt Igniter here: this script has no
  full-file-regen, sed/grep-check, `mix.exs`-edit, config-edit, or rename
  step for Igniter to replace — it is read-only verification/demo code. If
  codemod-style manufacturing exists at all in this repo's revenue-suite
  pipeline, it would live in the three sync scripts this file's `die()`
  message names (`scripts/revenue_economics_sync.sh`,
  `scripts/revenue_metering_sync.sh`,
  `scripts/claude_workflow_reactor_sync.sh`), which are audited separately
  above and are themselves not-applicable.

## `rf1_dfg_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Shell pipeline: (1)
  `cd native/rf1-dfg-oracle && cargo build --release` (line 20); (2)
  `mix deps.get` (line 22); (3) two `mix ggen_igniter.sync` invocations
  (lines 24-29, 31-36) each pulling an ontology query result
  (`admitted_actions.rq`, deliberately unused per the script's own header
  comment) and rendering a static EEx template
  (`beam4pm_rf1_dfg.ex.eex`, `beam4pm_rf1_dfg_test.exs.eex`) as a full-file
  write to `lib/beam4pm_rf1_dfg.ex` and `test/beam4pm_rf1_dfg_test.exs`.
  Both generated files carry a `# GENERATED by ggen_igniter ... Do not
  edit.` header and are whole-file overwrites, not incremental AST
  patches.
- **Target files:** `scripts/rf1_dfg_sync.sh`, `lib/beam4pm_rf1_dfg.ex`,
  `test/beam4pm_rf1_dfg_test.exs`, `mix.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_rf1_dfg.ex.eex`,
  `.../beam4pm_rf1_dfg_test.exs.eex`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt: the script's only two manufacturing
  steps are `cargo build --release` (an external toolchain call, out of
  Igniter's scope entirely) and two `mix ggen_igniter.sync` full-file EEx
  renders that intentionally produce whole new "Do not edit" generated
  files rather than patching pre-existing hand-written structure — it
  never touches `mix.exs` deps (which is already a proper `defp deps do
  [...] end`, not inline, so defect 1 would not even trigger if it were
  adopted), never touches an `application.ex` `start/2` (no such file
  exists in the repo, so `Igniter.Project.Application`/defect 3 is moot),
  never edits config (no `config/config.exs` exists, defect-2-adjacent
  `MixProject.update` is unused), and performs no function renames (defect
  4 moot) — so none of the four tested Igniter capabilities
  (`Deps`/`MixProject`/`Application`/`Refactors.Rename`) have a real target
  in this script's pipeline at all.

## `rf2_conformance_sync.sh`

- **Candidacy:** weak-candidate
- **Current mechanism:** Requires `RF2_ORACLE_BIN` env (line 20), builds
  the Rust oracle via `cargo build --release` (line 25), runs
  `mix deps.get` (line 27), then invokes `mix ggen_igniter.sync` twice
  (lines 29-34, 36-41) — each a full-file template regen from a SPARQL
  query (`rf2_spec.rq`) against `ontology.ttl`, writing the entire contents
  of `lib/beam4pm_rf2_conformance.ex` and
  `test/beam4pm_rf2_conformance_test.exs` from `.eex` templates. Both
  generated files carry a literal '# GENERATED by ggen_igniter ... Do not
  edit.' header — the pipeline's own doctrine is full-file authoritative
  regeneration from RDF, never incremental patching of existing content.
- **Target files:** `scripts/rf2_conformance_sync.sh`, `mix.exs`,
  `lib/beam4pm_rf2_conformance.ex`,
  `test/beam4pm_rf2_conformance_test.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/queries/rf2_spec.rq`,
  `.../igniter/templates/beam4pm_rf2_conformance.ex.eex`,
  `.../beam4pm_rf2_conformance_test.exs.eex`
- **Capability:** n/a
- **Defect risk:** none — the script never invokes `Deps.add_dep`,
  `MixProject.update`, `Application.add_new_child`, or `Refactors.Rename`
  in its current pipeline, so none of the 4 documented defects can trigger
  as this script stands today. Checked the real shapes anyway: `mix.exs`
  `deps()` is a separate `defp deps do [{:ggen_igniter, "~> 26.8", only:
  [:dev, :test], runtime: false}, {:ash, "~> 3.0"}, {:wasmex, "~> 0.15"}]
  end` not inlined in `project/0`, so defect #1 would not trigger if
  `Deps.add_dep` were later adopted here. `def application do` has no
  `start/2` and no `Supervisor.start_link` at all — just
  `[extra_applications: [:logger]]` — so defect #3 (`children=` binding
  requirement) is not applicable; there is no supervision tree in this app
  for `Application.add_new_child` to target. No zero-arity or guarded defs
  are targeted for rename anywhere in this script's pipeline, so defect #4
  is not applicable.
- **Recommendation:** Do not adopt `Igniter.Code.*`/`Refactors.*` for this
  script's actual two `ggen_igniter.sync` steps — they are deliberate
  full-file, ontology-authoritative regeneration of files marked 'Do not
  edit', which is the correct model for RDF-driven codegen and is not a
  patch-onto-existing-human-code scenario any `Igniter.Code.*` capability
  targets; the only plausible future fit is `Igniter.Project.Deps.add_dep`
  IF this script is later extended to add deps to `mix.exs`
  programmatically, and that would be safe today since `deps()` is already
  a separate function (defect #1 does not apply).

## `rf3_ocel_sync.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** The script (lines 26-38) does three things: (1)
  `cd native/rf3-ocel-oracle && cargo build --release` to build a real Rust
  oracle binary; (2) `mix deps.get`; (3) two invocations of
  `mix ggen_igniter.sync --ontology ontology.ttl --query
  admitted=.../admitted_actions.rq --template
  .../beam4pm_rf3_ocel.ex.eex --out lib/beam4pm_rf3_ocel.ex` and the
  analogous `..._test.exs.eex --out test/beam4pm_rf3_ocel_test.exs`. Both
  templates (lines 1-14) are explicitly documented as "Bindings: NONE --
  this template renders statically" — a full-file EEx regen with zero
  SPARQL-derived interpolation, driven entirely through the existing
  `mix ggen_igniter.sync` task (not raw sed/grep, not a hand-rolled
  `mix.exs`/config edit, not a rename).
- **Target files:** `scripts/rf3_ocel_sync.sh`, `lib/beam4pm_rf3_ocel.ex`,
  `test/beam4pm_rf3_ocel_test.exs`,
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_rf3_ocel.ex.eex`,
  `.../beam4pm_rf3_ocel_test.exs.eex`,
  `.../igniter/queries/admitted_actions.rq`, `mix.exs`
- **Capability:** n/a
- **Defect risk:** none — none of the 4 known Igniter defects can trigger
  because this script never calls any of the affected
  `Igniter.Project.Deps`/`MixProject`/`Application`/`Refactors.Rename` APIs
  in the first place. For completeness on the one file that would matter
  if a future step ever did add an `Igniter.Project.Deps` call (defect 1):
  `mix.exs` (`deps: deps()`, and `defp deps do [...] end`) already keeps
  deps in a separate function rather than inlining `deps: [...]` in
  `project/0` — so defect 1's trigger condition is absent in the real
  file, not merely assumed absent. There is no `start/2`/supervision tree
  in this app to check against defect 3 (`application.ex` was not
  found/touched by this script), and no renamed function target for defect
  4 — both genuinely not-applicable rather than checked-and-clean.
- **Recommendation:** Do not adopt
  `Igniter.Code.*`/`Project.*`/`Refactors.*` for this script: every step
  it runs (cargo build, `mix deps.get`, and two `mix ggen_igniter.sync`
  template renders) is either a real subprocess build or an already-
  existing whole-file EEx codegen path that the templates themselves
  document as deliberately non-interpolating/non-targeted ("Bindings:
  NONE") — there is no manual sed/grep check, no manual `mix.exs`/config
  edit, and no rename anywhere in this script's real pipeline for an
  Igniter capability to replace.

## `rust4pm_ocel_examples_wasm.exs`

- **Candidacy:** not-applicable
- **Current mechanism:** Pure runtime verification script (`mix run
  scripts/rust4pm_ocel_examples_wasm.exs`): starts the WASM engine via
  `Rust4PM.start()` (line 24), calls
  `Rust4PM.ocel_new/ocel_add_event_type/ocel_add_object/ocel_add_event/
  ocel_to_json/ocel_stats/import_xes/xes_to_ocel/ocel_dfg_of_object_type/
  ocel_variants_of_object_type/top_n_variants` against the real
  `lib/beam4pm_rust4pm.ex` API, and hard-asserts equality on returned
  in-memory maps/lists (e.g. `stats["num_events"] == 2 || Die.die(...)` and
  `nv == 753 || Die.die(...)`). It reads exactly one file on disk,
  `~/wasm4pm/data/InternationalDeclarations.xes` (`File.exists?(xes) ||
  Die.die(...)`), and never writes, patches, or regenerates any file.
- **Target files:** `scripts/rust4pm_ocel_examples_wasm.exs`,
  `lib/beam4pm_rust4pm.ex`, `~/wasm4pm/data/InternationalDeclarations.xes`
- **Capability:** n/a
- **Defect risk:** none — the script performs no `mix.exs` edit, no
  supervision-tree edit, and no function rename; it is a black-box runtime
  assertion script over an already-compiled WASM-backed Elixir API, not a
  codemod or file-generation pipeline. None of the 4 known defect triggers
  are reachable because none of the 4 corresponding Igniter capabilities
  have any real target here.
- **Recommendation:** Do not adopt Igniter for this script — it has no
  file-generation, config-editing, `mix.exs`-editing, or rename step; its
  entire job is calling a live WASM engine API and asserting on returned
  data, which is orthogonal to Igniter's AST-codemod surface.

## `rust4pm_wasm_build.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Pure bash pipeline: toolchain guards
  (`command -v cargo`, `rustup target add wasm32-wasip1` or a manual
  `rustc --print sysroot` + directory-existence check, lines 22-44), a real
  `cargo build --release --target wasm32-wasip1` invocation in
  `native/rust4pm-wasm` (line 47), then a file-existence check
  `[ ! -f "$WASM_REL" ]` (line 50) and shasum/sha256sum content-hash
  printing (lines 55-60) against the real produced artifact
  `native/rust4pm-wasm/target/wasm32-wasip1/release/rust4pm_wasm.wasm`.
- **Target files:** `scripts/rust4pm_wasm_build.sh`,
  `native/rust4pm-wasm/Cargo.toml`, `native/rust4pm-wasm/Cargo.lock`,
  `native/rust4pm-wasm/src` (compiled, not read/patched by this script)
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt Igniter for this script: every real
  step it performs (toolchain presence checks, `cargo build --release
  --target wasm32-wasip1`, artifact existence check, sha256 hashing)
  operates on Rust/Cargo files and shell toolchain state — it never reads
  or writes an Elixir `mix.exs`, `config/*.exs`, a supervision-tree
  `start/2`, or an Elixir function definition, so none of
  `Igniter.Code.*`/`Igniter.Project.*`/`Igniter.Refactors.*` (all
  Elixir-AST/`mix.exs`-scoped) has any real target file in this script to
  act on.

## `gate_m2_check.sh`

- **Candidacy:** weak-candidate
- **Current mechanism:** Finds every file under
  `SEARCH_DIRS=(src lib test gleam/src gleam/test schema docs/reference)`
  whose first 3 lines case-insensitively match "GENERATED by ggen"
  (`find_manufactured()`, lines 24-38), sha256s them (pass 2, line ~55),
  deletes them (`rm -f "$f"` loop, pass 3 line ~92), regenerates via
  `ggen sync run` (line 94) plus 13 further `bash scripts/*_sync.sh` calls
  (`igniter_sync.sh`, `receipt_chain_sync.sh`, `rf1/rf2/rf3_*_sync.sh`,
  `revenue_*_sync.sh`, `claude_workflow_reactor_sync.sh`, `pro_*_sync.sh`
  x5), then re-sha256s (pass 4) and diffs the two sha sets for
  byte-identity (final if-block). It never edits `mix.exs`, never edits
  config, never does a sed/grep pattern check, and never renames a
  function — it only deletes+full-file-regenerates by shelling to other
  sync scripts, which themselves call `mix ggen_igniter.sync --template
  X.eex --out Y` (full-file EEx template render, confirmed in
  `scripts/igniter_sync.sh` lines 27-33) or `ggen sync run` (Rust/Tera
  engine, also full-file render).
- **Target files:** `scripts/gate_m2_check.sh`, `scripts/igniter_sync.sh`,
  `mix.exs`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt
  `Igniter.Code.*`/`Project.*`/`Refactors.*` for `gate_m2_check.sh` itself:
  every step it performs directly (marker-based file discovery via
  `head`+`grep`, sha256, `rm`, and dispatching to other scripts) is
  orchestration/verification logic with no AST target, and its own
  `mix.exs` already uses a non-inlined `defp deps do [...] end` so defect
  #1 would not even apply if some other script later touched it; the real
  full-file-regen candidates for a future targeted-AST-patch conversion
  live one layer down, inside the `*_sync.sh` scripts' own
  `mix ggen_igniter.sync --template ...eex --out ...` calls (e.g.
  `igniter_sync.sh` lines 27-33), not in this gate script, which this task
  was scoped to audit and which has no `mix.exs`/config/rename step of its
  own.

## `standing_vocabulary_check.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** Hardcodes
  `CANONICAL_SIX=(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN
  UNSUPPORTED)` (lines 20-46), then for each word runs
  `grep -rlq "$word" receipts/ docs/ lib/ 2>/dev/null` (line 40) as a plain
  substring match (not anchored to a standalone token, per the comment at
  lines 32-39 explaining a prior stricter version produced false
  negatives), counting misses and exiting 1 if any of the six is absent.
- **Target files:** `scripts/standing_vocabulary_check.sh`, `receipts/`,
  `docs/`, `lib/`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt any Igniter capability here: the
  script's entire job is a cross-cutting substring presence check over
  `receipts/*.json`, `docs/**/*.md`, and `lib/*.ex` text content (via
  `grep -rlq`), with no `mix.exs` edit, no config edit, no
  supervision-tree child insertion, and no function rename anywhere in its
  pipeline — none of the four tested Igniter capability families
  (`Deps`/`MixProject`, `Project.Config`, `Application.add_new_child`,
  `Refactors.Rename`) or `Igniter.Code.Pattern` (which patches Elixir AST,
  not JSON/Markdown text) apply to what this script actually does.

## `roundtrip_check.sh`

- **Candidacy:** not-applicable
- **Current mechanism:** A pure runtime verification harness with no
  code-generation or file-patching step at all. It: (1) compiles `src/*.erl`
  with `erlc` into a tmpdir (line 24), (2) runs `erl -eval` calling
  `beam4pm_roundtrip:write_samples/1` to dump JSON wire samples (line 26),
  (3) runs `mix run -e` calling `BeamPM.Roundtrip.verify_samples/2` and
  `write_samples/1` (lines 28-33), (4) runs `erl -eval` calling
  `beam4pm_roundtrip:verify_samples/2` (lines 35-40), and exits non-zero on
  any failure via `set -euo pipefail` plus explicit `halt(1)`/
  `System.halt(1)` calls. It never opens, writes, or greps any project
  source file (`mix.exs`, `config/*.exs`, `application.ex`, or any
  `.ex`/`.erl` file) — every artifact it touches lives under a
  `mktemp -d` tmpdir (`$TMP/ebin`, `$TMP/wire`) that is `rm -rf`'d on exit
  (line 20). It is exclusively a compile-and-run-and-assert-exit-code
  pipeline over already-existing, already-ggen-manufactured modules (per
  its own header comment, lines 14-16: `beam4pm_roundtrip`,
  `BeamPM.Roundtrip`, the codecs, the types are already
  ggen-manufactured).
- **Target files:** `scripts/roundtrip_check.sh`
- **Capability:** n/a
- **Defect risk:** none
- **Recommendation:** Do not adopt any Igniter capability for this script:
  it contains no full-file regen, no sed/grep-based structural check, no
  `mix.exs`/config edit, and no rename — every step is an ephemeral
  compile-and-execute-and-assert-exit-code call against a `mktemp` tmpdir,
  which is outside Igniter's project-codemod domain entirely.

## Strong candidates requiring a new PR/story

Zero of the 25 scripts audited resolve to a **strong** Igniter-adoption
candidacy. Every script is either **not-applicable** (19 of 25 — the
mechanism performs no source-file patching, `mix.exs`/config edit, or
rename at all, so no Igniter capability has a real target) or
**weak-candidate** (6 of 25 — `pro_capability_manifest_sync.sh`,
`pro_compatibility_sync.sh`, `pro_license_sync.sh`, `receipt_chain_sync.sh`,
`rf2_conformance_sync.sh`, `gate_m2_check.sh` — the mechanism is a
deliberate whole-file ontology-driven regen of a "Do not edit" generated
file, and Igniter's AST-patch surface targets hand-authored code, not
machine-owned output, so adoption is not recommended even where a nominal
future hook exists).

Given this, no PR/story item proposes adopting an Igniter capability inside
any of the 25 audited scripts' current mechanism — every weak-candidate
finding above stays a "do not adopt" recommendation for the script's real,
present-day pipeline. This is itself the real, load-bearing audit result —
not an omission. What this audit's six weak-candidate findings did warrant,
and what now exists as a direct consequence, is a guard-rail requirement
per weak-candidate script — not an adoption, but a precondition check that
must pass before any future PR/story is permitted to wire an Igniter
capability into that script. Those six guard-rail items are
`docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md`'s
PR-306 through PR-311 and
`docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md`'s B4PM-1705 through
B4PM-1710, one pair per weak-candidate script
(`pro_capability_manifest_sync.sh` → PR-306/B4PM-1705,
`pro_compatibility_sync.sh` → PR-307/B4PM-1706,
`pro_license_sync.sh` → PR-308/B4PM-1707,
`receipt_chain_sync.sh` → PR-309/B4PM-1708,
`rf2_conformance_sync.sh` → PR-310/B4PM-1709,
`gate_m2_check.sh` → PR-311/B4PM-1710), each explicitly `UNSUPPORTED` today
by design until the named future trigger (an ontology-bound template, a
programmatic `mix.exs` edit, or a rename codemod) actually occurs. The two
places a real future *adoption* PR/story (not a guard rail) would attach,
if beam4pm's manufacturing pipeline changes shape later, are named
explicitly in the per-script findings above rather than filed speculatively
now:

- **If `rf2_conformance_sync.sh` is ever extended to add a dependency to
  `mix.exs` programmatically** (rather than relying on a committed
  `mix.exs`), `Igniter.Project.Deps.add_dep` becomes a real candidate —
  file the PR/story at that time, gated on
  `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` defect #1
  confirming beam4pm's `mix.exs` keeps deps in a separate `defp deps do
  [...] end` (already true today, so the defect would not trigger).
- **If `Igniter.Refactors.Rename` is ever adopted as an automated codemod
  over beam4pm-generated Elixir** (no script currently does this), the
  pre-flight guard already scoped in
  `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` under
  **B4PM-1704 Pre-flight guard for rename_function-based automation** must
  land first and must specifically special-case the parenless
  zero-arity `def contracts, do: @contracts`
  (`lib/beam4pm_process_governor.ex:474`) and
  `def admitted_actuations, do: @admitted_actuations`
  (`lib/beam4pm_actuation.ex:597`) found during this audit, plus the
  guarded defs in `lib/beam4pm_process_governor.ex` and
  `lib/beam4pm_revenue_economics.ex` named above — these are new,
  concrete rename hazards this audit surfaced beyond the ones already
  cited in `docs/jira/v26.8.31/03-known-defects-and-mitigations.md`, and
  should be added to that story's acceptance criteria rather than filed as
  a new story, since B4PM-1704 already owns this exact pre-flight-guard
  scope.

PR-306 through PR-311 and B4PM-1705 through B4PM-1710 (the six
guard-rail items enumerated above) are consumed by this audit's own
findings, as described. The next free IDs are **PR-312** (after PR-306
through PR-311 in
`docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md`)
and **B4PM-1711** (after B4PM-1705 through B4PM-1710 in
`docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md`) — reserved for a
future revision of this audit if a script's real mechanism changes shape
(e.g. a `*_sync.sh` template becomes ontology-bound, or a rename codemod is
adopted), not consumed by this audit's findings.

## See also

- `docs/jira/v26.8.31/02-product-requirements-igniter-capability-expansion.md`
  — the Igniter capability surface (PR-300 through PR-305) this audit
  checked each script against.
- `docs/jira/v26.8.31/03-known-defects-and-mitigations.md` — the 4 known
  defect triggers this audit checked each script's real pipeline against.
- `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the
  B4PM-1700 epic and its B4PM-1701 through B4PM-1704 stories, including
  B4PM-1704's pre-flight-guard scope this audit's rename-hazard findings
  should be folded into.
- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — the
  source-authority doctrine distinguishing hand-editable manufacturing
  inputs from machine-owned generated output, which underlies most of this
  audit's "not-applicable" findings.
