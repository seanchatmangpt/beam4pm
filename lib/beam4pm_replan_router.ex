defmodule BeamPM.ReplanRouter do
  @moduledoc """
  Hand-authored replanning ladder over the generated `BeamPM.Ferroplan`
  facade. ferroplan stays mechanism-only (there is no `session_route` op);
  the routing policy lives here so the generated facade is never edited.

  ## Pure core: `route/2`

  `route(observation, state) :: {decision, evidence, state}` checks, in order:

    1. stale preimage -- the observed subject/pack/policy/world digests differ
       from the admitted ones -> `:refuse_stale` + `StalePlanRefusal` (CO-044);
    2. goal met -> `:close` + `PlanMemory` (CO-046);
    3. an unknown fact (not in the grounded task) -> `:strategic_recompile`
       (world model invalid); conformance not yet observed -> `:reobserve`;
    4. conforms and the stashed plan is still valid -> `:continue`;
    5. the admitted UniversalPlan covers the observed policy state ->
       `:follow_policy`;
    6. a later suffix of the stashed plan is valid -> `:suffix_reuse`;
    7. otherwise climb monotonically `:session_replan` -> `:hddl_replan`
       (when the previous rung reported `:exhausted` / `:no_plan` /
       `:timeout`) -> `:strategic_recompile`, emitting `DynamicReplanTrigger`
       (CO-043) and a `PlanLineage` link (CO-047).

  The rung never moves down within an episode. A new admitted event (an
  `event_id` not seen before with `admitted: true`) opens a new episode and
  resets the rung, evidenced by `EventTriggeredPlanning` (CO-045). The stale
  check runs before the reset, so a drifted preimage is refused even when it
  arrives with a new event.

  Every decision carries exactly one `BeamPM.Types.OcelEvent` (also appended
  to `state.events`).

  ## Driver: `observe/3`, `execute/4`

  `observe/3` builds an observation from the real engine session
  (`session_fact` to find unknown facts, `session_observe`,
  `session_goal_met?`, `session_valid?`, `session_plan_valid?` over later
  suffixes). `execute/4` performs a CONSTRUCT-ceiling step for a decision:
  `session_think` (evals <= 1_000_000, mem <= 2048 MB), `hddl_solve` under a
  `Task` timeout, `fond_policy`, `session_advance`. `:strategic_recompile`
  returns `{:recompile_required, evidence}` and never regenerates anything.

  Authority: NONE; ceiling CONSTRUCT. Nothing here actuates the world -- the
  `:continue` / `:follow_policy` results are candidate steps only.
  """

  alias BeamPM.Ferroplan
  alias BeamPM.PlanLineage

  alias BeamPM.Types.{
    DynamicReplanTrigger,
    EventTriggeredPlanning,
    OcelEvent,
    PlanMemory,
    StalePlanRefusal
  }

  @authority "NONE"
  @ceiling "CONSTRUCT"

  @preimage_keys [:subject, :pack, :policy, :world]

  @rungs [:none, :session_replan, :hddl_replan, :strategic_recompile]
  @failed_outcomes [:exhausted, :no_plan, :timeout, :error]

  @max_evals 1_000_000
  @max_mem_mb 2048

  @decisions [
    :refuse_stale,
    :close,
    :strategic_recompile,
    :reobserve,
    :continue,
    :follow_policy,
    :suffix_reuse,
    :session_replan,
    :hddl_replan
  ]

  defstruct plan_id: nil,
            admitted_preimage: %{},
            universal_plan: nil,
            rung: :none,
            episode_id: nil,
            generation: 0,
            seen_events: MapSet.new(),
            lineage: %PlanLineage{},
            events: [],
            ordinal: 0,
            run_id: nil

  @type decision ::
          :refuse_stale
          | :close
          | :strategic_recompile
          | :reobserve
          | :continue
          | :follow_policy
          | :suffix_reuse
          | :session_replan
          | :hddl_replan

  @type rung :: :none | :session_replan | :hddl_replan | :strategic_recompile

  @type preimage :: %{
          optional(:subject) => String.t(),
          optional(:pack) => String.t(),
          optional(:policy) => String.t(),
          optional(:world) => String.t()
        }

  @typedoc """
  Observation fields (all optional except `:preimage`):

    * `:event_id` / `:admitted` -- the admitted world event this observation carries;
    * `:preimage` -- observed subject/pack/policy/world digests;
    * `:unknown_facts` -- facts absent from the grounded task;
    * `:conformance` -- `:conforms | :deviates | nil` (nil = not yet observed);
    * `:goal_met`, `:plan_valid` -- engine booleans;
    * `:policy_state` -- abstract UniversalPlan state id the world is in;
    * `:suffix_from` -- smallest cursor offset > 0 whose suffix is valid, or nil;
    * `:attempt` -- `{rung, :solved | :exhausted | :no_plan | :timeout | :error}`
      reporting the previous ladder step's outcome.
  """
  @type observation :: map()

  @type t :: %__MODULE__{
          plan_id: String.t() | nil,
          admitted_preimage: preimage(),
          universal_plan: map() | nil,
          rung: rung(),
          episode_id: String.t() | nil,
          generation: non_neg_integer(),
          seen_events: MapSet.t(String.t()),
          lineage: PlanLineage.t(),
          events: [OcelEvent.t()],
          ordinal: non_neg_integer(),
          run_id: String.t() | nil
        }

  @doc "All decisions `route/2` can return."
  @spec decisions() :: [decision()]
  def decisions, do: @decisions

  @doc "Ladder rungs in climb order."
  @spec rungs() :: [rung()]
  def rungs, do: @rungs

  @doc """
  New router state bound to an admitted plan and preimage. Options:
  `:plan_id` (required), `:preimage` (required, subject/pack/policy/world
  digests), `:universal_plan` (a UniversalPlan map), `:run_id`,
  `:episode_id`.
  """
  @spec new(keyword() | map()) :: t()
  def new(opts) do
    opts = Map.new(opts)
    plan_id = Map.fetch!(opts, :plan_id)
    preimage = opts |> Map.fetch!(:preimage) |> normalize_preimage()
    run_id = Map.get(opts, :run_id, "replan-" <> String.slice(PlanLineage.digest(plan_id), 0, 12))
    {_link, lineage} = PlanLineage.derive(PlanLineage.new(), plan_id, %{"admitted" => preimage})

    %__MODULE__{
      plan_id: plan_id,
      admitted_preimage: preimage,
      universal_plan: Map.get(opts, :universal_plan),
      episode_id: Map.get(opts, :episode_id, run_id <> "-ep0"),
      lineage: lineage,
      run_id: run_id
    }
  end

  @doc "Digest of a preimage map (sorted-key canonical JSON sha256)."
  @spec preimage_hash(preimage()) :: String.t()
  def preimage_hash(preimage), do: preimage |> normalize_preimage() |> PlanLineage.digest()

  # ---------------------------------------------------------------------
  # Pure router
  # ---------------------------------------------------------------------

  @doc "Routes one observation. See the moduledoc for the ordered checks."
  @spec route(observation(), t()) :: {decision(), map(), t()}
  def route(observation, %__MODULE__{} = state) when is_map(observation) do
    observed = observation |> Map.get(:preimage, %{}) |> normalize_preimage()

    if observed != state.admitted_preimage do
      refuse_stale(observed, state)
    else
      {reset_evidence, state} = maybe_reset(observation, state)

      {decision, evidence, state} = route_admitted(observation, state)

      evidence =
        if reset_evidence, do: Map.put(evidence, :episode, reset_evidence), else: evidence

      finish(decision, evidence, observation, state)
    end
  end

  defp refuse_stale(observed, state) do
    {:ok, refusal} =
      StalePlanRefusal.new(%{
        plan_id: state.plan_id,
        admitted_preimage_hash: PlanLineage.digest(state.admitted_preimage),
        observed_preimage_hash: PlanLineage.digest(observed)
      })

    drifted =
      Enum.filter(@preimage_keys, fn k ->
        Map.get(observed, k) != Map.get(state.admitted_preimage, k)
      end)

    evidence = %{reason: :stale_preimage, refusal: refusal, drifted: drifted}
    finish(:refuse_stale, evidence, %{}, state)
  end

  defp maybe_reset(observation, state) do
    event_id = Map.get(observation, :event_id)

    if Map.get(observation, :admitted, false) and is_binary(event_id) and
         not MapSet.member?(state.seen_events, event_id) do
      episode_id = "#{state.run_id}-ep#{MapSet.size(state.seen_events) + 1}"

      {:ok, etp} =
        EventTriggeredPlanning.new(%{
          event_id: event_id,
          world_state_hash: PlanLineage.digest(state.admitted_preimage),
          episode_id: episode_id
        })

      {etp,
       %{
         state
         | rung: :none,
           episode_id: episode_id,
           seen_events: MapSet.put(state.seen_events, event_id)
       }}
    else
      {nil, state}
    end
  end

  defp route_admitted(obs, state) do
    unknown = Map.get(obs, :unknown_facts, [])
    conformance = Map.get(obs, :conformance)

    cond do
      Map.get(obs, :goal_met, false) ->
        close(obs, state)

      unknown != [] ->
        world_invalid = %{
          kind: "WorldModelInvalid",
          plan_id: state.plan_id,
          unknown_facts: Enum.sort(unknown),
          unknown_facts_hash: PlanLineage.digest(Enum.sort(unknown))
        }

        ladder_step(
          :strategic_recompile,
          %{reason: :unknown_fact, world_model_invalid: world_invalid},
          obs,
          state
        )

      is_nil(conformance) ->
        {:reobserve, %{reason: :missing_conformance}, state}

      conformance == :conforms and Map.get(obs, :plan_valid, false) ->
        {:continue, %{reason: :conforms_plan_valid}, state}

      (action = policy_action(state.universal_plan, Map.get(obs, :policy_state))) != nil ->
        {:follow_policy,
         %{
           reason: :policy_covers_state,
           policy_state: Map.get(obs, :policy_state),
           action: action
         }, state}

      is_integer(Map.get(obs, :suffix_from)) and Map.get(obs, :suffix_from) > 0 ->
        {:suffix_reuse, %{reason: :suffix_valid, suffix_from: Map.get(obs, :suffix_from)}, state}

      true ->
        ladder_step(
          next_rung(state, Map.get(obs, :attempt)),
          %{reason: :replan_required},
          obs,
          state
        )
    end
  end

  defp close(obs, state) do
    evidence_hash =
      PlanLineage.digest(%{
        "plan_id" => state.plan_id,
        "preimage" => state.admitted_preimage,
        "event_id" => Map.get(obs, :event_id),
        "episode_id" => state.episode_id
      })

    {:ok, memory} =
      PlanMemory.new(%{
        plan_id: state.plan_id,
        evidence_hash: evidence_hash,
        memory_hash:
          PlanLineage.digest(%{
            "evidence_hash" => evidence_hash,
            "lineage_hash" => PlanLineage.head_hash(state.lineage),
            "plan_id" => state.plan_id
          })
      })

    {:close, %{reason: :goal_met, plan_memory: memory}, state}
  end

  @doc """
  Next rung given the current rung and the last attempt outcome. Monotone:
  never returns a rung below `state.rung`.
  """
  @spec next_rung(t(), {rung(), atom()} | nil) :: rung()
  def next_rung(%__MODULE__{rung: current}, attempt) do
    failed_at =
      case attempt do
        {rung, outcome} when rung in @rungs and outcome in @failed_outcomes -> rung
        _ -> nil
      end

    base = max_rung(current, failed_at && succ(failed_at))
    if base == :none, do: :session_replan, else: base
  end

  defp succ(:none), do: :session_replan
  defp succ(:session_replan), do: :hddl_replan
  defp succ(:hddl_replan), do: :strategic_recompile
  defp succ(:strategic_recompile), do: :strategic_recompile

  defp max_rung(a, nil), do: a
  defp max_rung(a, b), do: if(rung_index(b) > rung_index(a), do: b, else: a)

  defp rung_index(r), do: Enum.find_index(@rungs, &(&1 == r))

  defp ladder_step(rung, evidence, obs, state) do
    rung = max_rung(state.rung, rung)
    generation = state.generation + 1
    new_plan_id = "#{state.plan_id}:g#{generation}:#{rung}"

    trigger_payload = %{
      "attempt" => inspect(Map.get(obs, :attempt)),
      "episode_id" => state.episode_id,
      "event_id" => Map.get(obs, :event_id),
      "plan_id" => state.plan_id,
      "rung" => rung
    }

    {:ok, trigger} =
      DynamicReplanTrigger.new(%{
        plan_id: state.plan_id,
        event_id: Map.get(obs, :event_id),
        trigger_hash: PlanLineage.digest(trigger_payload)
      })

    {link, lineage} = PlanLineage.derive(state.lineage, new_plan_id, trigger_payload)

    evidence = Map.merge(evidence, %{rung: rung, trigger: trigger, lineage: link})
    {rung, evidence, %{state | rung: rung, generation: generation, lineage: lineage}}
  end

  defp policy_action(nil, _), do: nil
  defp policy_action(_, nil), do: nil

  defp policy_action(%{"policy" => entries}, policy_state) when is_list(entries) do
    Enum.find_value(entries, fn
      %{"state" => ^policy_state, "action" => action} -> action
      _ -> nil
    end)
  end

  defp policy_action(_, _), do: nil

  defp finish(decision, evidence, obs, state) do
    ordinal = state.ordinal + 1

    event =
      event(state, ordinal, "replan_router." <> Atom.to_string(decision), %{
        "decision" => Atom.to_string(decision),
        "reason" => evidence |> Map.get(:reason) |> to_string(),
        "plan_id" => state.plan_id,
        "episode_id" => state.episode_id,
        "rung" => Atom.to_string(state.rung),
        "observed_event_id" => Map.get(obs, :event_id),
        "lineage_head" => PlanLineage.head_hash(state.lineage),
        "authority" => @authority,
        "ceiling" => @ceiling
      })

    evidence =
      Map.merge(evidence, %{
        decision: decision,
        authority: @authority,
        ceiling: @ceiling,
        ocel_event: event
      })

    {decision, evidence, %{state | ordinal: ordinal, events: state.events ++ [event]}}
  end

  # Same shape as the private event helper in lib/beam4pm_actuation.ex.
  defp event(state, ordinal, event_type, extra_attrs) do
    run_id = state.run_id

    {:ok, ev} =
      OcelEvent.new(%{
        event_id: "#{run_id}-#{ordinal}-#{event_type}",
        event_type: event_type,
        event_time: DateTime.utc_now() |> DateTime.to_iso8601(),
        attributes: Map.merge(%{"case_id" => run_id}, extra_attrs)
      })

    ev
  end

  defp normalize_preimage(preimage) when is_map(preimage) do
    Map.new(@preimage_keys, fn k ->
      {k, Map.get(preimage, k, Map.get(preimage, Atom.to_string(k)))}
    end)
  end

  # ---------------------------------------------------------------------
  # Driver over the generated facade
  # ---------------------------------------------------------------------

  @doc """
  Builds an observation from a live engine session `handle` and a batch of
  sighted `{fact, bool}` pairs. `context` supplies the non-engine fields
  (`:preimage`, `:event_id`, `:admitted`, `:conformance`, `:policy_state`,
  `:attempt`, and `:plan` -- the stashed plan map used for suffix checks).
  Unknown facts are detected with `session_fact` (nil = not grounded) and
  are NOT sent to `session_observe`.
  """
  @spec observe(non_neg_integer(), [{String.t(), boolean()}], map()) ::
          {:ok, observation()} | {:error, term()}
  def observe(handle, sight, context)
      when is_integer(handle) and is_list(sight) and is_map(context) do
    with {:ok, {known, unknown}} <- split_known(handle, sight),
         {:ok, news} <- observe_known(handle, known),
         {:ok, %{"goal_met" => goal_met}} <- Ferroplan.session_goal_met?(handle),
         {:ok, %{"valid" => plan_valid}} <- Ferroplan.session_valid?(handle),
         {:ok, suffix_from} <- suffix_from(handle, Map.get(context, :plan)) do
      {:ok,
       context
       |> Map.drop([:plan])
       |> Map.merge(%{
         unknown_facts: unknown,
         news: news,
         goal_met: goal_met,
         plan_valid: plan_valid,
         suffix_from: suffix_from
       })}
    end
  end

  defp split_known(handle, sight) do
    Enum.reduce_while(sight, {:ok, {[], []}}, fn {name, _value} = pair, {:ok, {known, unknown}} ->
      case Ferroplan.session_fact(handle, name) do
        {:ok, %{"value" => nil}} -> {:cont, {:ok, {known, [name | unknown]}}}
        {:ok, %{"value" => _}} -> {:cont, {:ok, {[pair | known], unknown}}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, {known, unknown}} -> {:ok, {Enum.reverse(known), Enum.reverse(unknown)}}
      err -> err
    end
  end

  defp observe_known(_handle, []), do: {:ok, []}
  defp observe_known(handle, known), do: Ferroplan.session_observe(handle, known)

  defp suffix_from(_handle, nil), do: {:ok, nil}

  defp suffix_from(handle, %{"steps" => steps} = plan) when is_list(steps) do
    Enum.reduce_while(1..max(length(steps) - 1, 0)//1, {:ok, nil}, fn from, acc ->
      case Ferroplan.session_plan_valid?(handle, plan, from) do
        {:ok, %{"valid" => true}} -> {:halt, {:ok, from}}
        {:ok, %{"valid" => false}} -> {:cont, acc}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp suffix_from(_handle, _plan), do: {:ok, nil}

  @doc """
  Performs the CONSTRUCT step for `decision` against session `handle`.
  `inputs` carries `:evidence` (from `route/2`), and per rung:
  `:hddl_domain`/`:hddl_problem` for `:hddl_replan`, `:fond_problem` (a
  PlanningProblem JSON string) for `:follow_policy` when no policy is
  loaded. Options: `:evals` (default 100_000, capped at 1_000_000),
  `:mem_mb` (default 64, capped at 2048), `:hddl_timeout` (default 30_000 ms),
  `:limits` (PlannerLimits map).

  Returns `{:ok, %{rung:, outcome:, ...}}` where `outcome` feeds the next
  observation's `:attempt`, or `{:recompile_required, evidence}` for
  `:strategic_recompile`.
  """
  @spec execute(decision(), non_neg_integer(), map(), keyword()) ::
          {:ok, map()} | {:recompile_required, map()} | {:error, term()}
  def execute(decision, handle, inputs, opts \\ [])

  def execute(:strategic_recompile, _handle, inputs, _opts) do
    {:recompile_required, Map.get(inputs, :evidence, %{})}
  end

  def execute(:session_replan, handle, _inputs, opts) do
    evals = opts |> Keyword.get(:evals, 100_000) |> min(@max_evals) |> max(1)
    mem = opts |> Keyword.get(:mem_mb, 64) |> min(@max_mem_mb) |> max(1)

    with {:ok, _} <- Ferroplan.session_drop_plan(handle),
         {:ok, sol} <- Ferroplan.session_think(handle, evals, mem) do
      outcome = if sol["solved"] == true, do: :solved, else: :exhausted

      {:ok,
       %{rung: :session_replan, outcome: outcome, plan: sol["plan"], evals: evals, mem_mb: mem}}
    else
      {:error, reason} -> {:ok, %{rung: :session_replan, outcome: :exhausted, error: reason}}
    end
  end

  def execute(:hddl_replan, _handle, inputs, opts) do
    domain = Map.fetch!(inputs, :hddl_domain)
    problem = Map.fetch!(inputs, :hddl_problem)
    timeout = Keyword.get(opts, :hddl_timeout, 30_000)
    limits = Keyword.get(opts, :limits)

    task = Task.async(fn -> Ferroplan.hddl_solve(domain, problem, limits, timeout: timeout) end)

    case Task.yield(task, timeout + 1_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %{"solved" => true} = plan}} ->
        {:ok, %{rung: :hddl_replan, outcome: :solved, universal_plan: plan}}

      {:ok, {:ok, %{"error" => error}}} ->
        {:ok, %{rung: :hddl_replan, outcome: :no_plan, error: error}}

      {:ok, {:ok, other}} ->
        {:ok, %{rung: :hddl_replan, outcome: :no_plan, error: other}}

      {:ok, {:error, reason}} ->
        {:ok, %{rung: :hddl_replan, outcome: :no_plan, error: reason}}

      nil ->
        {:ok, %{rung: :hddl_replan, outcome: :timeout, timeout_ms: timeout}}

      {:exit, reason} ->
        {:ok, %{rung: :hddl_replan, outcome: :error, error: reason}}
    end
  end

  def execute(:follow_policy, _handle, inputs, opts) do
    case Map.get(inputs, :evidence, %{}) do
      %{action: action} when not is_nil(action) ->
        {:ok, %{rung: :none, outcome: :candidate, action: action, authority: @authority}}

      _ ->
        with {:ok, problem} <- Map.fetch(inputs, :fond_problem) |> ok_or(:missing_fond_problem),
             {:ok, %{"solved" => true} = plan} <-
               Ferroplan.fond_policy("", problem, Keyword.get(opts, :limits)) do
          {:ok, %{rung: :none, outcome: :policy_loaded, universal_plan: plan}}
        else
          {:ok, other} -> {:ok, %{rung: :none, outcome: :no_plan, error: other}}
          {:error, _} = err -> err
        end
    end
  end

  def execute(:suffix_reuse, handle, inputs, _opts) do
    k = inputs |> Map.get(:evidence, %{}) |> Map.get(:suffix_from, 0)

    Enum.reduce_while(1..k//1, :ok, fn _, :ok ->
      case Ferroplan.session_advance(handle) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      :ok ->
        with {:ok, %{"valid" => valid}} <- Ferroplan.session_valid?(handle) do
          {:ok, %{rung: :none, outcome: if(valid, do: :solved, else: :exhausted), advanced: k}}
        end

      err ->
        err
    end
  end

  def execute(:continue, handle, _inputs, _opts) do
    with {:ok, step} <- Ferroplan.session_step(handle) do
      {:ok, %{rung: :none, outcome: :candidate, step: step, authority: @authority}}
    end
  end

  def execute(decision, _handle, _inputs, _opts)
      when decision in [:close, :refuse_stale, :reobserve] do
    {:ok, %{rung: :none, outcome: :noop, decision: decision}}
  end

  @doc """
  Loads a UniversalPlan into `state` via the real `fond_policy` op
  (`problem` = PlanningProblem JSON text).
  """
  @spec load_policy(t(), String.t(), map() | nil) :: {:ok, t()} | {:error, term()}
  def load_policy(%__MODULE__{} = state, problem, limits \\ nil) when is_binary(problem) do
    case Ferroplan.fond_policy("", problem, limits) do
      {:ok, %{"solved" => true} = plan} -> {:ok, %{state | universal_plan: plan}}
      {:ok, other} -> {:error, {:no_policy, other}}
      {:error, _} = err -> err
    end
  end

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(:error, reason), do: {:error, reason}
end
