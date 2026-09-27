defmodule BeamPM.Powl.FondPowl do
  @moduledoc """
  FOND outcome-branch sets -> POWL choice-graph converter (the 法面 producer
  for `BeamPM.Types.PowlChoiceOperator` / `PowlChoiceGraphEdge` /
  `PowlLeaf` from planning side).

  `BeamPM.Dfcm.fond_outcomes/0` (lib/beam4pm_dfcm.ex:48-49) publishes the
  public observation-outcome vocabulary `[:positive, :negative,
  :inconclusive]`, and Dfcm's own `fond_policy/1` (lib/beam4pm_dfcm.ex:401,
  private) attaches exactly that outcome set to every `:observe` decision:
  one state/action, several admissible outcome branches, none erased. That
  is exactly a POWL exclusive choice, and the engine models an exclusive
  choice as a ChoiceGraph with edges `▷ -> Child(i)`, `Child(i) -> □` per
  branch and no edges between children (engine's own `exclusive_choice`
  builder, vendor/rust4pm-powl .../powl/mod.rs:511-516).

  `from_policy_outcomes/1` takes the explicit structure
  `%{state_or_action => [outcome, ...]}` and builds one choice graph per
  state/action (branches as edges), plus one `PowlChoiceOperator` whose
  `branch_digest` is a real content digest over that branch set and whose
  `selection_rule` is the constant `"fond_outcome_branches"` (naming the
  producing rule: all branches stay admissible until observation refines
  them -- the Dfcm FOND semantics itself, not invented evidence). Multiple
  states compose under a Sequence operator in sorted-key order
  (deterministic). Outcomes are validated against
  `BeamPM.Dfcm.fond_outcomes/0` -- an unknown outcome is a typed refusal,
  never a silently widened vocabulary.
  """

  alias BeamPM.Types.PowlChoiceGraphEdge
  alias BeamPM.Types.PowlChoiceOperator
  alias BeamPM.Types.PowlFreq
  alias BeamPM.Types.PowlLeaf
  alias BeamPM.Types.PowlSequenceOperator

  # Read at runtime (not a module attribute) so the Dfcm vocabulary stays
  # the single live source of truth.
  defp fond_outcomes, do: Enum.map(BeamPM.Dfcm.fond_outcomes(), &Atom.to_string/1)

  @exactly_once %PowlFreq{min_freq: 1, max_freq: 1}

  @doc """
  Convert FOND outcome branch sets into typed choice-graph structs.

  Input: `%{state_or_action => [outcomes]}` where keys are atoms or
  binaries and each outcome is one of `BeamPM.Dfcm.fond_outcomes/0` (atom
  or string). Returns
  `{:ok, %{root: BeamPM.Powl.Model.Node.t(), choices: [choice()]}}` where
  each choice is `%{key: String.t(), operator: PowlChoiceOperator.t(),
  node: BeamPM.Powl.Model.Node.t()}` -- one per state/action, sorted by
  key. `root` is the single choice graph when there is exactly one
  state/action, otherwise a Sequence over them in sorted-key order.
  Refusals: `{:error, {:invalid_policy_outcomes, term}}`,
  `{:error, {:empty_outcomes, key}}`, `{:error, {:unknown_outcome, key, outcome}}`.
  """
  @spec from_policy_outcomes(map()) ::
          {:ok, %{root: BeamPM.Powl.Model.Node.t(), choices: [map()]}} | {:error, term()}
  def from_policy_outcomes(outcomes) when is_map(outcomes) and outcomes != %{} do
    entries =
      outcomes
      |> Enum.map(fn {key, branches} ->
        with {:ok, key} <- normalize_key(key),
             {:ok, branches} <- normalize_branches(key, branches) do
          {:ok, build_choice(key, branches)}
        end
      end)

    if bad = Enum.find(entries, &match?({:error, _}, &1)) do
      bad
    else
      choices = Enum.map(entries, fn {:ok, c} -> c end)
      # entries keep the map's given order; sort choices by key for a
      # deterministic projection regardless of caller map order.
      choices = Enum.sort_by(choices, & &1.key)

      root =
        case choices do
          [only] ->
            only.node

          [_ | _] = multiple ->
            children = Enum.map(multiple, & &1.node)

            root_id =
              "fond-seq-" <>
                (multiple
                 |> Enum.map(& &1.operator.operator_id)
                 |> digest_join())

            %BeamPM.Powl.Model.Node{
              variant: :operator,
              operator: %PowlSequenceOperator{
                operator_id: root_id,
                step_digest: digest_join(Enum.map(multiple, & &1.key)),
                predecessor_digest: nil
              },
              freq: @exactly_once,
              children: children
            }
        end

      {:ok, %{root: root, choices: choices}}
    end
  end

  def from_policy_outcomes(outcomes) when outcomes == %{} or outcomes == [],
    do: {:error, {:invalid_policy_outcomes, outcomes}}

  def from_policy_outcomes(other), do: {:error, {:invalid_policy_outcomes, other}}

  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_key(key), do: {:error, {:invalid_policy_outcomes, {:key, key}}}

  defp normalize_branches(_key, branches) when not is_list(branches),
    do: {:error, {:invalid_policy_outcomes, :branches_not_list}}

  defp normalize_branches(key, []), do: {:error, {:empty_outcomes, key}}

  defp normalize_branches(key, branches) do
    Enum.reduce_while(branches, {:ok, []}, fn outcome, {:ok, acc} ->
      name =
        cond do
          is_atom(outcome) and not is_boolean(outcome) -> Atom.to_string(outcome)
          is_binary(outcome) -> outcome
          true -> nil
        end

      cond do
        is_nil(name) ->
          {:halt, {:error, {:unknown_outcome, key, outcome}}}

        name not in fond_outcomes() ->
          {:halt, {:error, {:unknown_outcome, key, outcome}}}

        true ->
          {:cont, {:ok, acc ++ [name]}}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.sort(names)}
      {:error, _} = err -> err
    end
  end

  defp build_choice(key, branches) do
    children =
      Enum.map(branches, fn branch ->
        %BeamPM.Powl.Model.Node{
          variant: :leaf,
          leaf: %PowlLeaf{activity_label: key <> "/" <> branch, is_tau: false, min_freq: 1, max_freq: 1}
        }
      end)

    n = length(branches)

    edges =
      0..(n - 1)
      |> Enum.flat_map(fn i ->
        [%PowlChoiceGraphEdge{from_kind: :start, from_child_index: nil, to_kind: :child, to_child_index: i},
         %PowlChoiceGraphEdge{from_kind: :child, from_child_index: i, to_kind: :end, to_child_index: nil}]
      end)
      |> Enum.sort_by(fn edge -> {kind_rank(edge.from_kind), edge.from_child_index,
                                  kind_rank(edge.to_kind), edge.to_child_index} end)

    node = %BeamPM.Powl.Model.Node{
      variant: :choice_graph,
      children: children,
      edges: edges,
      freq: @exactly_once
    }

    operator = %PowlChoiceOperator{
      operator_id: "fond-choice-" <> digest_join(branches),
      branch_digest: digest_join(Enum.map(branches, &{key, &1})),
      selection_rule: "fond_outcome_branches"
    }

    %{key: key, operator: operator, node: node}
  end

  defp kind_rank(:start), do: 0
  defp kind_rank(:child), do: 1
  defp kind_rank(:end), do: 2

  defp digest_join(terms),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(terms)) |> Base.encode16(case: :lower) |> binary_part(0, 32)
end
