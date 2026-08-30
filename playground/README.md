# Playground

This directory does not contain a playground yet. This README is the only file
here. `GATE PLAYGROUND_ALIVE` — one of the manufacturing acceptance crowns listed
in `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — is not met.

## Current state (2026-08-29)

- No files exist under `playground/` beyond this README.
- `receipts/2026-08-29-first-ggen-manufactured-slice.json` lists
  `"examples/ and playground/ (release gates in docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md)"`
  explicitly under `not_yet_attempted`. That receipt's own claim ceiling
  covers only the original 8 record types from the first manufacturing pass
  (`ocel_event`, `ocel_object`, `ocel_relationship`, `dfg_edge`,
  `petri_place`, `petri_transition`, `petri_arc`, `alignment_move`); a
  same-day 40-agent swarm later added 23 more, for **31** admitted
  `bpm:RecordType` data types total as of this writing (see
  `generated/docs/beam4pm_types_reference.md`, itself ggen-generated, for
  the current, exact, full list) — manufactured as Erlang and Elixir
  structs/records with field-presence validation, under
  `generated/erlang/src/beam4pm_types.erl` and `generated/elixir/lib/beam4pm_types.ex`.
  Either way, this remains narrower than a playground.
- Zero process-mining algorithms exist: no discovery, no conformance checking, no
  alignment computation, no planning. Only the data *shapes* for these concepts
  were manufactured, not behavior over them.

## What "playground" means in this repo

Per the repository-shape section of
`docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md`:

```text
playground/            generated end-to-end customer proof
```

Note "generated": per this project's source-authority policy, `playground/` is
manufacturing output, the same as `generated/` and `examples/`. It is not meant
to be hand-authored directly — a real playground gets produced by
`ontology.ttl` + a ggen-marketplace pack's templates via `ggen sync run`, the
same path that produced `generated/erlang/` and `generated/elixir/`. This
README itself is scaffolding for a directory ggen has not been asked to fill
yet, not a hand-written substitute for that manufacturing.

## What a real playground would need

To actually satisfy `GATE PLAYGROUND_ALIVE`, per the acceptance-crown
definition ("observed execution against the exact generated subject, not
generator existence or successful compilation alone") a playground needs a
fresh-user, end-to-end workflow that a person with no prior context on this
repo could run and observe, minimally covering:

1. **Discovery** — feed a real (or realistic sample) event log in through the
   admitted OCEL/XES record types and produce a directly-follows graph or
   Petri net from it. Does not exist.
2. **Conformance** — replay a trace against a discovered/reference process
   model and compute alignment moves (fit/deviation) using the
   `alignment_move` type already manufactured. Does not exist.
3. **Planning** — take the process model as a PDDL/PPDDL planning domain and
   produce a plan or policy, respecting this repo's `SELECT != CONSTRUCT !=
   DO` boundary (a plan is a candidate, not an executed action). Does not
   exist.

None of discovery, conformance, or planning has been manufactured for this
project. The only thing that exists today is the data-type layer those three
capabilities would eventually consume.

## See also

- `docs/jira/v26.8.29/03-architecture-and-ggen-manufacturing.md` — manufacturing
  acceptance crowns and the generated-repository-surfaces layout this file
  quotes from.
- `generated/README.md` — the source-authority doctrine for manufactured
  output (this directory falls under the same doctrine once ggen produces
  anything into it).
- `receipts/2026-08-29-first-ggen-manufactured-slice.json` — the only
  manufacturing receipt in this repo so far; states its own scope boundary
  explicitly, including that `playground/` was not attempted.
- `examples/README.md` — the sibling placeholder for the `examples/` gate.
