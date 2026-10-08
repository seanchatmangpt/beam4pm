# Run your first conformance check (tutorial)

Token-replay conformance against a Petri net you define, ending in a typed
drift decision. The engine is `BeamPM.Art72Conformance`
(`lib/beam4pm_art72_conformance.ex`): self-contained Elixir implementing
EU AI Act Art. 72 post-market-monitoring fitness

    C(L, P) = 1/2 (1 - m/c) + 1/2 (1 - r/p)

(the classic Rozinat & van der Aalst token-replay fitness, dissertation
Definition 7.2; see the module's `@moduledoc`).

## Prerequisites

- A working beam4pm checkout with a green `just verify` (see
  `getting-started.md`)

## 1. See it pass first

```console
$ mix test test/beam4pm_art72_conformance_test.exs
```

All tests pass, exit 0. The tests assert exact formula values: a
perfectly-fitting log scores `C = 1.0`, a trace skipping a final
transition scores `C = 2/3`, an underfed trace scores `C = 7/12`, and a
mixed log scores `C = 5/6` by token-sum aggregation.

## 2. Define a net and a log

```elixir
alias BeamPM.Art72Conformance

net =
  Art72Conformance.net(
    %{
      "t_a" => %{input: %{"p1" => 1}, output: %{"p2" => 1}},
      "t_b" => %{input: %{"p2" => 1}, output: %{"p3" => 1}},
      "t_c" => %{input: %{"p2" => 1}, output: %{"p4" => 1}}
    },
    %{"p1" => 1},
    %{"p3" => 1, "p4" => 1}
  )

log = [
  ["t_a", "t_b"],        # fits
  ["t_a", "t_b", "t_c"], # extra t_c (p4 excess at the end)
  ["t_a"]                # skips t_b (p3 deficit)
]
```

A transition is a name mapped to explicit weighted input/output markings.
`net/3` derives the place set from the arcs.

## 3. Replay and score

```elixir
{c, stats} = Art72Conformance.log_fitness(net, log)
stats
#=> %{consumed: 9, produced: 7, missing: 4, remaining: 1}

c
#=> 0.7063492063492064
```

(Values verified by running the example with `mix run -e` against
`lib/beam4pm_art72_conformance.ex` at the current pin.)

`log_fitness/2` sums tokens across traces (the standard aggregation) and
returns `{C, stats}`. Per-trace numbers come from `replay_trace/2`, which
raises on an unknown transition name — a trace referencing an activity the
model cannot express is a caller bug, not a fitness event.

## 4. Make the drift decision

```elixir
Art72Conformance.drift_decision(c, 0.2)
#=> :DRIFT   (0.706 < 1 - 0.2)

Art72Conformance.drift_decision(0.9, 0.2)
#=> :NO_DRIFT
```

Pure and typed: `C < 1 - epsilon` is `:DRIFT`, otherwise `:NO_DRIFT`
(`drift_decision/2`, `lib/beam4pm_art72_conformance.ex:163`).

## 5. Why token replay here, not alignment

beam4pm's rust4pm WASM engine exposes alignment-based fitness
(`BeamPM.Rust4PM.compute_fitness/2`) and optimal alignments, but no
token-replay op exposing raw m/c/r/p token counts (checked 2026-10-06
against `lib/beam4pm_rust4pm.ex`'s full dispatch surface — stated in the
module's `@moduledoc` "honest deviation note"). Definition 7.2 is
token-replay, so the token game is implemented directly in Elixir,
deterministic and engine-free.

## What you built

A reproducible conformance court: net in, log in, one float out, one typed
drift verdict out. Next steps: wire a real mined model in (Petri nets from
discovery) or run the whole suite:

```console
$ mix test test/beam4pm_art72_conformance_test.exs
```

See Also: `docs/diataxis/how-to/run-the-art72-conformance-court.md` ·
`docs/diataxis/explanation/ocel-2-0-event-model-in-beam4pm.md`
