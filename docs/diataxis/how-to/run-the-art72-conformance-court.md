# Run the ART72 conformance court (how-to)

Goal: score a real log against a fixed Petri net and produce the typed
drift verdict EU AI Act Art. 72 post-market monitoring calls for.

The court is `BeamPM.Art72Conformance` (`lib/beam4pm_art72_conformance.ex`),
hand-written computation (a wrapper/algorithm module, not an ontology
projection — same convention as `BeamPM.Petgraph`/`BeamPM.Tract`, per its
`@moduledoc`). Engine-free by design: the rust4pm WASM engine has no
token-replay op exposing raw m/c/r/p counts (stated in the `@moduledoc`'s
honest deviation note, checked 2026-10-06 against
`lib/beam4pm_rust4pm.ex`'s dispatch surface).

## The four calls

All live in `lib/beam4pm_art72_conformance.ex`:

The four calls, in order:

- `net/3` — build the Petri net from weighted arcs + initial/final
  markings
- `replay_trace/2` — one trace -> `%{consumed:, produced:, missing:,
  remaining:}`; raises on an unknown transition name (caller bug, not a
  fitness event)
- `log_fitness/2` — whole log -> `{C, aggregate_stats}`, token-sum
  aggregation
- `drift_decision/2` — `C < 1 - epsilon` -> `:DRIFT`, else `:NO_DRIFT`

## 1. Build the net

```elixir
net =
  BeamPM.Art72Conformance.net(
    %{
      "t_a" => %{input: %{"p1" => 1}, output: %{"p2" => 1}},
      "t_b" => %{input: %{"p2" => 1, "gate" => 1}, output: %{"p3" => 1}}
    },
    %{"p1" => 1},
    %{"p3" => 1}
  )
```

Weights are explicit integers; omitted places hold 0 tokens (`net/3`
doc).

## 2. Score the log

```elixir
{c, stats} = BeamPM.Art72Conformance.log_fitness(net, log)
```

`stats` is `%{consumed:, produced:, missing:, remaining:}` summed over all
traces. Underfed transitions still fire (pm4py convention): absent input
tokens count into both `m` (missing) and `c` (consumed), so a single
missing token penalizes but never divides by zero (`@moduledoc`,
"Replay convention").

## 3. Verdict

```elixir
BeamPM.Art72Conformance.drift_decision(c, 0.2)
```

## Running it for real

Wrap the three calls in `mix run -e '...'` from the repo root, or add a
case to the standing suite:

```console
$ mix test test/beam4pm_art72_conformance_test.exs
```

The suite asserts exact formula values (perfect log `C = 1.0`, skip `C =
2/3`, underfeed `C = 7/12`, mixed log `C = 5/6`).

## Related surfaces

- Alignment-based fitness from the WASM engine:
  `BeamPM.Rust4PM.compute_fitness/2` (`lib/beam4pm_rust4pm.ex`)
- POWL-model conformance: `lib/beam4pm_powl_conformance.ex`
- RF2 conformance family: `lib/beam4pm_rf2_conformance.ex`

See Also: `docs/diataxis/tutorials/run-your-first-conformance-check.md` ·
`docs/diataxis/reference/ash-resources-index.md`
