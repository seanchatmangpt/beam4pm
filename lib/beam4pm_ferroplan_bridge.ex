defmodule BeamPM.Ferroplan.Bridge do
  @moduledoc ~S"""
  Bridge between the strategic-autonomic-loop's doctrine/OCEL side and the
  Ferroplan engine sessions (lane W2, v26.9.25 strategic-autonomic-loop
  wave 2). Three concerns, all pure except the pinned telemetry edge:

  1. **Doctrine -> PDDL problem text** (`doctrine_to_problem/2`): renders a
     plain doctrine map (`%{objective_clauses: [binary], constraints:
     [binary], domain_text: binary}`) into the PDDL problem TEXT string that
     `BeamPM.Ferroplan.session_new/3` accepts as its `problem` argument.
     Deterministic: same input map, byte-identical output string.

     The pinned render format (one space indent inside the define, four
     spaces per clause, clauses in caller list order, empty groups render
     as bare `(and)`):

     ```
     (define (problem <normalized_name>)
       (:domain <domain_name>)
       (:objects)
       (:init)
       (:goal (and
         <objective clause 1>
         <objective clause 2>
       ))
       (:constraints (and
         <constraint 1>
       ))
     )
     ```

     `problem_name` is normalized to a PDDL name: trimmed, lowercased, every
     character outside `a-z0-9_-` replaced with `_`. The `(:domain ...)` name
     is extracted from `domain_text`'s `(define (domain NAME` header; a
     domain text without that header raises `ArgumentError` (fail loudly --
     a silent `(define (problem ...)` that grounds against the wrong domain
     is the exact defect class this bridge exists to prevent).

  2. **OCEL events -> sight batch** (`sight_from_events/1`): converts a list
     of OCEL event maps (`%{type: binary, attributes: map, relationships:
     term}`) into the `[{String.t(), boolean()}]` sight batch that
     `BeamPM.Ferroplan.session_observe/3` takes, under the pinned generic
     fact-name policy (lane map RESOLUTIONS #4 context; deviation-derived
     facts are the CALLER's job -- `BeamPM.OcelSessionFacts`, lane W5):

     - one fact per event: name = the event `type`, value `true`;
     - when the event's attributes carry an `object_id` key (string or atom),
       the fact name is `"type@object_id"` instead;
     - one additional fact per attribute whose value is ALREADY boolean
       (`true`/`false`): name = `"<attr>_<value>"` (e.g. `"active_true"`),
       value `true`. Non-boolean attribute values are NOT discretized here;
     - `relationships` are deliberately NOT projected by this function:
       relationship fact names need the deviation-side naming policy that
       lane W5 owns (failed edge recorded in the lane receipt).

     Attribute facts are emitted sorted by fact name so the output does not
     depend on map iteration order; events keep their input order.

  3. **Replan signal** (`replan_signal/3`): wraps a
     `BeamPM.Ferroplan.session_valid?/2` or `session_goal_met?/2` RESULT
     (`{:ok, %{"valid" => bool}}` / `{:ok, %{"goal_met" => bool}}` /
     `{:error, _}` / `{:ok, %{"error" => _}}` envelope refusal) into a
     replan decision, and -- only when the decision is to replan -- emits the
     pinned telemetry event `[:beam4pm, :ferroplan, :replan_triggered]` with
     metadata EXACTLY `%{trigger_hash: hex, reason: :deviation | :stale_plan
     | :world_invalid}` (lane map RESOLUTIONS #2; consumers attach to this
     shape, so no extra metadata keys). Decision table:

     | probe result                      | decision          |
     |-----------------------------------|-------------------|
     | `{:ok, %{"valid" => false}}`      | `{:replan, reason}` |
     | `{:ok, %{"goal_met" => false}}`   | `{:replan, reason}` |
     | `{:ok, %{"error" => _}}` envelope | `{:replan, reason}` |
     | `{:error, _}`                     | `{:replan, reason}` |
     | `{:ok, %{"valid" => true}}`       | `:continue`       |
     | `{:ok, %{"goal_met" => true}}`    | `:continue`       |

     An unknown result shape raises `ArgumentError` (unprobeable -- never
     silently continue). The telemetry call follows the generated facade's
     one-`:telemetry.execute/3`-after-the-fact house pattern
     (lib/beam4pm_ferroplan.ex `emit_engine_op_telemetry/4`), with
     `%{duration_native: ...}` as measurements. `trigger_hash` comes from
     `opts[:trigger_hash]` when binary (the caller holding lane W3's pinned
     formula `sha256(deviation_individual_name <> observed_at_iso8601)` hex
     passes it there); otherwise it is derived deterministically as
     sha256-hex of `term_to_binary({reason, probe_result})`.

  4. **Guarded engine-op call sites** (`guarded_engine_call/3`,
     `fond_policy_validate/3`, `session_install_plan/3`; lane map
     RESOLUTIONS #10): the two new ferroplan ops are declared in
     `ontology/ws2-autonomic-planning/051-fond_policy_validate_and_session_install_plan.ttl`
     but the GENERATED facade (`lib/beam4pm_ferroplan.ex`) does not export
     them until the coordinator re-renders at integration. Every call site
     therefore goes through `function_exported?/3` and falls back to the
     typed `{:error, {:engine_op_unavailable, op}}` -- never an
     UndefinedFunctionError, never a reference to a nonexistent export
     outside the guard.
  """

  @replan_event [:beam4pm, :ferroplan, :replan_triggered]
  @replan_reasons [:deviation, :stale_plan, :world_invalid]

  # ------------------------------------------------------------------
  # a. doctrine -> PDDL problem text
  # ------------------------------------------------------------------

  @doc ~S"""
  Renders a doctrine map into the PDDL problem text `session_new/3` accepts.

  `doctrine` is `%{domain_text: binary}` plus optional
  `objective_clauses: [binary]` and `constraints: [binary]` (PDDL
  sub-expressions, emitted verbatim in list order). `problem_name` is
  normalized (trimmed, lowercased, non `[a-z0-9_-]` -> `_`). Deterministic:
  same input, byte-identical output. Raises `ArgumentError` when
  `domain_text` has no `(define (domain NAME` header or the normalized
  problem name is empty.
  """
  @spec doctrine_to_problem(%{required(:domain_text) => String.t()}, String.t()) :: String.t()
  def doctrine_to_problem(doctrine, problem_name)
      when is_map(doctrine) and is_binary(problem_name) do
    domain_text = Map.get(doctrine, :domain_text)
    domain_name = domain_name!(domain_text)
    normalized = normalize_problem_name(problem_name)

    objective_clauses =
      binary_list!(Map.get(doctrine, :objective_clauses, []), "objective_clauses")

    constraints = binary_list!(Map.get(doctrine, :constraints, []), "constraints")

    """
    (define (problem #{normalized})
      (:domain #{domain_name})
      (:objects)
      (:init)
      (:goal (and#{render_clauses(objective_clauses)}))
      (:constraints (and#{render_clauses(constraints)}))
    )\
    """
  end

  defp domain_name!(domain_text) when is_binary(domain_text) do
    case Regex.run(~r/\(define\s+\(domain\s+([^\s)]+)/, domain_text) do
      [_, name] -> name
      nil -> raise ArgumentError, "domain_text has no `(define (domain NAME` header"
    end
  end

  defp domain_name!(other) do
    raise ArgumentError, "doctrine map requires a binary :domain_text, got: #{inspect(other)}"
  end

  defp normalize_problem_name(problem_name) do
    normalized =
      problem_name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]/, "_")

    if normalized == "" do
      raise ArgumentError,
            "problem_name #{inspect(problem_name)} normalizes to an empty PDDL name"
    end

    normalized
  end

  defp binary_list!(clauses, key) when is_list(clauses) do
    if Enum.all?(clauses, &is_binary/1) do
      clauses
    else
      raise ArgumentError, "#{key} must be a list of binaries, got: #{inspect(clauses)}"
    end
  end

  defp binary_list!(other, key) do
    raise ArgumentError, "#{key} must be a list of binaries, got: #{inspect(other)}"
  end

  defp render_clauses([]), do: ""

  defp render_clauses(clauses) do
    body = Enum.map_join(clauses, "\n", &"    #{&1}")
    "\n" <> body <> "\n  "
  end

  # ------------------------------------------------------------------
  # b. OCEL events -> sight batch
  # ------------------------------------------------------------------

  @doc ~S"""
  Converts OCEL event maps into the `[{name, boolean}]` sight batch
  `session_observe/3` takes, under the pinned generic fact-name policy
  (see the moduledoc). Deterministic: attribute facts sorted by name, events
  in input order; same input, byte-identical `inspect/1` output.
  """
  @spec sight_from_events([map()]) :: [{String.t(), boolean()}]
  def sight_from_events(events) when is_list(events) do
    Enum.flat_map(events, &event_facts/1)
  end

  defp event_facts(%{type: type} = event) when is_binary(type) do
    attrs = attributes(event)

    base_name =
      case object_id(attrs) do
        nil -> type
        object_id -> type <> "@" <> to_string(object_id)
      end

    attr_facts =
      attrs
      |> Enum.filter(fn {_key, value} -> is_boolean(value) end)
      |> Enum.map(fn {key, value} -> {fact_name(key, value), true} end)
      |> Enum.sort()

    [{base_name, true} | attr_facts]
  end

  defp event_facts(other) do
    raise ArgumentError,
          "each OCEL event must be a map with a binary :type, got: #{inspect(other)}"
  end

  defp attributes(event) do
    case Map.get(event, :attributes) do
      nil ->
        %{}

      attrs when is_map(attrs) ->
        attrs

      other ->
        raise ArgumentError, "event :attributes must be a map or nil, got: #{inspect(other)}"
    end
  end

  defp object_id(attrs) do
    Map.get(attrs, "object_id") || Map.get(attrs, :object_id)
  end

  defp fact_name(key, value) when is_atom(key), do: "#{Atom.to_string(key)}_#{value}"
  defp fact_name(key, value) when is_binary(key), do: "#{key}_#{value}"

  # ------------------------------------------------------------------
  # c. replan signal (pinned telemetry seam)
  # ------------------------------------------------------------------

  @doc ~S"""
  Wraps a `session_valid?/2` or `session_goal_met?/2` RESULT into a replan
  decision (see the moduledoc decision table) and, when the decision is to
  replan, emits `[:beam4pm, :ferroplan, :replan_triggered]` with metadata
  exactly `%{trigger_hash: hex, reason: reason}`.

  `reason` is one of `:deviation | :stale_plan | :world_invalid` -- the
  caller's own account of which check motivated the probe. `opts`
  understands `:trigger_hash` (binary; the caller holding the pinned W3
  formula passes it here; otherwise derived deterministically). Returns
  `{:replan, reason}` or `:continue`; emits telemetry ONLY on `{:replan,
  reason}`.
  """
  @spec replan_signal(term(), :deviation | :stale_plan | :world_invalid, keyword()) ::
          {:replan, :deviation | :stale_plan | :world_invalid} | :continue
  def replan_signal(probe_result, reason, opts \\ [])
      when reason in @replan_reasons and is_list(opts) do
    start_native = System.monotonic_time()

    case replan_decision(probe_result) do
      :continue ->
        :continue

      :replan ->
        trigger_hash = trigger_hash(reason, probe_result, opts)
        duration_native = System.monotonic_time() - start_native

        :telemetry.execute(
          @replan_event,
          %{duration_native: duration_native},
          %{trigger_hash: trigger_hash, reason: reason}
        )

        {:replan, reason}
    end
  end

  defp replan_decision({:ok, %{"valid" => valid}}) when is_boolean(valid),
    do: if(valid, do: :continue, else: :replan)

  defp replan_decision({:ok, %{"goal_met" => met}}) when is_boolean(met),
    do: if(met, do: :continue, else: :replan)

  defp replan_decision({:ok, %{"error" => _}}), do: :replan
  defp replan_decision({:error, _}), do: :replan

  defp replan_decision(other),
    do: raise(ArgumentError, "unprobeable engine result shape: #{inspect(other)}")

  defp trigger_hash(reason, probe_result, opts) do
    case Keyword.get(opts, :trigger_hash) do
      hash when is_binary(hash) ->
        hash

      _ ->
        :crypto.hash(:sha256, :erlang.term_to_binary({reason, probe_result}))
        |> Base.encode16(case: :lower, padding: false)
    end
  end

  # ------------------------------------------------------------------
  # d. guarded engine-op call sites (lane map RESOLUTIONS #10)
  # ------------------------------------------------------------------

  @doc ~S"""
  Calls `engine_mod.fun/arity` with `args` only when the generated facade
  actually exports it (`function_exported?/3`); otherwise returns the typed
  fallback `{:error, {:engine_op_unavailable, fun}}`. Public so lanes W3/W5
  and the test suite can drive the same guard with any target module.
  """
  @spec guarded_engine_call(module(), atom(), [term()]) ::
          term() | {:error, {:engine_op_unavailable, atom()}}
  def guarded_engine_call(engine_mod, fun, args)
      when is_atom(engine_mod) and is_atom(fun) and is_list(args) do
    if function_exported?(engine_mod, fun, length(args)) do
      apply(engine_mod, fun, args)
    else
      {:error, {:engine_op_unavailable, fun}}
    end
  end

  @doc ~S"""
  Guarded call of the declared `fond_policy_validate` engine op
  (ontology/ws2-autonomic-planning/051, opOrder 34): re-validate an
  already-computed FOND plan against `domain`/`problem` PDDL text without
  spending search. Returns the engine result, or
  `{:error, {:engine_op_unavailable, :fond_policy_validate}}` until the
  facade re-render lands.
  """
  @spec fond_policy_validate(String.t(), String.t(), map(), keyword()) ::
          term() | {:error, {:engine_op_unavailable, :fond_policy_validate}}
  def fond_policy_validate(domain, problem, plan, opts \\ [])
      when is_binary(domain) and is_binary(problem) and is_map(plan) and is_list(opts) do
    guarded_engine_call(BeamPM.Ferroplan, :fond_policy_validate, [domain, problem, plan, opts])
  end

  @doc ~S"""
  Guarded call of the declared `session_install_plan` engine op
  (ontology/ws2-autonomic-planning/051, opOrder 35): install a decoded
  UniversalPlan map as the session's stashed plan without re-search. Returns
  the engine result, or `{:error, {:engine_op_unavailable,
  :session_install_plan}}` until the facade re-render lands.
  """
  @spec session_install_plan(non_neg_integer(), map(), keyword()) ::
          term() | {:error, {:engine_op_unavailable, :session_install_plan}}
  def session_install_plan(handle, plan, opts \\ [])
      when is_integer(handle) and is_map(plan) and is_list(opts) do
    guarded_engine_call(BeamPM.Ferroplan, :session_install_plan, [handle, plan, opts])
  end
end
