defmodule BeamPM.EnterprisePlanning do
  @moduledoc """
  Enterprise planning facade over the admitted `BeamPM.Ferroplan` engine.

  This module does not invent a second planner. It composes the existing
  classical/PDDL3/temporal, HTN/HDDL, FOND, explanation, validation and
  session/replanning surfaces behind one explicit planning contract.

  Every returned plan or policy is a candidate. This module never actuates it.
  Unsupported planning classes are refused by name instead of silently
  degrading to a weaker planning model.
  """

  alias BeamPM.Ferroplan

  @supported_classes [
    :classical,
    :numeric,
    :preferences,
    :temporal,
    :htn,
    :hddl,
    :fond
  ]

  @unsupported_classes [
    :pomdp,
    :contingent_partial_observability,
    :probabilistic_mdp,
    :continuous_time_effects,
    :dynamic_derived_predicates
  ]

  @type planning_class ::
          :classical | :numeric | :preferences | :temporal | :htn | :hddl | :fond

  @type request :: %{
          required(:class) => atom(),
          required(:domain) => String.t(),
          required(:problem) => String.t(),
          optional(:limits) => map(),
          optional(:search) => String.t(),
          optional(:request_id) => String.t()
        }

  @doc "Machine-readable capability boundary."
  def capabilities do
    %{
      supported: @supported_classes,
      unsupported: @unsupported_classes,
      lifecycle: [
        :solve,
        :validate,
        :explain,
        :replan,
        :fork_scenario,
        :observe,
        :goal_change,
        :bounded_search
      ],
      authority: :candidate_only,
      actuation: :not_provided
    }
  end

  @doc """
  Route a planning request to the strongest admitted native planning class.

  PDDL classes use `plan_production/4`, preserving bounded production
  envelopes. HTN, HDDL and FOND use their native solver paths. No class is
  approximated by another class.
  """
  @spec solve(request(), keyword()) :: Ferroplan.result() | {:error, term()}
  def solve(%{class: class, domain: domain, problem: problem} = req, opts \\ [])
      when is_atom(class) and is_binary(domain) and is_binary(problem) do
    case class do
      class when class in [:classical, :numeric, :preferences, :temporal] ->
        extra = production_options(class, req)
        Ferroplan.plan_production(domain, problem, extra, opts)

      :htn ->
        Ferroplan.htn_plan(domain, problem, opts)

      :hddl ->
        Ferroplan.hddl_solve(domain, problem, opts)

      :fond ->
        Ferroplan.fond_policy(domain, problem, opts)

      class when class in @unsupported_classes ->
        {:error, {:unsupported_planning_class, class}}

      other ->
        {:error, {:unknown_planning_class, other}}
    end
  end

  def solve(req, _opts), do: {:error, {:invalid_planning_request, req}}

  @doc "Explain a concrete candidate plan using the same engine semantics."
  def explain(domain, problem, plan, opts \\ [])
      when is_binary(domain) and is_binary(problem) and is_map(plan) do
    Ferroplan.explain(domain, problem, plan, opts)
  end

  @doc """
  Validate an externally supplied candidate plan from a given step.

  A temporary native planning session is always freed. Validation is
  inspection only; it neither advances nor actuates the plan.
  """
  def validate(domain, problem, plan, from \\ 0, opts \\ [])
      when is_binary(domain) and is_binary(problem) and is_map(plan) and
             is_integer(from) and from >= 0 do
    with_session(domain, problem, opts, fn handle ->
      Ferroplan.session_plan_valid?(handle, plan, from, opts)
    end)
  end

  @doc "Create a stateful planning session for observation/replanning loops."
  def open_session(domain, problem, opts \\ []),
    do: Ferroplan.session_new(domain, problem, opts)

  @doc "Fork a scenario without mutating the source planning session."
  def fork_scenario(handle, opts \\ []), do: Ferroplan.session_fork(handle, opts)

  @doc "Apply observations to a planning session; this is observation, not actuation."
  def observe(handle, sight, opts \\ []), do: Ferroplan.session_observe(handle, sight, opts)

  @doc "Change the planning goal without executing any action."
  def set_goal(handle, goal, opts \\ []), do: Ferroplan.session_set_goal(handle, goal, opts)

  @doc """
  Bounded replan for an existing session.

  Search is explicitly bounded by evaluations and memory. The result remains
  a candidate plan and does not cross an actuation boundary.
  """
  def replan(handle, evals, mem_mb, opts \\ [])
      when is_integer(handle) and evals > 0 and mem_mb > 0 do
    Ferroplan.session_think(handle, evals, mem_mb, opts)
  end

  @doc "Free a planning session."
  def close_session(handle, opts \\ []), do: Ferroplan.session_free(handle, opts)

  defp production_options(class, req) do
    base =
      case class do
        :temporal -> %{"mode" => "temporal"}
        :preferences -> %{"mode" => "pddl3"}
        _ -> %{"mode" => "auto"}
      end

    base
    |> maybe_put("search", req[:search])
    |> maybe_put("request_id", req[:request_id])
    |> merge_limits(req[:limits])
  end

  defp merge_limits(extra, nil), do: extra

  defp merge_limits(extra, limits) when is_map(limits) do
    Enum.reduce(
      ["max_evaluated", "max_plan_steps", "max_output_bytes"],
      extra,
      fn key, acc ->
        value = Map.get(limits, key) || Map.get(limits, String.to_existing_atom(key))
        maybe_put(acc, key, value)
      end
    )
  rescue
    ArgumentError -> extra
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp with_session(domain, problem, opts, fun) do
    case Ferroplan.session_new(domain, problem, opts) do
      {:ok, %{"handle" => handle}} ->
        try do
          fun.(handle)
        after
          _ = Ferroplan.session_free(handle, opts)
        end

      other ->
        other
    end
  end
end
