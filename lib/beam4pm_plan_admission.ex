# Hand-authored (not ggen-generated). Admitted via bap:hand_authored_lib_beam4pm_plan_admission -- see ontology.ttl
defmodule BeamPM.PlanAdmission do
  @moduledoc ~S"""
  Independent admission of a planner's candidate plan. ferroplan proposes
  (`authority: candidate_only`); `BeamPM.Graphlaw` replays the plan over an
  RDF state and refuses at the first violated precondition or an unmet goal.

  An `admission` spec is `%{state: triples, model: model, goal: triples}`:

    * `state` -- initial ground atoms, `{subject, predicate, object}` IRI triples
    * `model` -- the plan step's `"action"` name => `%{pre:, add:, del:}` triple
      lists, or a 1-arity function of the step's `"args"` returning that map
    * `goal`  -- triples that must hold after the last action

  Fails closed: an action missing from `model` is a refusal, not a skip.
  """

  alias BeamPM.Graphlaw

  @type admission :: %{state: [tuple()], model: %{String.t() => map()}, goal: [tuple()]}

  @doc "Steps of a ferroplan plan: a bare step list or a `UniversalPlan` map."
  @spec steps(term()) :: [map()]
  def steps(%{"steps" => steps}) when is_list(steps), do: steps
  def steps(steps) when is_list(steps), do: steps
  def steps(_), do: []

  @doc "Replays `plan` under `admission`; `{:ok, %{receipts:, states:}}` or `{:error, {:refused, refusal}}`."
  @spec admit(term(), admission(), keyword()) :: {:ok, map()} | {:error, term()}
  def admit(plan, %{state: state, model: model, goal: goal}, opts \\ []) do
    with {:ok, actions} <- actions(steps(plan), model),
         {:ok, resp} <- Graphlaw.admit_plan(state, actions, goal, opts) do
      {:ok, %{receipts: resp["receipts"], states: resp["states"]}}
    end
  end

  defp actions(steps, model) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      name = step["action"]

      case Map.fetch(model, name) do
        {:ok, m} ->
          m = if is_function(m, 1), do: m.(step["args"] || []), else: m

          action = %{
            name: name,
            pre: Map.get(m, :pre, []),
            add: Map.get(m, :add, []),
            del: Map.get(m, :del, [])
          }

          {:cont, {:ok, [action | acc]}}

        :error ->
          {:halt,
           {:error,
            {:refused, %{"kind" => "Unsupported", "message" => "no action model for `#{name}`"}}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end
end
