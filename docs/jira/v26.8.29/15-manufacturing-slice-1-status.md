# beam4pm v26.8.29 — Manufacturing Slice 1 Status

Last updated: 2026-08-29.

Status: `PARTIAL_ALIVE[FIRST_SLICE_GGEN_ONLY_ERLANG_ELIXIR_ALIVE]` — a first
bounded manufacturing slice is real and independently re-verified below. No
release crown, provider crown, or RevOps stage is earned by this slice.

## Post-swarm update (same day, 2026-08-29) — read this before the numbers below

Everything below this point was written against the **original 8-record-type
slice** (commit `2ad3f16`) and is left exactly as authored, as the historical
record of that pass. A same-day 40-agent swarm then added **23 more admitted
record types** (31 total), 4 more pack templates (JSON Schema, a generated
Markdown reference, and Erlang/Elixir reflection manifests with their own
tests), and repo scaffolding (README, CONTRIBUTING, examples/, playground/,
CI workflow, Makefile/Justfile, docs). Every numeric claim below
("8 `bpm:RecordType` individuals", "16/16 EUnit", "16/16 ExUnit") describes
that earlier, smaller state and is now superseded by:

- **31** admitted `bpm:RecordType` individuals in `ontology.ttl`
- **94/94** EUnit tests passing (`rebar3 eunit`, real Erlang/OTP 28.3.1)
- **95/95** ExUnit tests passing (`mix test`, real Elixir 1.19.5)
- `GATE M2` (deterministic reprojection) re-verified at the 31-record scale:
  full `generated/` deletion + `ggen sync run` regeneration produced
  byte-identical output, confirmed via `sha256sum` before/after
- The submodule pin moved to ggen-marketplace commit `dfa8cb42c` (adds the 4
  new pack templates)

The gate-by-gate table further down and its `M0`/`M4` counts are otherwise
unaffected in kind (still no examples exercising real algorithmic behavior
beyond a trivial demo, still no Gleam/Ash, still no cross-language roundtrip,
still no `BEAM4PM_GGEN_ONLY_ALIVE` crown) — only the record/test counts
changed. See the swarm's own receipt for full detail once written; as of this
edit it had not yet been committed.

### Adversarial verification pass (same day) — bugs fixed and known limitations disclosed

