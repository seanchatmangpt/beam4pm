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
  arrives with a new event. `admitted: true` is asserted by the caller, so
  resets are bounded: at most `:max_episodes` (default 8) new episodes per router; a further fresh admitted event is recorded
  as seen but does NOT reset the rung, and the evidence carries
  `episode_refused: %{reason: :episode_budget_exhausted, ...}`. A forged
  stream of fresh event ids therefore cannot hold the ladder at the bottom
  forever -- it climbs to `:strategic_recompile` like any other failure run.

  Key discipline: an observation (or `new/1` options) whose top-level keys
  are not atoms is refused (`:refuse_malformed`, reason `:non_atom_keys`;
  `new/1` raises `ArgumentError`), so a `"goal_met"` string key is never
  dropped silently. Unknown `new/1` option keys raise `ArgumentError`.

  Policy equivalence: `policy_digest/1` renders atoms as strings, so a plan
  and its all-string twin share a digest. Following uses the SAME
  equivalence -- `:policy_state` and each entry's `"state"` are compared by
  their canonical JSON (`PlanLineage.canonical_json/1`), and `"policy"` /
  `"state"` / `"action"` are read under either the string or the atom key --
  so anything the digest admits is followed identically.

  Every decision carries exactly one `BeamPM.Types.OcelEvent`, also recorded
  in the state and read back oldest-first with `events/1` (stored
  newest-first in `events_rev`, so recording one is O(1) however long the
  run -- the benchmark court in `bench/replan_router_bench.exs` bounds
  per-decision cost against history length). Its `event_time` is the observation's `:observed_at`
  (an ISO 8601 string) when it is valid -- for refusals
  (`:refuse_stale` / `:refuse_malformed`) too -- so a replay that supplies
  the same `:observed_at` produces byte-identical events for every
  decision; wall-clock UTC is used only when no valid `:observed_at` is
  supplied.

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

  @default_max_episodes 8
  @new_opts [:plan_id, :preimage, :universal_plan, :run_id, :episode_id, :max_episodes]

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
            events_rev: [],
            ordinal: 0,
            run_id: nil,
            episodes: 0,
            max_episodes: @default_max_episodes

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
          events_rev: [OcelEvent.t()],
          ordinal: non_neg_integer(),
          run_id: String.t() | nil,
          episodes: non_neg_integer(),
          max_episodes: non_neg_integer()
        }

  @doc "Every OCEL event recorded by `route/2`, oldest first."
  @spec events(t()) :: [OcelEvent.t()]
  def events(%__MODULE__{events_rev: rev}), do: Enum.reverse(rev)

  @doc "All decisions `route/2` can return."
  @spec decisions() :: [decision()]
  def decisions, do: @decisions

  @doc "Ladder rungs in climb order."
  @spec rungs() :: [rung()]
  def rungs, do: @rungs

  @doc """
  New router state bound to an admitted plan and preimage. Options:
  `:plan_id` (required, non-empty string), `:preimage` (required,
  subject/pack/policy/world digests), `:universal_plan` (a UniversalPlan
  map), `:run_id`, `:episode_id` (non-empty strings), `:max_episodes`
  (non-negative integer, default #{@default_max_episodes}: the bound on
  event-triggered rung resets).

  Raises `ArgumentError` -- never `FunctionClauseError` / `KeyError` -- when
  the options are not a keyword list or atom-keyed map, carry an unknown or
  non-atom key, miss a required key, carry a wrongly typed value, when any of
  the four admitted digests is missing or not a non-empty string (an empty
  admitted preimage would otherwise match an observation that carries none),
  or when `:universal_plan` does not digest to the admitted
  `preimage.policy`.
  """
  @spec new(keyword() | map()) :: t()
  def new(opts) do
    opts = new_opts!(opts)
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
      run_id: run_id,
      max_episodes: Map.get(opts, :max_episodes, @default_max_episodes)
    }
  end

  # Every malformed option is an ArgumentError naming the offending key.
  defp new_opts!(opts) when is_map(opts), do: check_new_opts!(opts)

  defp new_opts!(opts) when is_list(opts) do
    if Enum.all?(opts, &match?({k, _} when is_atom(k), &1)),
      do: check_new_opts!(Map.new(opts)),
      else: raise(ArgumentError, "options must be a keyword list or map, got: #{inspect(opts)}")
  end

  defp new_opts!(opts),
    do: raise(ArgumentError, "options must be a keyword list or map, got: #{inspect(opts)}")

  defp check_new_opts!(opts) do
    case Enum.reject(Map.keys(opts), &(&1 in @new_opts)) do
      [] ->
        :ok

      bad ->
        raise ArgumentError,
              "unknown or non-atom option keys #{inspect(bad)} (allowed: #{inspect(@new_opts)})"
    end

    for k <- [:plan_id, :preimage], not Map.has_key?(opts, k) do
      raise ArgumentError, "missing required option #{inspect(k)}"
    end

    for k <- [:plan_id, :run_id, :episode_id],
        Map.has_key?(opts, k),
        not (is_binary(opts[k]) and byte_size(opts[k]) > 0) do
      raise ArgumentError,
            "option #{inspect(k)} must be a non-empty string, got: #{inspect(opts[k])}"
    end

    unless is_map(opts.preimage) do
      raise ArgumentError, "option :preimage must be a map, got: #{inspect(opts.preimage)}"
    end

    unless Map.get(opts, :universal_plan) == nil or is_map(opts.universal_plan) do
      raise ArgumentError,
            "option :universal_plan must be a map or nil, got: #{inspect(opts.universal_plan)}"
    end

    case Map.get(opts, :max_episodes, @default_max_episodes) do
      n when is_integer(n) and n >= 0 ->
        :ok

      other ->
        raise ArgumentError,
              "option :max_episodes must be a non-negative integer, got: #{inspect(other)}"
    end

    opts
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
    # Refusals never echo unvalidated fields, but they DO take a valid
    # :observed_at so a replay is byte-identical for every decision.
    clock = refusal_clock(observation)

    cond do
      (keys = non_atom_keys(observation)) != [] ->
        finish(
          :refuse_malformed,
          %{reason: :non_atom_keys, fields: [:keys], non_atom_keys: keys},
          clock,
          state
        )

      (dup = ambiguous_preimage_keys(raw_preimage)) != [] ->
        finish(
          :refuse_malformed,
          %{reason: :ambiguous_preimage, fields: [:preimage], ambiguous_keys: dup},
          clock,
          state
        )

      observed != state.admitted_preimage ->
        refuse_stale(observed, clock, state)

      not policy_admitted?(state) ->
        refuse_policy(clock, state)

      (bad = malformed_fields(observation)) != [] ->
        finish(:refuse_malformed, %{reason: :malformed_observation, fields: bad}, clock, state)

      true ->
        {reset_evidence, state} = maybe_reset(observation, state)

        {decision, evidence, state} = route_admitted(observation, state)

        evidence =
          case reset_evidence do
            nil -> evidence
            {:refused, refused} -> Map.put(evidence, :episode_refused, refused)
            etp -> Map.put(evidence, :episode, etp)
          end

        finish(decision, evidence, observation, state)
    end
  end

  defp policy_admitted?(%__MODULE__{universal_plan: nil}), do: true

  defp policy_admitted?(%__MODULE__{universal_plan: plan, admitted_preimage: pre})
       when is_map(plan),
       do: policy_digest(plan) == pre.policy

  defp policy_admitted?(_), do: false

  defp refusal_clock(obs) do
    case Map.get(obs, :observed_at) do
      t when is_binary(t) -> if valid_observed_at?(t), do: %{observed_at: t}, else: %{}
      _ -> %{}
    end
  end

  defp non_atom_keys(obs), do: obs |> Map.keys() |> Enum.reject(&is_atom/1) |> Enum.sort()

  defp refuse_policy(clock, state) do
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

    finish(:refuse_stale, evidence, clock, state)
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
      attempt: &valid_attempt?/1,
      policy_state: &valid_policy_state?/1
    ]

    for {field, ok?} <- checks, not ok?.(Map.get(obs, field)), do: field
  end

  defp valid_attempt?(nil), do: true
  defp valid_attempt?({rung, outcome}) when rung in @rungs and outcome in @outcomes, do: true
  defp valid_attempt?(_), do: false

  # A policy state id must have a canonical JSON scalar form; booleans are
  # never state ids.
  defp valid_policy_state?(nil), do: true
  defp valid_policy_state?(b) when is_boolean(b), do: false
  defp valid_policy_state?(s) when is_binary(s) or is_atom(s) or is_integer(s), do: true
  defp valid_policy_state?(_), do: false

  defp valid_observed_at?(nil), do: true

  defp valid_observed_at?(t) when is_binary(t),
    do: match?({:ok, _, _}, DateTime.from_iso8601(t))

  defp valid_observed_at?(_), do: false

  defp refuse_stale(observed, clock, state) do
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
    finish(:refuse_stale, evidence, clock, state)
  end

  defp maybe_reset(observation, state) do
    event_id = Map.get(observation, :event_id)

    fresh? =
      Map.get(observation, :admitted) == true and is_binary(event_id) and
        not MapSet.member?(state.seen_events, event_id)

    cond do
      fresh? and state.episodes >= state.max_episodes ->
        # Budget spent: remember the event (a replay stays a replay) but keep
        # the rung -- a self-asserted event stream cannot pin the ladder low.
        refused = %{
          reason: :episode_budget_exhausted,
          event_id: event_id,
          episodes: state.episodes,
          max_episodes: state.max_episodes
        }

        {{:refused, refused}, %{state | seen_events: MapSet.put(state.seen_events, event_id)}}

      fresh? ->
        open_episode(event_id, state)

      true ->
        {nil, state}
    end
  end

  defp open_episode(event_id, state) do
    episodes = state.episodes + 1
    episode_id = "#{state.run_id}-ep#{episodes}"

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
         episodes: episodes,
         seen_events: MapSet.put(state.seen_events, event_id)
     }}
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

  # Same equivalence as policy_digest/1: keys and state ids are compared by
  # their canonical JSON form, so an atom and its string twin -- which the
  # digest cannot tell apart -- are followed identically.
  defp policy_action(plan, policy_state) when is_map(plan) do
    wanted = PlanLineage.canonical_json(policy_state)

    case either_key(plan, "policy", :policy) do
      entries when is_list(entries) ->
        Enum.find_value(entries, fn
          entry when is_map(entry) ->
            state_id = either_key(entry, "state", :state)

            if state_id != nil and PlanLineage.canonical_json(state_id) == wanted,
              do: either_key(entry, "action", :action)

          _ ->
            nil
        end)

      _ ->
        nil
    end
  end

  defp policy_action(_, _), do: nil

  # A map that carries both forms fails policy_digest/1 (duplicate rendered
  # key), so it can never be admitted; reading either form is unambiguous.
  defp either_key(map, key, atom), do: Map.get(map, key, Map.get(map, atom))

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

    {decision, evidence, %{state | ordinal: ordinal, events_rev: [event | state.events_rev]}}
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

  def execute(:session_replan, handle, inputs, opts) do
    evals = opts |> Keyword.get(:evals, 100_000) |> min(@max_evals) |> max(1)
    mem = opts |> Keyword.get(:mem_mb, 64) |> min(@max_mem_mb) |> max(1)
    think_opts = if t = Keyword.get(opts, :think_timeout), do: [timeout: t], else: []
    base = %{rung: :session_replan, evals: evals, mem_mb: mem}

    # A drop_plan failure is a session fault (bad handle, engine gone), never
    # a planning outcome.
    with {:dropped, {:ok, _}} <- {:dropped, Ferroplan.session_drop_plan(handle)},
         {:ok, sol} <- Ferroplan.session_think(handle, evals, mem, think_opts) do
      outcome = if sol["solved"] == true, do: :solved, else: :exhausted
      admit_candidate(inputs, outcome, Map.merge(base, %{outcome: outcome, plan: sol["plan"]}))
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

  # Independent admission (graphlaw): when `inputs[:admission]` is present a
  # solved candidate plan is replayed by BeamPM.PlanAdmission and refused at
  # the first unmet precondition/goal. Fails closed if the court is unreachable.
  # Fail-closed default (`config :beam4pm, :admission_mode`, see
  # BeamPM.GraphlawAdmission.mode/0): in `:required` mode a solved candidate
  # with no admission spec is refused `{:admission_missing, reason}`;
  # `admission: :skip` (or `:skip` mode) explicitly opts out.
  defp admit_candidate(%{admission: %{} = admission}, :solved, result) do
    case BeamPM.PlanAdmission.admit(result.plan, admission) do
      {:ok, admitted} -> {:ok, Map.put(result, :admission, admitted)}
      {:error, {:refused, refusal}} -> {:error, {:plan_refused, refusal}}
      {:error, reason} -> {:error, {:admission_unavailable, reason}}
    end
  end

  defp admit_candidate(%{admission: :skip}, _outcome, result), do: {:ok, result}

  defp admit_candidate(_inputs, :solved, result) do
    case BeamPM.GraphlawAdmission.mode() do
      :required ->
        {:error,
         {:admission_missing,
          "admission_mode is :required and inputs carry no :admission spec " <>
            "(pass admission: %{state:, model:, goal:} or admission: :skip)"}}

      :skip ->
        {:ok, result}
    end
  end

  defp admit_candidate(_inputs, _outcome, result), do: {:ok, result}

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
  state is unchanged. The graphlaw court runs by default in `:required`
  admission mode (`graphlaw_court: false` opts out); an unreachable court is
  `{:error, {:admission_unavailable, _}}`.
  """
  @spec load_policy(t(), String.t(), map() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def load_policy(%__MODULE__{} = state, problem, limits \\ nil, opts \\ [])
      when is_binary(problem) do
    case Ferroplan.fond_policy("", problem, limits) do
      {:ok, %{"solved" => true} = plan} ->
        observed = policy_digest(plan)

        cond do
          observed != state.admitted_preimage.policy ->
            {:error,
             {:policy_digest_mismatch,
              %{admitted: state.admitted_preimage.policy, observed: observed}}}

          Keyword.get(opts, :graphlaw_court, BeamPM.GraphlawAdmission.mode() == :required) ->
            # Independent strong-cyclic admission (graphlaw); fails closed.
            case BeamPM.GraphlawAdmission.admit_policy(problem, plan) do
              {:ok, _admitted} -> {:ok, %{state | universal_plan: plan}}
              {:error, {:refused, refusal}} -> {:error, {:policy_refused, refusal}}
              {:error, reason} -> {:error, {:admission_unavailable, reason}}
            end

          true ->
            {:ok, %{state | universal_plan: plan}}
        end

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

# ---------------------------------------------------------------------------
# graphlaw admission helpers (folded into this admitted facade so the
# bpm:AuthorshipKind_native_engine_facade debt ceiling (gates/070) holds).
# The Wasmex host itself, BeamPM.Graphlaw, is GENERATED (lib/beam4pm_graphlaw.ex).
# ---------------------------------------------------------------------------

defmodule BeamPM.GraphlawAdmission do
  @moduledoc ~S"""
  Host-side admission helpers over the GENERATED `BeamPM.Graphlaw` engine
  (lib/beam4pm_graphlaw.ex, rendered from the `bap:engine_graphlaw`
  bpm:Engine facts): frames RDF triples, PDDL-derived plans and SHACL shapes
  into the two graphlaw wire ops (`law`, `policy`). The wasmex hosting, the
  `gl_alloc` / `gl_call` / `gl_free` wire and the `{"ok": false}` ->
  `{:error, {:refused, %{kind, engine, dialect, message}}}` collapse are
  generated; only this triple/JSON framing is hand-written.
  """

  alias BeamPM.Graphlaw

  require Logger

  @timeout 30_000

  # Documented ABI constant: graphlaw's `capabilities` reports `abi_version`.
  @expected_abi_version 1
  @pin_rel "native/graphlaw/graphlaw_wasm.wasm.sha256"

  @type result :: {:ok, map()} | {:error, {:refused, map()} | {:wasmex, term()}}

  defdelegate start(), to: Graphlaw
  defdelegate wasm_built?(), to: Graphlaw
  defdelegate wasm_missing_reason(), to: Graphlaw

  @doc """
  Replays a candidate plan over `state` (a list of `{subject, predicate, object}`
  IRI triples). `actions` is a list of `%{name:, pre:, add:, del:}` (triple
  lists); `goal` is a triple list. Returns `{:ok, %{states, receipts, nquads}}`
  (one receipt per action) or `{:error, {:refused, refusal}}` at the first
  unmet precondition / goal.
  """
  @spec admit_plan([tuple()], [map()], [tuple()], keyword()) :: result()
  def admit_plan(state, actions, goal, opts \\ []) when is_list(state) and is_list(actions) do
    plan = %{
      "actions" =>
        Enum.map(actions, fn a ->
          %{
            "name" => to_string(Map.fetch!(a, :name)),
            "pre" => nt(Map.get(a, :pre, [])),
            "add" => nt(Map.get(a, :add, [])),
            "del" => nt(Map.get(a, :del, []))
          }
        end),
      "goal" => nt(goal)
    }

    law(state, [%{"step" => "plan", "plan" => plan}], opts)
  end

  @doc """
  SHACL admission gate: `{:ok, resp}` iff the `state` triples conform to the
  Turtle `shapes_ttl`; otherwise `{:error, {:refused, refusal}}`. Never
  changes the state.
  """
  @spec admit_shacl([tuple()] | String.t(), String.t(), keyword()) :: result()
  def admit_shacl(state, shapes_ttl, opts \\ []) when is_binary(shapes_ttl) do
    law(state, [%{"step" => "shacl", "shapes" => shapes_ttl}], opts)
  end

  @doc """
  Independent FOND policy admission: `problem` and `policy` (a ferroplan
  `UniversalPlan` map or its `policy` entries) are checked strong-cyclic by
  the graphlaw court. `{:ok, admitted}` or `{:error, {:refused, refusal}}`.
  """
  @spec admit_policy(map() | String.t(), map() | list() | String.t(), keyword()) :: result()
  def admit_policy(problem, policy, opts \\ []) do
    problem = if is_binary(problem), do: JSON.decode!(problem), else: problem
    Graphlaw.policy(problem, policy, timeout: Keyword.get(opts, :timeout, @timeout))
  end

  @doc "Raw `law` op: `state` is triples or an N-Triples/Turtle string; `steps` per the graphlaw ABI."
  @spec law([tuple()] | String.t(), [map()], keyword()) :: result()
  def law(state, steps, opts \\ []) do
    {text, dialect} =
      if is_binary(state),
        do: {state, Keyword.get(opts, :dialect, "turtle")},
        else: {nt(state), "ntriples"}

    Graphlaw.law(%{"text" => text, "dialect" => dialect}, steps,
      timeout: Keyword.get(opts, :timeout, @timeout)
    )
  end

  @doc """
  Admission mode: `config :beam4pm, :admission_mode, :required | :skip`
  (default `:required`, fail-closed; any other value is read as `:required`).
  `:required` makes the router, `load_policy/4` and `admit_deviation/5` run the
  graphlaw court unless the call explicitly opts out (`admission: :skip`,
  `graphlaw_court: false`, `graphlaw_gate: false`).
  """
  @spec mode() :: :required | :skip
  def mode do
    case Application.get_env(:beam4pm, :admission_mode, :required) do
      :skip -> :skip
      _ -> :required
    end
  end

  @doc "The `abi_version` the graphlaw court must report from `capabilities`."
  @spec expected_abi_version() :: pos_integer()
  def expected_abi_version, do: @expected_abi_version

  @doc "Default pin file: sha256 of the installed wasm, written by scripts/graphlaw_wasm_fetch.sh."
  @spec pin_path() :: String.t()
  def pin_path, do: Path.expand(@pin_rel)

  @doc """
  Compares the sha256 of the wasm at `path` to the pin in `pin_path`.
  `:ok` | `{:error, {:artifact_missing | :pin_missing | :pin_mismatch, _}}`.
  """
  @spec verify_artifact(String.t(), String.t()) :: :ok | {:error, term()}
  def verify_artifact(path \\ Graphlaw.wasm_path(), pin_path \\ pin_path()) do
    with {:ok, bytes} <- File.read(path) |> tag(:artifact_missing, path),
         {:ok, pin} <- File.read(pin_path) |> tag(:pin_missing, pin_path) do
      expected = pin |> String.split() |> List.first("") |> String.downcase()
      actual = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

      if actual == expected,
        do: :ok,
        else: {:error, {:pin_mismatch, %{path: path, expected: expected, actual: actual}}}
    end
  end

  defp tag({:ok, _} = ok, _kind, _path), do: ok
  defp tag({:error, reason}, kind, path), do: {:error, {kind, %{path: path, reason: reason}}}

  @doc """
  ABI handshake against the RUNNING engine: `:ok` iff `capabilities` reports
  `abi_version == expected_abi_version/0`.
  """
  @spec handshake() :: :ok | {:error, term()}
  def handshake do
    case Graphlaw.capabilities() do
      {:ok, %{"abi_version" => v}} when v == @expected_abi_version -> :ok
      {:ok, other} -> {:error, {:abi_mismatch, %{expected: @expected_abi_version, got: other["abi_version"]}}}
      {:error, _} = err -> err
    end
  end

  @doc """
  True iff the engine process is alive AND the wasm pin verifies AND the ABI
  handshake succeeds. Never starts an engine.
  """
  @spec ready?() :: boolean()
  def ready? do
    is_pid(Process.whereis(BeamPM.Graphlaw.Engine)) and verify_artifact() == :ok and
      handshake() == :ok
  end

  @doc """
  Engine child specs for BeamPM.Application: the graphlaw and ferroplan engines
  whose wasm artifact exists (a missing artifact logs a warning; a graphlaw
  artifact failing `verify_artifact/0` logs an error and is NOT started).
  """
  @spec engine_children() :: [Supervisor.child_spec()]
  def engine_children do
    graphlaw =
      cond do
        not Graphlaw.wasm_built?() ->
          Logger.warning("graphlaw engine not started: " <> Graphlaw.wasm_missing_reason())
          []

        (v = verify_artifact()) != :ok ->
          Logger.error("graphlaw engine refused at boot (wasm pin): #{inspect(v)}")
          []

        true ->
          [Graphlaw.child_spec([])]
      end

    ferroplan =
      if BeamPM.Ferroplan.wasm_built?() do
        [BeamPM.Ferroplan.child_spec([])]
      else
        Logger.warning("ferroplan engine not started: " <> BeamPM.Ferroplan.wasm_missing_reason())
        []
      end

    graphlaw ++ ferroplan
  end

  @doc "Renders IRI triples as N-Triples text."
  @spec nt([tuple()]) :: String.t()
  def nt(triples) do
    Enum.map_join(triples, fn {s, p, o} -> "<#{s}> <#{p}> <#{o}> .\n" end)
  end
end

defmodule BeamPM.PlanAdmission do
  @moduledoc ~S"""
  Independent admission of a planner's candidate plan. ferroplan proposes
  (`authority: candidate_only`); `BeamPM.GraphlawAdmission` replays the plan over an
  RDF state and refuses at the first violated precondition or an unmet goal.

  An `admission` spec is `%{state: triples, model: model, goal: triples}`:

    * `state` -- initial ground atoms, `{subject, predicate, object}` IRI triples
    * `model` -- the plan step's `"action"` name => `%{pre:, add:, del:}` triple
      lists, or a 1-arity function of the step's `"args"` returning that map
    * `goal`  -- triples that must hold after the last action

  Fails closed: an action missing from `model` is a refusal, not a skip.
  """

  alias BeamPM.GraphlawAdmission

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
         {:ok, resp} <- GraphlawAdmission.admit_plan(state, actions, goal, opts) do
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

defmodule BeamPM.ActionModel do
  @moduledoc ~S"""
  Derives a `BeamPM.PlanAdmission` admission spec (`%{state:, model:, goal:}`)
  from PDDL text, so callers do not hand-write action models.

  Supported subset: STRIPS + typing. Action `:parameters`, `:precondition`
  as a conjunction of positive atoms, `:effect` as a conjunction of atoms
  (add) and `(not atom)` (delete); problem `:init` atoms and `:goal`
  conjunction of positive atoms. Anything else is refused with
  `{:error, {:unsupported, what}}` -- never guessed: `or`, `not` in a
  precondition or goal, `forall`, `exists`, `imply`, `when`, `=`, numeric
  fluents (`:functions`, `increase`, `decrease`, `assign`, comparisons),
  durative actions, `either` types, predicates of arity above 2.

  ## Atom to triple scheme (same as test/beam4pm_graphlaw_test.exs)

  Objects are uppercased (as ferroplan reports them) and become
  `"urn:r:OBJ"`; predicates are lowercased and become `"urn:p:pred"`.

    * `(at a)`      => `{"urn:r:A", "urn:p:at", "urn:p:true"}`
    * `(link a b)`  => `{"urn:r:A", "urn:p:link", "urn:r:B"}`
    * `(p)` (arity 0) => `{"urn:r:_", "urn:p:p", "urn:p:true"}`

  The model maps the uppercased action name to a function of the plan
  step's `"args"`; an arity mismatch yields an unsatisfiable precondition so
  the step is refused rather than skipped.
  """

  @type triple :: {String.t(), String.t(), String.t()}
  @type spec :: %{state: [triple()], model: %{String.t() => (list() -> map())}, goal: [triple()]}

  @unsupported_ops ~w(or not forall exists imply when = increase decrease assign
                      scale-up scale-down > < >= <= + - * / at-start at-end over)

  @spec from_pddl(String.t(), String.t()) :: {:ok, spec()} | {:error, term()}
  def from_pddl(domain_pddl, problem_pddl) do
    with {:ok, dom} <- parse(domain_pddl),
         {:ok, prob} <- parse(problem_pddl),
         {:ok, actions} <- actions(dom),
         {:ok, init} <- init(prob),
         {:ok, goal} <- goal(prob) do
      model =
        Map.new(actions, fn {name, params, pre, add, del} ->
          {name, build(params, pre, add, del)}
        end)

      {:ok, %{state: Enum.map(init, &triple/1), model: model, goal: Enum.map(goal, &triple/1)}}
    end
  end

  # ---- s-expression parsing -------------------------------------------------

  defp parse(text) when is_binary(text) do
    tokens =
      text
      |> String.replace(~r/;[^\n]*/, "")
      |> String.replace("(", " ( ")
      |> String.replace(")", " ) ")
      |> String.split()

    case read(tokens) do
      {:ok, [sexp], []} -> {:ok, sexp}
      _ -> {:error, {:parse, "malformed PDDL s-expression"}}
    end
  end

  defp read(["(" | rest]), do: read_list(rest, [])

  defp read([tok | rest]) when tok != ")",
    do: {:ok, [String.downcase(tok)], rest}

  defp read(_), do: {:error, :eof}

  defp read_list([")" | rest], acc), do: {:ok, [Enum.reverse(acc)], rest}
  defp read_list([], _), do: {:error, :eof}

  defp read_list(["(" | _] = toks, acc) do
    with {:ok, [x], rest} <- read(toks), do: read_list(rest, [x | acc])
  end

  defp read_list([tok | rest], acc), do: read_list(rest, [String.downcase(tok) | acc])

  # ---- domain ---------------------------------------------------------------

  defp actions(["define", _name | sections]) do
    Enum.reduce_while(sections, {:ok, []}, fn
      [":functions" | _], _ ->
        {:halt, {:error, {:unsupported, "numeric fluents (:functions)"}}}

      [":durative-action" | _], _ ->
        {:halt, {:error, {:unsupported, "durative actions"}}}

      [":types" | types], acc ->
        if Enum.any?(types, &(&1 == "either")),
          do: {:halt, {:error, {:unsupported, "either types"}}},
          else: {:cont, acc}

      [":action", name | body], {:ok, acc} ->
        case action(name, body) do
          {:ok, a} -> {:cont, {:ok, [a | acc]}}
          err -> {:halt, err}
        end

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp actions(_), do: {:error, {:parse, "not a PDDL domain"}}

  defp action(name, body) do
    kv = pairs(body)
    params = params(Map.get(kv, ":parameters", []))

    with :ok <- check_types(Map.get(kv, ":parameters", [])),
         {:ok, pre} <- conj(Map.get(kv, ":precondition", []), :precondition),
         {:ok, eff} <- effects(Map.get(kv, ":effect", [])) do
      {add, del} = eff
      {:ok, {String.upcase(name), params, pre, add, del}}
    end
  end

  defp pairs(body) do
    body
    |> Enum.chunk_every(2)
    |> Enum.filter(&match?([k, _] when is_binary(k), &1))
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  defp check_types(params) when is_list(params) do
    if Enum.any?(params, &is_list/1), do: {:error, {:unsupported, "either types"}}, else: :ok
  end

  defp params(list) do
    list |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "?")))
  end

  # Conjunction of positive atoms. `[]` / `["and"]` = empty.
  defp conj([], _), do: {:ok, []}
  defp conj(["and" | items], ctx), do: atoms(items, ctx)
  defp conj([op | _], _) when op in @unsupported_ops, do: unsupported(op)
  defp conj([pred | args], _) when is_binary(pred), do: {:ok, [[pred | args]]}

  defp atoms(items, ctx) do
    Enum.reduce_while(items, {:ok, []}, fn
      [op | _], _ when op in @unsupported_ops ->
        {:halt, unsupported(op, ctx)}

      ["and" | _] = nested, {:ok, acc} ->
        case conj(nested, ctx) do
          {:ok, xs} -> {:cont, {:ok, acc ++ xs}}
          err -> {:halt, err}
        end

      [_ | _] = atom, {:ok, acc} ->
        {:cont, {:ok, acc ++ [atom]}}

      _, _ ->
        {:halt, {:error, {:parse, "bad atom in #{ctx}"}}}
    end)
  end

  defp unsupported(op, ctx \\ nil),
    do: {:error, {:unsupported, if(ctx, do: "#{op} in #{ctx}", else: op)}}

  defp effects([]), do: {:ok, {[], []}}
  defp effects(["and" | items]), do: effect_items(items)
  defp effects(single), do: effect_items([single])

  defp effect_items(items) do
    Enum.reduce_while(items, {:ok, {[], []}}, fn
      ["not", [_ | _] = atom], {:ok, {a, d}} ->
        case guard_atom(atom) do
          :ok -> {:cont, {:ok, {a, d ++ [atom]}}}
          err -> {:halt, err}
        end

      [op | _], _ when op in @unsupported_ops ->
        {:halt, unsupported(op, :effect)}

      ["and" | rest], {:ok, {a, d}} ->
        case effect_items(rest) do
          {:ok, {a2, d2}} -> {:cont, {:ok, {a ++ a2, d ++ d2}}}
          err -> {:halt, err}
        end

      [_ | _] = atom, {:ok, {a, d}} ->
        case guard_atom(atom) do
          :ok -> {:cont, {:ok, {a ++ [atom], d}}}
          err -> {:halt, err}
        end

      _, _ ->
        {:halt, {:error, {:parse, "bad effect"}}}
    end)
  end

  defp guard_atom([_ | args]) when length(args) > 2,
    do: {:error, {:unsupported, "predicate arity above 2"}}

  defp guard_atom(_), do: :ok

  # ---- problem --------------------------------------------------------------

  defp init(["define", _name | sections]) do
    case Enum.find(sections, &match?([":init" | _], &1)) do
      [":init" | atoms] ->
        Enum.reduce_while(atoms, {:ok, []}, fn
          [op | _], _ when op in @unsupported_ops -> {:halt, unsupported(op, :init)}
          [_ | _] = a, {:ok, acc} -> {:cont, check_ground(a, acc)}
          _, _ -> {:halt, {:error, {:parse, "bad init atom"}}}
        end)
        |> case do
          {:ok, acc} -> {:ok, acc}
          err -> err
        end

      _ ->
        {:error, {:parse, "problem has no :init"}}
    end
  end

  defp init(_), do: {:error, {:parse, "not a PDDL problem"}}

  defp check_ground([_ | args] = a, acc) do
    cond do
      length(args) > 2 -> {:halt, {:error, {:unsupported, "predicate arity above 2"}}}
      true -> {:cont, {:ok, acc ++ [a]}}
    end
    |> case do
      {:halt, e} -> e
      {:cont, ok} -> ok
    end
  end

  defp goal(["define", _name | sections]) do
    case Enum.find(sections, &match?([":goal" | _], &1)) do
      [":goal", g] -> conj(g, :goal) |> guard_all()
      _ -> {:error, {:parse, "problem has no :goal"}}
    end
  end

  defp guard_all({:ok, atoms}) do
    Enum.find_value(atoms, {:ok, atoms}, fn a ->
      case guard_atom(a) do
        :ok -> nil
        err -> err
      end
    end)
  end

  defp guard_all(err), do: err

  # ---- mapping --------------------------------------------------------------

  defp triple([pred]), do: {"urn:r:_", "urn:p:#{pred}", "urn:p:true"}
  defp triple([pred, a]), do: {res(a), "urn:p:#{pred}", "urn:p:true"}
  defp triple([pred, a, b]), do: {res(a), "urn:p:#{pred}", res(b)}

  defp res(o), do: "urn:r:#{String.upcase(o)}"

  defp build(params, pre, add, del) do
    fn args ->
      if length(args) != length(params) do
        %{pre: [{"urn:r:_arity_mismatch", "urn:p:bad", "urn:p:true"}], add: [], del: []}
      else
        bind = Map.new(Enum.zip(params, args), fn {p, a} -> {p, String.downcase(a)} end)

        inst = fn atoms ->
          Enum.map(atoms, fn [p | as] -> triple([p | Enum.map(as, &Map.get(bind, &1, &1))]) end)
        end

        %{pre: inst.(pre), add: inst.(add), del: inst.(del)}
      end
    end
  end
end
