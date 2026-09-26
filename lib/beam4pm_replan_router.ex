defmodule BeamPM.ReplanRouter do
  @moduledoc """
  Hand-authored replanning ladder over the generated `BeamPM.Ferroplan`
  facade. ferroplan stays mechanism-only (there is no `session_route` op);
  the routing policy lives here so the generated facade is never edited.

  ## Pure core: `route/2`

  `route(observation, state) :: {decision, evidence, state}` checks, in order:

    1. stale preimage -- the observed subject/pack/policy/world digests differ
       from the admitted ones -> `:refuse_stale` + `StalePlanRefusal` (CO-044).
       This fails closed: an observation without a `:preimage` (or missing a
       key) normalizes to `nil` digests, and `new/1` refuses an admitted
       preimage whose four digests are not all non-empty strings, so a
       missing preimage can never match;
       1a. the held UniversalPlan does not digest to the admitted
       `preimage.policy` (`policy_digest/1`) -> `:refuse_stale` with reason
       `:policy_digest_mismatch` -- a mutated policy is never followed;
       1b. a malformed observation (a non-boolean `:goal_met` / `:plan_valid`
       / `:admitted`, an unknown `:conformance`, a bad `:attempt` shape or
       outcome, ...) -> `:refuse_malformed` naming the offending fields.
       A preimage that carries the same field under both an atom and a
       string key is ambiguous and is refused as malformed (field
       `:preimage`) before any digest comparison -- no key wins silently;
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

  An `:attempt` counts only when its rung is the rung the state currently
  holds (`state.rung`, never `:none`); any other attempt is ignored and
  recorded as `:attempt_ignored` in the evidence, so a forged report cannot
  skip rungs. The only admissible outcomes are `:solved` and the planning
  failures `:exhausted` / `:no_plan` / `:timeout`; any other outcome
  (including `:error`) is refused as malformed, so `route/2` itself -- not
  caller discipline -- keeps host faults off the ladder.

  Plan ids: `plan_id` is the root admitted plan; `current_plan_id` is the
  generation being executed. Each ladder step names the new generation
  `"<root>:g<N>:<rung>"`, links it to `current_plan_id` in the lineage, emits
  the `DynamicReplanTrigger` for the plan being REPLACED (`current_plan_id`),
  and then advances `current_plan_id`. The lineage head hash commits to the
  whole chain but is only as trustworthy as where it is anchored: a full
  chain rewrite verifies `:ok` with a different head, so consumers compare
  the head against an externally recorded value.

  The rung never moves down within an episode. A new admitted event (an
  `event_id` not seen before with `admitted: true`) opens a new episode and
  resets the rung, evidenced by `EventTriggeredPlanning` (CO-045). The stale
  check runs before the reset, so a drifted preimage is refused even when it
  arrives with a new event.

  Every decision carries exactly one `BeamPM.Types.OcelEvent` (also appended
  to `state.events`). Its `event_time` is the observation's `:observed_at`
  (an ISO 8601 string) when given, so a replay that supplies the same
  `:observed_at` produces byte-identical events; otherwise wall-clock UTC.

  ## Driver: `observe/3`, `execute/4`

  `observe/3` builds an observation from the real engine session
  (`session_fact` to find unknown facts, `session_observe`,
  `session_goal_met?`, `session_valid?`, `session_plan_valid?` over later
  suffixes). `execute/4` performs a CONSTRUCT-ceiling step for a decision:
  `session_think` (evals <= 1_000_000, mem <= 2048 MB), `hddl_solve` under a
  `Task` timeout, `fond_policy`, `session_advance`. `:strategic_recompile`
  returns `{:recompile_required, evidence}` and never regenerates anything.

  Only planning failures become an outcome that feeds `:attempt`
  (`:exhausted` / `:no_plan` / `:timeout`). A host or session fault (a bad
  handle, the engine not started, a wasmex failure other than a call
  timeout) is returned as `{:error, {:host_fault, reason}}` and must not be
  fed back as an attempt, so infrastructure trouble never climbs the ladder.

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
  @failed_outcomes [:exhausted, :no_plan, :timeout]
  @outcomes [:solved | @failed_outcomes]
  @conformances [nil, :conforms, :deviates]

  # Registered name of the facade's wasmex engine (its child_spec id). Used
  # only to discard an engine whose hddl_solve outlived the Task deadline --
  # the same stop-and-discard the facade itself performs on a call timeout.
  @engine BeamPM.Ferroplan.Engine

  @max_evals 1_000_000
  @max_mem_mb 2048

  @decisions [
    :refuse_stale,
    :refuse_malformed,
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
            current_plan_id: nil,
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
          | :refuse_malformed
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
    * `:attempt` -- `{rung, :solved | :exhausted | :no_plan | :timeout}`
      reporting the previous ladder step's outcome;
    * `:observed_at` -- ISO 8601 timestamp used as the OCEL `event_time`.
  """
  @type observation :: map()

  @type t :: %__MODULE__{
          plan_id: String.t() | nil,
          current_plan_id: String.t() | nil,
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

  Raises `ArgumentError` when any of the four admitted digests is missing or
  not a non-empty string (an empty admitted preimage would otherwise match an
  observation that carries none), or when `:universal_plan` does not digest
  to the admitted `preimage.policy`.
  """
  @spec new(keyword() | map()) :: t()
  def new(opts) do
    opts = Map.new(opts)
    plan_id = Map.fetch!(opts, :plan_id)
    raw_preimage = Map.fetch!(opts, :preimage)

    if (dup = ambiguous_preimage_keys(raw_preimage)) != [] do
      raise ArgumentError,
            "admitted preimage carries #{inspect(dup)} under both atom and string keys"
    end

    preimage = raw_preimage |> normalize_preimage() |> admitted_preimage!()
    universal_plan = Map.get(opts, :universal_plan)

    if universal_plan != nil and policy_digest(universal_plan) != preimage.policy do
      raise ArgumentError,
            "universal_plan digests to #{policy_digest(universal_plan)}, " <>
              "not the admitted preimage.policy #{preimage.policy}"
    end

    run_id = Map.get(opts, :run_id, "replan-" <> String.slice(PlanLineage.digest(plan_id), 0, 12))
    {_link, lineage} = PlanLineage.derive(PlanLineage.new(), plan_id, %{"admitted" => preimage})

    %__MODULE__{
      plan_id: plan_id,
      current_plan_id: plan_id,
      admitted_preimage: preimage,
      universal_plan: universal_plan,
      episode_id: Map.get(opts, :episode_id, run_id <> "-ep0"),
      lineage: lineage,
      run_id: run_id
    }
  end

  @doc """
  Digest a UniversalPlan must have to be followed: the canonical-JSON sha256
  of the plan map. The admitted `preimage.policy` is this value.
  """
  @spec policy_digest(map()) :: String.t()
  def policy_digest(universal_plan) when is_map(universal_plan),
    do: PlanLineage.digest(universal_plan)

  defp admitted_preimage!(preimage) do
    Enum.each(@preimage_keys, fn k ->
      case Map.get(preimage, k) do
        v when is_binary(v) and byte_size(v) > 0 ->
          :ok

        other ->
          raise ArgumentError,
                "admitted preimage #{inspect(k)} must be a non-empty digest string, " <>
                  "got: #{inspect(other)}"
      end
    end)

    preimage
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
    raw_preimage = Map.get(observation, :preimage)
    observed = normalize_preimage(raw_preimage)

    cond do
      (dup = ambiguous_preimage_keys(raw_preimage)) != [] ->
        finish(
          :refuse_malformed,
          %{reason: :ambiguous_preimage, fields: [:preimage], ambiguous_keys: dup},
          %{},
          state
        )

      observed != state.admitted_preimage ->
        refuse_stale(observed, state)

      not policy_admitted?(state) ->
        refuse_policy(state)

      (bad = malformed_fields(observation)) != [] ->
        finish(:refuse_malformed, %{reason: :malformed_observation, fields: bad}, %{}, state)

      true ->
        {reset_evidence, state} = maybe_reset(observation, state)

        {decision, evidence, state} = route_admitted(observation, state)

        evidence =
          if reset_evidence, do: Map.put(evidence, :episode, reset_evidence), else: evidence

        finish(decision, evidence, observation, state)
    end
  end

  defp policy_admitted?(%__MODULE__{universal_plan: nil}), do: true

  defp policy_admitted?(%__MODULE__{universal_plan: plan, admitted_preimage: pre})
       when is_map(plan),
       do: policy_digest(plan) == pre.policy

  defp policy_admitted?(_), do: false

  defp refuse_policy(state) do
    held = if is_map(state.universal_plan), do: policy_digest(state.universal_plan)

    {:ok, refusal} =
      StalePlanRefusal.new(%{
        plan_id: state.current_plan_id,
        admitted_preimage_hash: PlanLineage.digest(state.admitted_preimage),
        observed_preimage_hash: PlanLineage.digest(%{state.admitted_preimage | policy: held})
      })

    evidence = %{
      reason: :policy_digest_mismatch,
      refusal: refusal,
      drifted: [:policy],
      held_policy_digest: held
    }

    finish(:refuse_stale, evidence, %{}, state)
  end

  defp malformed_fields(obs) do
    checks = [
      goal_met: &(is_nil(&1) or is_boolean(&1)),
      plan_valid: &(is_nil(&1) or is_boolean(&1)),
      admitted: &(is_nil(&1) or is_boolean(&1)),
      conformance: &(&1 in @conformances),
      event_id: &(is_nil(&1) or is_binary(&1)),
      unknown_facts: &(is_nil(&1) or (is_list(&1) and Enum.all?(&1, fn f -> is_binary(f) end))),
      suffix_from: &(is_nil(&1) or (is_integer(&1) and &1 >= 0)),
      observed_at: &valid_observed_at?/1,
      attempt: &valid_attempt?/1
    ]

    for {field, ok?} <- checks, not ok?.(Map.get(obs, field)), do: field
  end

  defp valid_attempt?(nil), do: true
  defp valid_attempt?({rung, outcome}) when rung in @rungs and outcome in @outcomes, do: true
  defp valid_attempt?(_), do: false

  defp valid_observed_at?(nil), do: true

  defp valid_observed_at?(t) when is_binary(t),
    do: match?({:ok, _, _}, DateTime.from_iso8601(t))

  defp valid_observed_at?(_), do: false

  defp refuse_stale(observed, state) do
    {:ok, refusal} =
      StalePlanRefusal.new(%{
        plan_id: state.current_plan_id,
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

    if Map.get(observation, :admitted) == true and is_binary(event_id) and
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
    unknown = Map.get(obs, :unknown_facts) || []
    conformance = Map.get(obs, :conformance)

    cond do
      Map.get(obs, :goal_met) == true ->
        close(obs, state)

      unknown != [] ->
        world_invalid = %{
          kind: "WorldModelInvalid",
          plan_id: state.current_plan_id,
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

      conformance == :conforms and Map.get(obs, :plan_valid) == true ->
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
        attempt = Map.get(obs, :attempt)

        evidence =
          if attempt != nil and honored_attempt(state, attempt) == nil,
            do: %{reason: :replan_required, attempt_ignored: attempt},
            else: %{reason: :replan_required}

        ladder_step(next_rung(state, attempt), evidence, obs, state)
    end
  end

  defp close(obs, state) do
    evidence_hash =
      PlanLineage.digest(%{
        "plan_id" => state.current_plan_id,
        "preimage" => state.admitted_preimage,
        "event_id" => Map.get(obs, :event_id),
        "episode_id" => state.episode_id
      })

    {:ok, memory} =
      PlanMemory.new(%{
        plan_id: state.current_plan_id,
        evidence_hash: evidence_hash,
        memory_hash:
          PlanLineage.digest(%{
            "evidence_hash" => evidence_hash,
            "lineage_hash" => PlanLineage.head_hash(state.lineage),
            "plan_id" => state.current_plan_id
          })
      })

    {:close, %{reason: :goal_met, plan_memory: memory}, state}
  end

  @doc """
  Next rung given the current rung and the last attempt outcome. Monotone:
  never returns a rung below `state.rung`. Only an attempt at the rung the
  state currently holds can climb (see `honored_attempt/2`); any other
  attempt is ignored.
  """
  @spec next_rung(t(), {rung(), atom()} | nil) :: rung()
  def next_rung(%__MODULE__{rung: current} = state, attempt) do
    failed_at =
      case honored_attempt(state, attempt) do
        {rung, outcome} when outcome in @failed_outcomes -> rung
        _ -> nil
      end

    base = max_rung(current, failed_at && succ(failed_at))
    if base == :none, do: :session_replan, else: base
  end

  @doc """
  The attempt if it reports on the rung `state` currently holds (a real
  ladder step, not `:none`), else `nil`.
  """
  @spec honored_attempt(t(), term()) :: {rung(), atom()} | nil
  def honored_attempt(%__MODULE__{rung: current}, {current, outcome} = attempt)
      when current != :none and outcome in @outcomes,
      do: attempt

  def honored_attempt(%__MODULE__{}, _attempt), do: nil

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
      "attempt" => attempt_payload(Map.get(obs, :attempt)),
      "episode_id" => state.episode_id,
      "event_id" => Map.get(obs, :event_id),
      "plan_id" => new_plan_id,
      "replaced_plan_id" => state.current_plan_id,
      "root_plan_id" => state.plan_id,
      "rung" => rung
    }

    {:ok, trigger} =
      DynamicReplanTrigger.new(%{
        plan_id: state.current_plan_id,
        event_id: Map.get(obs, :event_id),
        trigger_hash: PlanLineage.digest(trigger_payload)
      })

    {link, lineage} = PlanLineage.derive(state.lineage, new_plan_id, trigger_payload)

    evidence = Map.merge(evidence, %{rung: rung, trigger: trigger, lineage: link})

    {rung, evidence,
     %{
       state
       | rung: rung,
         generation: generation,
         lineage: lineage,
         current_plan_id: new_plan_id
     }}
  end

  # Canonical-JSON rendering of an attempt: `nil` or `[rung, outcome]` as
  # strings, so the trigger hash never depends on `inspect/1` formatting.
  defp attempt_payload(nil), do: nil
  defp attempt_payload({rung, outcome}), do: [Atom.to_string(rung), Atom.to_string(outcome)]

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
      event(state, ordinal, "replan_router." <> Atom.to_string(decision), event_time(obs), %{
        "decision" => Atom.to_string(decision),
        "reason" => evidence |> Map.get(:reason) |> to_string(),
        "plan_id" => state.current_plan_id,
        "root_plan_id" => state.plan_id,
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
  defp event(state, ordinal, event_type, event_time, extra_attrs) do
    run_id = state.run_id

    {:ok, ev} =
      OcelEvent.new(%{
        event_id: "#{run_id}-#{ordinal}-#{event_type}",
        event_type: event_type,
        event_time: event_time,
        attributes: Map.merge(%{"case_id" => run_id}, extra_attrs)
      })

    ev
  end

  # Only a validated observation (`finish/4` receives `%{}` for refusals)
  # can supply its own time.
  defp event_time(obs) do
    case Map.get(obs, :observed_at) do
      t when is_binary(t) -> t
      _ -> DateTime.utc_now() |> DateTime.to_iso8601()
    end
  end

  # Preimage fields present under both the atom and the string key.
  defp ambiguous_preimage_keys(preimage) when is_map(preimage) do
    Enum.filter(@preimage_keys, fn k ->
      Map.has_key?(preimage, k) and Map.has_key?(preimage, Atom.to_string(k))
    end)
  end

  defp ambiguous_preimage_keys(_), do: []

  defp normalize_preimage(preimage) when is_map(preimage) do
    Map.new(@preimage_keys, fn k ->
      {k, Map.get(preimage, k, Map.get(preimage, Atom.to_string(k)))}
    end)
  end

  defp normalize_preimage(_missing), do: Map.new(@preimage_keys, &{&1, nil})

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
  `:strategic_recompile`. Every decision in `decisions/0` has a clause:
  `:close`, `:refuse_stale`, `:refuse_malformed` and `:reobserve` are
  `:noop`. `:hddl_replan` without binary `:hddl_domain` / `:hddl_problem`
  returns `{:error, {:missing_inputs, fields}}` and touches no engine.
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
    think_opts = if t = Keyword.get(opts, :think_timeout), do: [timeout: t], else: []
    base = %{rung: :session_replan, evals: evals, mem_mb: mem}

    # A drop_plan failure is a session fault (bad handle, engine gone), never
    # a planning outcome.
    with {:dropped, {:ok, _}} <- {:dropped, Ferroplan.session_drop_plan(handle)},
         {:ok, sol} <- Ferroplan.session_think(handle, evals, mem, think_opts) do
      outcome = if sol["solved"] == true, do: :solved, else: :exhausted
      {:ok, Map.merge(base, %{outcome: outcome, plan: sol["plan"]})}
    else
      {:dropped, {:error, reason}} -> {:error, {:host_fault, reason}}
      {:error, reason} -> classify_failure(base, :exhausted, reason)
    end
  end

  def execute(:hddl_replan, handle, inputs, opts) do
    case Enum.reject([:hddl_domain, :hddl_problem], &is_binary(Map.get(inputs, &1))) do
      [] -> hddl_replan(handle, inputs.hddl_domain, inputs.hddl_problem, opts)
      missing -> {:error, {:missing_inputs, missing}}
    end
  end

  def execute(:follow_policy, _handle, inputs, opts) do
    follow_policy(inputs, opts)
  end

  def execute(:suffix_reuse, handle, inputs, _opts) do
    suffix_reuse(handle, inputs)
  end

  def execute(:continue, handle, _inputs, _opts) do
    with {:ok, step} <- Ferroplan.session_step(handle) do
      {:ok, %{rung: :none, outcome: :candidate, step: step, authority: @authority}}
    end
  end

  def execute(decision, _handle, _inputs, _opts)
      when decision in [:close, :refuse_stale, :refuse_malformed, :reobserve] do
    {:ok, %{rung: :none, outcome: :noop, decision: decision}}
  end

  defp hddl_replan(_handle, domain, problem, opts) do
    timeout = Keyword.get(opts, :hddl_timeout, 30_000)
    grace = Keyword.get(opts, :task_grace_ms, 1_000)
    limits = Keyword.get(opts, :limits)
    base = %{rung: :hddl_replan}

    # The Task deadline (`timeout`) is the governing wall bound: the facade's
    # own call timeout is set `grace` ms later so it never pre-empts it. On
    # the deadline the Task is killed and the engine discarded (the solve is
    # not preemptible inside the guest), exactly like the facade's own
    # call-timeout path: every session handle is invalid afterwards.
    task =
      Task.async(fn ->
        Ferroplan.hddl_solve(domain, problem, limits, timeout: timeout + grace)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %{"solved" => true} = plan}} ->
        {:ok, Map.merge(base, %{outcome: :solved, universal_plan: plan})}

      {:ok, {:ok, %{"error" => error}}} ->
        {:ok, Map.merge(base, %{outcome: :no_plan, error: error})}

      {:ok, {:ok, other}} ->
        {:ok, Map.merge(base, %{outcome: :no_plan, error: other})}

      {:ok, {:error, reason}} ->
        classify_failure(base, :no_plan, reason)

      nil ->
        discard_engine()

        {:ok, Map.merge(base, %{outcome: :timeout, timeout_ms: timeout, engine_restarted: true})}

      {:exit, reason} ->
        {:error, {:host_fault, {:exit, reason}}}
    end
  end

  defp follow_policy(inputs, opts) do
    case Map.get(inputs, :evidence, %{}) do
      %{action: action} when not is_nil(action) ->
        {:ok, %{rung: :none, outcome: :candidate, action: action, authority: @authority}}

      _ ->
        with {:ok, problem} <- Map.fetch(inputs, :fond_problem) |> ok_or(:missing_fond_problem),
             {:ok, %{"solved" => true} = plan} <-
               Ferroplan.fond_policy("", problem, Keyword.get(opts, :limits)) do
          {:ok,
           %{
             rung: :none,
             outcome: :policy_loaded,
             universal_plan: plan,
             policy_digest: policy_digest(plan)
           }}
        else
          {:ok, other} -> {:ok, %{rung: :none, outcome: :no_plan, error: other}}
          {:error, _} = err -> err
        end
    end
  end

  defp suffix_reuse(handle, inputs) do
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

  @doc """
  Loads a UniversalPlan into `state` via the real `fond_policy` op
  (`problem` = PlanningProblem JSON text). The synthesized plan is admitted
  only if it digests to the admitted `preimage.policy`; otherwise
  `{:error, {:policy_digest_mismatch, %{admitted: _, observed: _}}}` and the
  state is unchanged.
  """
  @spec load_policy(t(), String.t(), map() | nil) :: {:ok, t()} | {:error, term()}
  def load_policy(%__MODULE__{} = state, problem, limits \\ nil) when is_binary(problem) do
    case Ferroplan.fond_policy("", problem, limits) do
      {:ok, %{"solved" => true} = plan} ->
        observed = policy_digest(plan)

        if observed == state.admitted_preimage.policy,
          do: {:ok, %{state | universal_plan: plan}},
          else:
            {:error,
             {:policy_digest_mismatch,
              %{admitted: state.admitted_preimage.policy, observed: observed}}}

      {:ok, other} ->
        {:error, {:no_policy, other}}

      {:error, _} = err ->
        err
    end
  end

  # Engine-reported refusals are planning failures; a wasmex call timeout is
  # a :timeout outcome; anything else is a host fault that must not climb.
  defp classify_failure(base, _planning_outcome, {:wasmex, {:engine_restarted, reason}} = err) do
    if call_timeout?(reason),
      do: {:ok, Map.merge(base, %{outcome: :timeout, engine_restarted: true, error: err})},
      else: {:error, {:host_fault, err}}
  end

  defp classify_failure(base, planning_outcome, {:engine, _} = err),
    do: {:ok, Map.merge(base, %{outcome: planning_outcome, error: err})}

  defp classify_failure(_base, _planning_outcome, reason), do: {:error, {:host_fault, reason}}

  defp call_timeout?({:call_exit, {:timeout, _}}), do: true
  defp call_timeout?(_), do: false

  defp discard_engine do
    case Process.whereis(@engine) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          5_000 -> :ok
        end
    end
  end

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(:error, reason), do: {:error, reason}
end