A second, 10-agent adversarial pass read the real swarm output (not just the prompts
that produced it) and found real, since-fixed defects: `k8s_object_ref.namespace` was
wrongly required (cluster-scoped Kubernetes kinds have no namespace — now optional);
`beam4pm_types.erl` declared record types without `-export_type`, producing real
dialyzer "Unknown types" errors for any external caller — fixed; the JSON Schema
template emitted no "GENERATED... Do not edit" marker, unlike every other template in
the pack — fixed; both EUnit test templates redundantly `-export`ed their own
auto-exported `_test/0` functions, a real warning that would become a hard failure
under `warnings_as_errors` — fixed; the pack's own `ontology.ttl` declared
`bpm:fieldRequired`'s range as `xsd:boolean` while every template compares it as a
plain string — fixed to `xsd:string`. Several documentation files (`.github/pull_request_template.md`
copy-pasted from a different repo, `examples/README.md` falsely claiming
`examples/erlang`/`examples/elixir` didn't exist, `playground/README.md` misattributing
the current 31-record count to an 8-record receipt, the pack's own README documenting
only 4 of 11 templates, the new-record-type issue template's worked example using
values that violate the pack's own admission gates) were also found stale or wrong and
corrected in place.

**Known limitations disclosed but not fixed in this pass** (real, verified, deliberately
left as future work rather than rushed):

- All 31 Erlang/Elixir constructors silently accept and drop unknown/extra map keys
  instead of rejecting them — a mistyped or schema-drifted field name is never surfaced.
- Neither language's constructor performs runtime value-type checking — a `-spec`/`@type`
  of `integer()` does not stop a caller from passing a string; only field *presence* is
  validated, not field *type*.
- `event_type` and `object_type` (and, more narrowly, `dfg_edge` vs. `heuristic_arc`)
  generate structurally identical shapes with no discriminant, so a value built for one
  is silently accepted by the other's constructor.
- `alignment_move.move_type`'s four-value enum (`sync | model | log | silent`) conflates
  move category with transition visibility — a `silent` move is really a `model` move on
  an unlabeled transition, not a mutually-exclusive fourth category. Fixing this properly
  means a real schema change (e.g. splitting into a category field plus a boolean/visibility
  field), deferred rather than done hastily under this pass's time budget.
- `ocel_attribute` and `object_attribute_change` are two overlapping, non-interoperable
  shapes for a similar underlying concept (a time-varying object attribute); their doc
  text was tightened but the shapes themselves were not unified.
- Generated "all fields present" tests assert only `{:ok, _}` / `{ok, _}`, never that
  individual field values were actually assigned correctly — a codegen defect that
  swapped or dropped a key would not be caught by the generated tests as they exist today.
- `beam4pm_types_manifest:fields/1`'s catch-all clause returns `[]` for an unknown record
  name, making it indistinguishable from a record that legitimately has zero fields (none
  currently do, but the ambiguity exists in the function's contract).

None of these are release-gate-blocking for the `PARTIAL_ALIVE` standing already claimed
above; they are named here so a future pass inherits an accurate map rather than
rediscovering them.

## Purpose

This is the Measure-phase status report for beam4pm's first manufacturing
slice, checked gate-by-gate against `docs/jira/v26.8.29/11-release-gates-receipts.md`.
Every claim below is either a citation to a receipt already on disk or a
command this report's author re-ran directly against the real repository
during authoring, per that document's Chicago execution protocol and this
project's standing vocabulary (`UNKNOWN` / `PARTIAL_ALIVE` / `ALIVE` /
`BLOCKED` / `UNSUPPORTED`). No PI/marketplace/RevOps claim below is inferred
from planning prose; those layers have no executable evidence yet, and are
reported as `UNKNOWN` on that basis alone.

## Scope of "slice 1"

Slice 1 is exactly: 8 admitted `bpm:RecordType` individuals
(`ocel_event`, `ocel_object`, `ocel_relationship`, `dfg_edge`, `petri_place`,
`petri_transition`, `petri_arc`, `alignment_move`) manufactured via the
`beam4pm-process-model-pack` into Erlang and Elixir data structures plus
validating constructors. It is not the full beam4pm/beam4pm_pro product
described elsewhere in `docs/jira/v26.8.29/`, and it is not process-mining
behavior — no directly-follows-graph discovery, no Petri-net replay, no
conformance/alignment computation exists yet. This scope statement matches
`receipts/2026-08-29-first-ggen-manufactured-slice.json` and `README.md`.

## Repository identity as of this report

- Repository: `/Users/sac/beam4pm`, branch `main`, up to date with `origin/main`.
- Head commit: `2ad3f165252d26b7afce6ca98bfe56b1b5cf695f`,
  "feat: first real ggen-manufactured slice (8 process-mining record types)",
  2026-08-29 19:00:50 -0700.
- Submodule `vendor/ggen-marketplace` pinned at
  `379f324715981eafc2a37b483da37bbf4629231b` (`v26.8.10-7906-g379f32471`),
  verified via `git submodule status`.
- `ggen.lock` pack content hash:
  `blake3:5b9360291e30f78b6f568f56f0210746458a726a7db67922ebe79865ea59490b`.
  Note: the committed receipt's `manufacturing_pack.commit` field
  (`e79e39ba4c4b6ac9092423d5fc181c05cc8e22d6`) does not match the submodule
  pin actually checked out at report time (`379f324715981eafc2a37b483da37bbf4629231b`).
  This is a discrepancy in the receipt's own metadata, not in the manufacturing
  result — the `ggen.lock` content hash above is what this report treats as
  ground truth for "which pack version actually ran."
- Untracked, uncommitted files present on disk at report time, additional to
  the committed slice: `.github/workflows/ci.yml`, `Justfile`, `Makefile`,
  `README.md`, `examples/`. These were verified directly (see GATE M4 below)
  and are real, but are not yet part of any commit — `git status --short`
  shows all five as `??`.
- Toolchains actually present on this machine and used for verification:
  `ggen 26.8.18`, `rebar 3.26.0` on `Erlang/OTP 28 Erts 16.2`
  (`/Users/sac/.erlmcp/otp-28.3.1`), `Elixir 1.19.5 (compiled with Erlang/OTP 28)`.
  `gleam` is absent (`command not found`) — see GATE M3/Gleam below.

## Manufacturing gates (M0–M6)

### GATE M0 — canonical input admitted: `ALIVE`

`ontology.ttl` contains 8 `bpm:RecordType` individuals built from the
`beam4pm-process-model-pack`'s vocabulary, each with named, typed, ordered
fields and explicit `bpm:fieldRequired` string literals. The pack ships two
SHACL/SPARQL admission gates
(`vendor/ggen-marketplace/packs/beam4pm-process-model-pack/gates/010_required.rq`,
`020_field_type_enum.rq`) and `ggen sync run`'s pipeline includes an explicit
`pipeline.validate` stage that this report re-ran and observed complete with
exit code 0 (see GATE M1 command output below — same invocation covers both
gates). No privileged source exception was invoked; all authored inputs
(`ontology.ttl`, `ggen.toml`, `rebar.config`, `mix.exs`, `src/beam4pm.app.src`)
are documented, in `README.md` and `generated/README.md`, as legitimate
manufacturing-input scaffolding, not domain source.

### GATE M1 — manufacture succeeds: `ALIVE`

Re-run live during this report (not quoted from the old receipt alone):

```sh
$ ggen sync run
...
{
  "written": [
    "generated/erlang/src/beam4pm_types.erl",
    "generated/elixir/lib/beam4pm_types.ex",
    "generated/elixir/test/beam4pm_types_test.exs",
    "generated/elixir/test/test_helper.exs",
    "generated/erlang/test/beam4pm_types_tests.erl"
  ],
  "skipped": [],
  "graph_hash_hex": "619b8ae725cae59cc6c6ebc521e7f2a8fafd70584164376d36718167a0bc3237",
  ...
}
```

5/5 intended artifacts written, `graph_hash_hex` matches the committed
receipt's value exactly, exit code 0.

### GATE M2 — deterministic reprojection: `ALIVE`

Independently reproduced during this report's authoring, not just cited from
the prior receipt:

1. `shasum -a 256` over the 5 files under `generated/erlang` and
   `generated/elixir` — captured as "before."
2. `rm -rf generated/erlang generated/elixir`.
3. `ggen sync run` (output above).
4. `shasum -a 256` over the same 5 paths again — captured as "after."

Before/after hashes for all 5 files were byte-for-byte identical:

| file | sha256 |
| --- | --- |
| `generated/elixir/lib/beam4pm_types.ex` | `91ae788ce47a7a39a6bd9bcba6a336c0e3f8c410ccb1ec641e80210bc231a81a` |
| `generated/elixir/test/beam4pm_types_test.exs` | `44418625ea9eaceef5e3d0c39b696b8e56a37a0acbf59006f22f937be9acd27b` |
| `generated/elixir/test/test_helper.exs` | `a94f8490c4a5702deb00eca2c4626776318d3b92a9077eca878542c712635ed7` |
| `generated/erlang/src/beam4pm_types.erl` | `24616889fb061996839cda8a6da1a95c9fbb70744b32291f328118d8884b5f48` |
| `generated/erlang/test/beam4pm_types_tests.erl` | `acc26b3239789c94531e1fa115a01495ab366f00a7777fde6d7a2fdffd6c52be` |

This matches the committed receipt's `gate_m2_deterministic_reprojection`
claim and closes it with a second, independent execution.

### GATE M3 — compile/type verification: `ALIVE` (Erlang, Elixir only)

Re-run live:

```sh
$ rebar3 compile          # clean
$ rebar3 eunit
All 16 tests passed.

$ mix compile --warnings-as-errors   # clean, zero warnings
$ mix test
Finished in 0.03 seconds (0.03s async, 0.00s sync)
16 tests, 0 failures
```

16/16 EUnit tests pass on real `Erlang/OTP 28.3.1`; 16/16 ExUnit tests pass on
real `Elixir 1.19.5`. Both are the 8 record types × {valid-construction,
missing-required-field} cases. Zero mocks, zero stubs — the tests call the
generated `new_<type>/1` / `<Type>.new/1` constructors directly.

Gleam is explicitly out of scope for this gate: `which gleam` returns nothing
and `gleam` is not an installed command on this machine. No Gleam source was
generated, attempted, or claimed. Standing: `UNSUPPORTED` (toolchain
unavailable), not `BLOCKED` and not silently skipped.

Ash/Elixir-Ash projection: not attempted. No Ash resource files exist
anywhere under `/Users/sac/beam4pm` (only unrelated branch-ref names inside
the vendored `ggen-marketplace` submodule's own `.git/modules` metadata, which
are not part of this project). Standing: `UNKNOWN`.

### GATE M4 — executable examples: `PARTIAL_ALIVE`

The gate as defined requires "Erlang and Gleam examples execute actual
process-mining/process-intelligence behavior." What actually exists, verified
by direct execution during this report:

```sh
$ mix run examples/elixir/ocel_log_demo.exs
Built 3 OcelEvent structs via BeamPM.Types.OcelEvent.new/1:
  e-1001 :: PlaceOrder
  e-1002 :: PackItems
  e-1003 :: ShipOrder
```

This is real, executing code against the real generated
`BeamPM.Types.OcelEvent` module — not a mock. But it is only a trivial demo:
it builds three struct instances through a validating constructor and prints
them. There is no directly-follows-graph discovery, no Petri-net firing/
replay, no conformance-checking alignment computation — none of the
process-mining behavior the gate names. It is also Elixir-only: there is no
Erlang example and no Gleam example (Gleam is `UNSUPPORTED` per GATE M3
above), so neither of the two languages the gate explicitly names has a
qualifying example. `examples/`, `Justfile`, `Makefile`, `.github/`, and the
top-level `README.md` that documents this example are all currently
uncommitted (`git status --short` shows them `??`) — real on disk, not yet
part of the repository's history.

Standing: `PARTIAL_ALIVE` — real execution observed, gate closure incomplete
on both the "process-mining behavior" and "Erlang and Gleam" requirements.

### GATE M5 — cross-language identity: `UNKNOWN` (not attempted)

No round-trip/codec tooling exists between the Erlang and Elixir projections
(or any third representation) anywhere in the repository. Nothing to
falsify or confirm; standing is `UNKNOWN`, not `BLOCKED`.

### GATE M6 — playground: `UNKNOWN` (not attempted)

No `playground/` directory exists anywhere under `/Users/sac/beam4pm`.
Standing is `UNKNOWN`.

## Crown: `BEAM4PM_GGEN_ONLY_ALIVE`

**Not earned.** Per `11-release-gates-receipts.md`, this crown requires
M0 through M6 closed for the exact qualified release subject. M0–M3 are
`ALIVE` for Erlang and Elixir only; M4 is `PARTIAL_ALIVE` at best and fails
its own "Erlang and Gleam" language requirement outright; M5 and M6 are
`UNKNOWN`; Gleam itself is `UNSUPPORTED` on this machine. A checkpoint is not
a crown — this slice is a real, verified checkpoint on M0–M3, nothing more.

## Source-lock gates

**Normal source change: compliant.** Every file under `generated/` is
ggen-manufactured output attributable to the `beam4pm-process-model-pack`
running against admitted `ontology.ttl` instance data (verified via GATE M1/
M2 reproduction above). No privileged source exception was declared, used, or
required for this slice — the hand-authored files (`ontology.ttl`,
`ggen.toml`, `rebar.config`, `mix.exs`, `src/beam4pm.app.src`) are documented
manufacturing-input scaffolding, not domain source, per `README.md`'s
source-authority doctrine. Zero manufacturing debt from this gate for this
slice.

## Process-intelligence gates (PI0–PI8): `UNKNOWN`, all of them

No observation ingestion, topology reconstruction, correlation, process
inference, process twin, intelligence/metric proof, formal-model projection,
planning, or BRCE actuation exists anywhere in `/Users/sac/beam4pm`. The only
artifacts manufactured so far are 8 static data-type definitions and their
field-presence validators — no algorithm over them has been written or run.
`08-process-intelligence-roadmap.md` describes an intended roadmap; a roadmap
document is planning prose, not an evidence object, and is not treated as
progress against any PI gate here.

- PI0 Observation ingestion — `UNKNOWN`
- PI1 Topology — `UNKNOWN`
- PI2 Correlation — `UNKNOWN`
- PI3 Process inference — `UNKNOWN`
- PI4 Process twin — `UNKNOWN`
- PI5 Intelligence — `UNKNOWN`
- PI6 Formal projection — `UNKNOWN`
- PI7 Planning — `UNKNOWN`
- PI8 BRCE — `UNKNOWN`

## Air-gap gates: `UNKNOWN`

None of the ten `AIRGAP_ALIVE` steps (offline install, signature/SBOM/
provenance verification, disconnected startup, local observation, local
inference/display, local persistence, diagnostic receipt, offline update,
rollback, offline entitlement reconciliation) have been attempted. No air-gap
configuration flag or mechanism exists in this repository at all — not even
the "insufficient flag" case named in `11-release-gates-receipts.md`, since
there is no beam4pm_pro deployment surface yet to flag.

## Marketplace gates (MP0–MP9): `UNKNOWN`, all providers

No seller account, listing, purchase path, entitlement handling, deployment
activation, value-path execution, billing/metering reconciliation, private
offer, lifecycle event, or failure/replay path exists for AWS, Microsoft, or
GCP marketplaces. `04-cloud-marketplace-revops.md` describes the intended
operating model and is explicitly labeled there as "planning inputs, not
proof that beam4pm is listed or transactable." That self-labeling is
accurate and is preserved here.

- `AWS_MARKETPLACE_ALIVE` — `UNKNOWN`
- `MICROSOFT_MARKETPLACE_ALIVE` — `UNKNOWN`
- `GCP_MARKETPLACE_ALIVE` — `UNKNOWN`
- `BEAM4PM_PRO_MARKETPLACE_REVOPS_ALIVE` — `UNKNOWN` (requires all three
  provider crowns plus product/RevOps closure; none of the prerequisites are
  closed)

## RevOps gates (R0–R8): `UNKNOWN`, all of them

No qualified customer mission, deployed proof, customer-specific value
finding, commercial proposal, contracted agreement, adoption, expansion, or
renewal event exists. `beam4pm_pro` does not exist as code (stated plainly in
`README.md`: "it does not exist as code yet"), so R1 (technical admission)
onward has no subject to execute against.

- R0 Qualified — `UNKNOWN`
- R1 Technical admission — `UNKNOWN`
- R2 Proof running — `UNKNOWN`
- R3 Value proven — `UNKNOWN`
- R4 Commercial proposed — `UNKNOWN`
- R5 Contracted — `UNKNOWN`
- R6 Adopted — `UNKNOWN`
- R7 Expansion — `UNKNOWN`
- R8 Renewal — `UNKNOWN`

## Summary table

| Gate / crown | Standing | Real evidence cited above |
| --- | --- | --- |
| M0 canonical input admitted | `ALIVE` | 8 `bpm:RecordType` individuals; pack admission gates; validate stage exit 0 |
| M1 manufacture succeeds | `ALIVE` | `ggen sync run`, 5/5 files written, exit 0 (re-run live) |
| M2 deterministic reprojection | `ALIVE` | sha256 identical before/after full delete+regenerate (re-run live) |
| M3 compile/type verification | `ALIVE` (Erlang, Elixir) | `rebar3 eunit` 16/16, `mix test` 16/16 (both re-run live) |
| M3 — Gleam | `UNSUPPORTED` | `gleam` binary absent on this machine |
| M3 — Ash | `UNKNOWN` | no Ash resources exist in this repository |
| M4 executable examples | `PARTIAL_ALIVE` | real Elixir demo script executed live; struct construction only, not process-mining behavior; no Erlang/Gleam example |
| M5 cross-language identity | `UNKNOWN` | not attempted, no tooling exists |
| M6 playground | `UNKNOWN` | no `playground/` directory exists |
| `BEAM4PM_GGEN_ONLY_ALIVE` | **not earned** | M4–M6 incomplete/unknown, Gleam unsupported |
| Source-lock gates | compliant | all generated output attributable to ggen; no privileged exception used |
| PI0–PI8 | `UNKNOWN` (all) | no process-intelligence code exists |
| Air-gap gates | `UNKNOWN` (all) | no air-gap mechanism exists |
| MP0–MP9 (all providers) | `UNKNOWN` (all) | no marketplace layer exists |
| RevOps R0–R8 | `UNKNOWN` (all) | `beam4pm_pro` does not exist as code |

## Replay instructions

From a clean checkout with `--recurse-submodules`:

```sh
cd beam4pm
make submodules   # git submodule update --init --recursive
make sync         # rm -f ggen.lock; ggen sync run --dry-run; ggen sync run
make test         # rebar3 eunit; mix test
```

For an independent GATE M2 re-check:

```sh
find generated/erlang generated/elixir -type f | sort | xargs shasum -a 256
rm -rf generated/erlang generated/elixir
ggen sync run
find generated/erlang generated/elixir -type f | sort | xargs shasum -a 256
# diff the two outputs; expect zero differences
```

## Known limitations (stated, not hidden)

- This slice manufactures data types and field validators only. No
  process-mining algorithm (discovery, conformance checking, alignment
  computation) exists.
- Gleam projection is unattempted because the toolchain is not installed
  locally, not because it was tried and failed.
- The committed receipt's stated pack commit SHA does not match the
  submodule's actual pinned commit; the `ggen.lock` content hash is the more
  reliable identity for "what actually ran" and is what this report used.
- `examples/`, `Justfile`, `Makefile`, `.github/workflows/ci.yml`, and the
  top-level `README.md` are real and were exercised directly for this report,
  but are uncommitted at report time.
- The repository's own CI workflow (uncommitted) documents a known gap in its
  own comments: it does not install a `ggen` binary on the runner, so its
  determinism-check step is expected to fail loudly and is wrapped in
  `continue-on-error: true` until that is fixed.

## See Also

- `docs/jira/v26.8.29/11-release-gates-receipts.md` — the gate/crown/standing
  vocabulary this report is checked against.
- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — source-lock
  and manufacturing doctrine referenced under "Source-lock gates" above.
- `docs/jira/v26.8.29/08-process-intelligence-roadmap.md` — the roadmap this
  report treats as planning prose, not evidence, for the PI gates.
- `docs/jira/v26.8.29/04-cloud-marketplace-revops.md` — the planning inputs
  this report treats as non-proof for the marketplace gates.
- `receipts/2026-08-29-first-ggen-manufactured-slice.json` — the committed
  receipt this report independently re-verified (GATE M2, GATE M3) and
  extended (GATE M4).
- `README.md` — current top-level project status statement (uncommitted at
  report time; consistent with this report's findings).
