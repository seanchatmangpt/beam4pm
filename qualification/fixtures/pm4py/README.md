# pm4py Canonical Fixtures (running-example)

Byte-identical copies of two canonical pm4py test fixtures, used by the
rust4pm-wasm-in-BEAM port of three pm4py examples
(`scripts/pm4py_examples_wasm.exs`) and by
`test/beam4pm_rust4pm_test.exs`. Copied 2026-08-30.

## Provenance

- Upstream source: the pm4py checkout at `/Users/sac/chatmangpt/pm4py`,
  files `tests/input_data/running-example.xes` and
  `tests/input_data/running-example.pnml`.
- Upstream license: pm4py is AGPL-3.0; these fixtures ship with its test
  suite. They are data fixtures (an event log and a Petri net), copied for
  qualification only.
- Byte-identical to upstream, verified by `cmp` and SHA-256 at copy time:
  - `running-example.xes`
    `663cd7b1da01cd024291e527a46079e0e7676fcf3a81ca8f5dee070b073c5df9`
  - `running-example.pnml`
    `4b4ce13c752978c20f8265402cd69a302050f71ab95e717145ec8e8a1427417a`

## Why copied instead of referenced in place

Repo tests and scripts resolve fixtures via repo-root-relative
`Path.expand("qualification/fixtures/...")` — the same convention as RF1's
checked-in copies of the wasm4pm canonical datasets
(see `test/beam4pm_rf1_dfg_test.exs`). A path into a sibling checkout would
make `mix test` depend on an uncommitted external tree.

## Contents

- `running-example.xes` — 6 traces (cases 3, 2, 1, 6, 5, 4), 8 activities,
  6 variants (each of the 6 traces is distinct). First `<trace>` in the file is case `"3"` (9 events).
- `running-example.pnml` — the matching Petri net with initial/final
  markings; it perfectly fits the log (all alignments cost 0 under the
  standard cost function).

## See Also

- `scripts/pm4py_examples_wasm.exs` — the three pm4py example ports that
  consume these fixtures
- `docs/reference/rust4pm-wasm-beam.md` — the wasm ABI these run through
- `/Users/sac/chatmangpt/pm4py/examples/alignment_discounted_a_star.py`,
  `examples/activities_to_alphabet.py`, `examples/activity_position.py` —
  the upstream examples being ported
