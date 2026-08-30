# Examples

Two small, real, runnable demo scripts exist here, one per BEAM language
projection currently manufactured:

- `examples/erlang/ocel_log_demo.erl` — an escript building three real
  `ocel_event` records via `beam4pm_types:new_ocel_event/1`.
- `examples/elixir/ocel_log_demo.exs` — the same demo against
  `BeamPM.Types.OcelEvent.new/1`.

Both are real exercises of the ggen-manufactured `beam4pm_types` module (see
each subdirectory's own `README.md` for exact invocation) — not stubs, not
mocks. Each has been run for real in this environment and produces the
output documented in its own README.

## What these demos are, and are not

They are small, single-record-type demonstrations that a constructor works
end to end. They are **not**:

- An end-to-end process-mining workflow (build a log, derive a
  directly-follows graph, check an alignment) — no discovery/conformance
  algorithm exists yet to demonstrate.
- Gleam or Ash examples — neither projection has been attempted yet (Gleam:
  `UNSUPPORTED`, toolchain unavailable in this environment).
- A `playground/` — see `playground/README.md` for what that gate still
  requires.

For exhaustive validation of every one of the 31 admitted record types (not
just `ocel_event`), see the generated test suites instead:

- `test/beam4pm_types_tests.erl` — 62 of the 94 EUnit tests
  (2 per record type: a valid-construction test and a missing-required-field
  test), the remaining 32 come from `beam4pm_types_manifest_tests.erl`
  (1 count test + 31 per-record field-list tests).
- `test/beam4pm_types_test.exs` and
  `beam4pm_types_manifest_test.exs` — the same split for the 95 ExUnit tests.

Those are ggen-manufactured unit tests validating schema-level correctness
across every record type; the two demo scripts above are illustrative
integrator-facing examples for one record type each.

## What a fuller examples/ would still need

Runnable, generated per-language programs that use the manufactured
`beam4pm_types` (and, once they exist, discovery/conformance/planning)
modules the way a real integrator would: build an OCEL event log from
several related events and objects, derive a directly-follows graph from a
list of traces, check an alignment — on both the Erlang and Elixir
projections (and Gleam, once that toolchain gate is unblocked). None of this
exists yet; the two demos here are a real but narrow starting point, not a
substitute for it.

## See also

- `examples/erlang/README.md`, `examples/elixir/README.md` — exact
  invocation instructions for each demo.
- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — manufacturing
  acceptance crowns (`ERLANG_EXAMPLES_ALIVE`, `GLEAM_EXAMPLES_ALIVE`, etc.)
  and the generated-repository-surfaces layout.
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — the source-authority doctrine for
  manufactured output.
- `playground/README.md` — the sibling placeholder for the `playground/` gate.
