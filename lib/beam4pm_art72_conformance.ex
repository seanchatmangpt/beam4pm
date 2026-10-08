defmodule BeamPM.Art72Conformance do
  @moduledoc """
  EU AI Act Art. 72 post-market monitoring conformance (dissertation
  Definition 7.2): token-replay fitness

      C(L, P) = 1/2 (1 - m/c) + 1/2 (1 - r/p)

  over an event log L and Petri net P, wired to a typed drift decision.

  ## Mapping to the engine (honest deviation note)

  beam4pm's rust4pm WASM engine exposes **alignment-based** fitness
  (`BeamPM.Rust4PM.compute_fitness/2`) and optimal alignments
  (`align_trace/2`, `align_variants/2`). The engine has NO token-replay op
  exposing m/c/r/p token counts (checked 2026-10-06 against
  `lib/beam4pm_rust4pm.ex`'s full dispatch surface). Definition 7.2 is the
  classic token-replay fitness (Rozinat & van der Aalst), so this module
  implements the token game directly in Elixir over a plain Petri net
  (places, weighted arcs, initial/final marking). Self-contained and
  engine-free, so a synthetic net + log replay is fully deterministic.

  ## Replay convention (stated precisely, pm4py-compatible in spirit)

  Each trace is replayed transition by transition against the current
  marking:

    * if every input place holds the required tokens, they are consumed
      (added to `c`) and the output tokens are produced (added to `p`);
    * if some input tokens are absent, the transition still fires
      "underfed" (pm4py convention): the absent tokens are counted into
      `m` (missing) AND into `c` (consumed), so the ratio stays
      well-defined and a single missing token penalizes but does not
      divide by zero.

  At trace end, the marking is compared to the final marking:

    * per-place deficit `max(0, final(p) - marking(p))` is added to `m`
      and to `c`;
    * per-place excess `max(0, marking(p) - final(p))` is added to `r`
      (remaining) and to `p`.

  `c == 0` or `p == 0` (nothing replayed) yields fitness 1.0 by convention
  (nothing deviated). Aggregate log fitness sums tokens across traces
  (the standard token-replay aggregation).
  """

  alias __MODULE__

  defstruct places: %{}, transitions: %{}, initial: %{}, final: %{}

  @type t :: %Art72Conformance{
          places: %{optional(place()) => pos_integer()},
          transitions: %{optional(String.t()) => transition()},
          initial: marking(),
          final: marking()
        }

  @type place :: String.t()
  @type marking :: %{optional(place()) => non_neg_integer()}
  @type transition :: %{input: marking(), output: marking()}

  @type replay_stats :: %{
          consumed: non_neg_integer(),
          produced: non_neg_integer(),
          missing: non_neg_integer(),
          remaining: non_neg_integer()
        }

  @doc """
  Builds a Petri net. `transitions` maps a transition name to
  `%{input: marking(), output: marking()}` (explicit integer weights).
  `initial`/`final` are marking maps; omitted places hold 0 tokens.
  """
  @spec net(%{optional(String.t()) => %{input: marking(), output: marking()}}, marking(), marking()) :: t()
  def net(transitions, initial, final) when is_map(transitions) and is_map(initial) and is_map(final) do
    places =
      transitions
      |> Enum.reduce(MapSet.new(), fn {_name, tr}, acc ->
        acc
        |> MapSet.union(MapSet.new(Map.keys(tr.input)))
        |> MapSet.union(MapSet.new(Map.keys(tr.output)))
      end)
      |> MapSet.to_list()
      |> Map.new(&{&1, 1})

    %Art72Conformance{places: places, transitions: transitions, initial: initial, final: final}
  end

  @doc """
  Replays one trace (list of transition names) and returns the token sums
  `%{consumed: c, produced: p, missing: m, remaining: r}`.
  Raises on an unknown transition name (a trace referencing an activity
  the model cannot express is a caller bug, not a fitness event).
  """
  @spec replay_trace(t(), [String.t()]) :: replay_stats()
  def replay_trace(%Art72Conformance{} = net, trace) when is_list(trace) do
    base = %{consumed: 0, produced: 0, missing: 0, remaining: 0}

    {stats, end_marking} =
      Enum.reduce(trace, {base, net.initial}, fn tname, {acc, marking} ->
        tr = Map.fetch!(net.transitions, tname)

        {missing_here, consumed_here} =
          Enum.reduce(tr.input, {0, 0}, fn {pl, w}, {m, c} ->
            {m + max(0, w - Map.get(marking, pl, 0)), c + w}
          end)

        produced_here = Enum.sum(Map.values(tr.output))

        marking =
          marking
          |> then(fn mk -> Enum.reduce(tr.input, mk, fn {pl, w}, m2 -> Map.put(m2, pl, max(0, Map.get(m2, pl, 0) - w)) end) end)
          |> then(fn mk -> Enum.reduce(tr.output, mk, fn {pl, w}, m2 -> Map.put(m2, pl, Map.get(m2, pl, 0) + w) end) end)

        {%{acc | consumed: acc.consumed + consumed_here,
                 produced: acc.produced + produced_here,
                 missing: acc.missing + missing_here},
         marking}
      end)

    deficit = marking_delta(end_marking, net.final, :deficit)
    excess = marking_delta(end_marking, net.final, :excess)

    %{
      consumed: stats.consumed + deficit,
      produced: stats.produced + excess,
      missing: stats.missing + deficit,
      remaining: stats.remaining + excess
    }
  end

  @doc """
  Replays a whole log (list of traces) with the standard token-sum
  aggregation and returns `{C, aggregate_stats}`. C is a float in [0, 1].
  """
  @spec log_fitness(t(), [[String.t()]]) :: {float(), replay_stats()}
  def log_fitness(%Art72Conformance{} = net, log) when is_list(log) do
    stats =
      Enum.reduce(log, %{consumed: 0, produced: 0, missing: 0, remaining: 0}, fn trace, acc ->
        s = replay_trace(net, trace)
        Map.merge(acc, s, fn _k, a, b -> a + b end)
      end)

    {fitness_from_stats(stats), stats}
  end

  @doc """
  Definition 7.2 from aggregate token counts. `c == 0` or `p == 0`
  (nothing replayed) yields 1.0 by convention.
  """
  @spec fitness_from_stats(replay_stats()) :: float()
  def fitness_from_stats(%{consumed: c, produced: p, missing: m, remaining: r}) do
    term1 = if c == 0, do: 1.0, else: 1 - m / c
    term2 = if p == 0, do: 1.0, else: 1 - r / p
    (term1 + term2) / 2
  end

  @doc """
  Pure typed drift decision: `C < 1 - epsilon_threshold` => `:DRIFT`,
  else `:NO_DRIFT`.
  """
  @spec drift_decision(number(), non_neg_integer() | float()) :: :DRIFT | :NO_DRIFT
  def drift_decision(c, epsilon_threshold)
      when is_number(c) and is_number(epsilon_threshold) and epsilon_threshold >= 0 do
    if c < 1 - epsilon_threshold, do: :DRIFT, else: :NO_DRIFT
  end

  defp marking_delta(marking, final, kind) do
    places = MapSet.to_list(MapSet.union(MapSet.new(Map.keys(marking)), MapSet.new(Map.keys(final))))

    Enum.reduce(places, 0, fn pl, acc ->
      have = Map.get(marking, pl, 0)
      need = Map.get(final, pl, 0)

      case kind do
        :deficit -> acc + max(0, need - have)
        :excess -> acc + max(0, have - need)
      end
    end)
  end
end
