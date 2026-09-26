defmodule BeamPM.Dfcm do
  @compile {:no_warn_undefined, AshAutofde.CascadeAllocator}
  @compile {:no_warn_undefined, BeamPM.Ferroplan}

  alias BeamPM.Ferroplan

  @moduledoc """
  Pure Design for Combinatorial Maximalism planning crown.

  DfCM preserves admitted alternatives, applies explicit fences, records every
  exclusion with a deterministic receipt and falsifier, and returns either a
  decision-relevant observation request or a SELECT candidate. It composes the
  WS2 FOND/HDDL contracts and deliberately has no DO surface.
  """

  @type observation_outcome :: :positive | :negative | :inconclusive
  @type option :: map()
  @type problem :: %{
          required(:options) => [option()],
          optional(:observations) => map(),
          optional(:fences) => [map()]
        }

  @phase_order [
    :preserve,
    :fence,
    :calculus,
    :exclusions,
    :falsifier,
    :extension,
    :construct_contingent_policy,
    :select
  ]

  @reversibility_rank %{
    unknown: 0,
    irreversible: 1,
    migratable: 2,
    compensatable: 3,
    reversible: 4
  }

  @fond_outcomes [:positive, :negative, :inconclusive]

  @spec authority_ceiling() :: :select
  def authority_ceiling, do: :select

  @spec phase_order() :: [atom()]
  def phase_order, do: @phase_order

  @spec fond_outcomes() :: [observation_outcome()]
  def fond_outcomes, do: @fond_outcomes

  @doc "Run one deterministic DfCM planning cycle; returns planning data only."
  @spec cycle(problem()) :: map()
  def cycle(%{options: options} = problem) when is_list(options) do
    observations = Map.get(problem, :observations, %{})
    fences = Map.get(problem, :fences, [])

    admitted =
      options
      |> Enum.map(&normalize_option/1)
      |> Enum.filter(&Map.get(&1, :admitted, true))

    preserved_ids = Enum.map(admitted, & &1.id)

    fence_exclusions = fence_exclusions(admitted, fences)
    fence_excluded_ids = ids(fence_exclusions)

    observation_exclusions =
      admitted
      |> Enum.reject(&(&1.id in fence_excluded_ids))
      |> observation_exclusions(observations)

    initial_exclusions = fence_exclusions ++ observation_exclusions
    initial_excluded_ids = ids(initial_exclusions)
    active = Enum.reject(admitted, &(&1.id in initial_excluded_ids))
    pending = decision_relevant_observations(active, observations)

    dominance_exclusions =
      if pending == [], do: dominance_exclusions(active), else: []

    exclusions = dedupe_exclusions(initial_exclusions ++ dominance_exclusions)
    excluded_ids = ids(exclusions)
    nondominated = Enum.reject(active, &(&1.id in excluded_ids))

    decision =
      case pending do
        [observation | _] ->
          %{
            kind: :observe,
            observation: observation,
            outcomes: @fond_outcomes,
            authority_ceiling: :select
          }

        [] ->
          select(nondominated)
      end

    %{
      authority_ceiling: :select,
      phase_order: @phase_order,
      preserved_options: preserved_ids,
      excluded_options: exclusions,
      nondominated_options: Enum.map(nondominated, & &1.id),
      pending_observations: pending,
      decision: decision,
      hddl_task_network: %{
        task: :dfcm_cycle,
        ordered_subtasks: @phase_order,
        terminal_authority: :select
      },
      fond_policy: fond_policy(decision)
    }
  end

  @doc "Apply one FOND observation outcome to the problem state."
  @spec observe(problem(), atom(), observation_outcome()) :: problem()
  def observe(problem, observation, outcome)
      when is_atom(observation) and outcome in @fond_outcomes do
    observations = Map.get(problem, :observations, %{})
    Map.put(problem, :observations, Map.put(observations, observation, outcome))
  end

  @doc "Materialize the next FOND policy branch set."
  @spec policy(problem()) :: map()
  def policy(problem) do
    case cycle(problem).decision do
      %{kind: :observe, observation: observation} ->
        branches =
          Map.new(@fond_outcomes, fn outcome ->
            next = problem |> observe(observation, outcome) |> cycle()
            {outcome, next.decision}
          end)

        %{
          kind: :strong_cyclic,
          observation: observation,
          fairness: :eventual_conclusive_observation,
          branches: branches,
          authority_ceiling: :select
        }

      decision ->
        %{kind: :terminal_select_state, decision: decision, authority_ceiling: :select}
    end
  end

  @doc """
  Multifractal option allocation over surviving nondominated candidates.
  Preserves option entropy and returns fractional capacity shares without DO authority.
  """
  @spec allocate_options(problem(), map()) :: map()
  def allocate_options(problem, budget \\ %{}) do
    cycle_result = cycle(problem)
    options = Map.get(problem, :options, [])
    nondominated_ids = cycle_result.nondominated_options

    active = Enum.filter(options, fn opt -> opt.id in nondominated_ids end)

    if active == [] do
      %{
        status: :refused,
        reason: :no_lawful_option,
        allocations: [],
        authority_ceiling: :select
      }
    else
      candidates =
        Enum.map(active, fn opt ->
          norm = normalize_option(opt)
          %{
            "branch_id" => norm.id,
            "option_entropy" => max(1.0, norm.goal_progress * 1.0),
            "historical_yield" => max(0.5, norm.reuse * 0.2),
            "estimated_cost" => max(1.0, norm.verification_cost * 1.0)
          }
        end)

      allocator_fn =
        if Code.ensure_loaded?(AshAutofde.CascadeAllocator) and
             function_exported?(AshAutofde.CascadeAllocator, :allocate, 3) do
          fn b, c -> AshAutofde.CascadeAllocator.allocate("dfcm_plan", b, c) end
        else
          fn _b, _c -> {:error, :allocator_unavailable} end
        end

      case allocator_fn.(budget, candidates) do
        {:ok, plan} ->
          Map.put(plan, :authority_ceiling, :select)

        {:error, _fallback} ->
          # Uniform option-preserving fallback
          share = 1.0 / length(active)
          %{
            "plan_id" => "dfcm_plan",
            "total_option_value_preserved" => 1.0,
            "entropy" => 1.0,
            "allocations" =>
              Enum.map(active, fn opt ->
                %{
                  "branch_id" => opt.id,
                  "allocated_fraction" => share,
                  "standing" => "ADMITTED"
                }
              end),
            authority_ceiling: :select
          }
      end
    end
  end

  @doc "Pareto dominance across progress, reversibility, information, reuse and bounded cost."
  @spec dominates?(option(), option()) :: boolean()
  def dominates?(left, right) do
    left = normalize_option(left)
    right = normalize_option(right)
    left_dims = dimensions(left)
    right_dims = dimensions(right)
    pairs = Enum.zip(left_dims, right_dims)

    Enum.all?(pairs, fn {l, r} -> l >= r end) and
      Enum.any?(pairs, fn {l, r} -> l > r end)
  end

  @doc "A/B/C/X benchmark: A collapses C; B preserves C; C is valuable iff X is positive."
  @spec benchmark() :: problem()
  def benchmark do
    %{
      observations: %{x: :inconclusive},
      fences: [],
      options: [
        %{
          id: "A",
          goal_progress: 8,
          information_gain: 0,
          reuse: 5,
          reversibility: :irreversible,
          irreversible_loss: 1,
          consequence: 2,
          verification_cost: 0,
          destroys: ["C"]
        },
        %{
          id: "B",
          goal_progress: 8,
          information_gain: 0,
          reuse: 5,
          reversibility: :reversible,
          irreversible_loss: 0,
          consequence: 2,
          verification_cost: 1,
          preserves: ["C"]
        },
        %{
          id: "C",
          goal_progress: 10,
          information_gain: 0,
          reuse: 5,
          reversibility: :reversible,
          irreversible_loss: 0,
          consequence: 2,
          verification_cost: 1,
          requires_observation: :x,
          enabled_when: {:x, :positive}
        }
      ]
    }
  end

  defp normalize_option(option) do
    option
    |> Map.put_new(:admitted, true)
    |> Map.put_new(:goal_progress, 0)
    |> Map.put_new(:information_gain, 0)
    |> Map.put_new(:reuse, 0)
    |> Map.put_new(:reversibility, :unknown)
    |> Map.put_new(:irreversible_loss, 0)
    |> Map.put_new(:consequence, 0)
    |> Map.put_new(:verification_cost, 0)
  end

  defp fence_exclusions(options, fences) do
    for fence <- fences,
        option <- options,
        option.id in Map.get(fence, :excludes, []) do
      receipt(
        option.id,
        {:fence, Map.fetch!(fence, :id)},
        Map.get(fence, :evidence),
        Map.get(fence, :falsifier, {:remove_fence, Map.fetch!(fence, :id)})
      )
    end
  end

  defp observation_exclusions(options, observations) do
    Enum.flat_map(options, fn option ->
      case Map.get(option, :enabled_when) do
        {observation, expected} ->
          case Map.get(observations, observation) do
            outcome when outcome in [:positive, :negative] and outcome != expected ->
              [
                receipt(
                  option.id,
                  {:observation_disables, observation, outcome},
                  {:observed, observation, outcome},
                  {:observation_is, observation, expected}
                )
              ]

            _ ->
              []
          end

        nil ->
          []
      end
    end)
  end

  defp decision_relevant_observations(options, observations) do
    options
    |> Enum.flat_map(fn option ->
      case Map.get(option, :requires_observation) do
        nil -> []
        observation -> [observation]
      end
    end)
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(observations, &1) not in [:positive, :negative]))
    |> Enum.sort()
  end

  defp dominance_exclusions(options) do
    Enum.flat_map(options, fn candidate ->
      case Enum.find(options, &(&1.id != candidate.id and dominates?(&1, candidate))) do
        nil ->
          []

        dominant ->
          [
            receipt(
              candidate.id,
              {:dominated_by, dominant.id},
              {:pareto_witness, dominant.id, candidate.id},
              {:invalidate_dominance_witness, dominant.id, candidate.id}
            )
          ]
      end
    end)
  end

  defp select([]),
    do: %{kind: :refuse, reason: :no_lawful_option, authority_ceiling: :select}

  defp select(options) do
    selected = Enum.max_by(options, &selection_score/1)

    %{
      kind: :select,
      selected_option: selected.id,
      selection_score: selection_score(selected),
      authority_ceiling: :select
    }
  end

  defp dimensions(option) do
    [
      option.goal_progress,
      Map.fetch!(@reversibility_rank, option.reversibility),
      option.information_gain,
      option.reuse,
      -option.irreversible_loss,
      -option.consequence,
      -option.verification_cost
    ]
  end

  defp selection_score(option), do: List.to_tuple(dimensions(option))

  defp receipt(option_id, reason, evidence, falsifier) do
    receipt_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary({option_id, reason, evidence, falsifier}))
      |> Base.encode16(case: :lower)

    %{
      option_id: option_id,
      reason: reason,
      evidence: evidence,
      falsifier: falsifier,
      receipt_hash: receipt_hash
    }
  end

  defp ids(exclusions), do: Enum.map(exclusions, & &1.option_id)

  defp dedupe_exclusions(exclusions) do
    exclusions
    |> Enum.uniq_by(&{&1.option_id, &1.reason})
    |> Enum.sort_by(&{&1.option_id, inspect(&1.reason)})
  end

  defp fond_policy(%{kind: :observe, observation: observation}) do
    %{
      kind: :strong_cyclic,
      observation: observation,
      outcomes: @fond_outcomes,
      inconclusive_successor: :observe,
      terminal_authority: :select
    }
  end

  defp fond_policy(decision),
    do: %{kind: :terminal, decision: decision.kind, terminal_authority: :select}

  # --- Live Ferroplan DfCM runtime -----------------------------------------

  @doc """
  Observe a bounded live-world delta and repair the current Ferroplan
  candidate without granting DO authority.

  The runtime preserves the cheapest valid option first. When the pinned
  Ferroplan exposes the native DfCM `session_repair` operation it is used
  directly; older admitted pins fall back to the equivalent host-side
  ladder:

      goal-met -> valid suffix reuse -> bounded full replan

  Native `session_repair` inserts follow-biased tail repair between suffix
  reuse and full replan, so upgrading the producer strengthens option
  preservation without changing this caller contract.
  """
  @spec observe_and_repair_session(
          non_neg_integer(),
          [{String.t(), boolean()}],
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def observe_and_repair_session(handle, observations, opts \\ [])
      when is_integer(handle) and is_list(observations) do
    event_id = Keyword.get(opts, :event_id, "event:" <> deterministic_hash(observations))

    with {:ok, surprises} <- Ferroplan.session_observe(handle, observations),
         {:ok, repair} <- repair_session(handle, opts) do
      trigger =
        if repair.trigger == :invalid_plan do
          %{
            plan_id: repair.previous_plan_id || "none",
            event_id: event_id,
            trigger_hash:
              deterministic_hash({
                repair.previous_plan_id,
                event_id,
                observations,
                surprises
              })
          }
        end

      {:ok,
       repair
       |> Map.put(:surprises, surprises)
       |> Map.put(:event_id, event_id)
       |> Map.put(:dynamic_replan_trigger, trigger)}
    end
  end

  @doc """
  Repair the current stashed Ferroplan candidate while preserving option
  value. Returns SELECT/CONSTRUCT evidence only; never advances or executes
  the plan.
  """
  @spec repair_session(non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def repair_session(handle, opts \\ []) when is_integer(handle) do
    evals = Keyword.get(opts, :evals, 10_000)
    mem_mb = Keyword.get(opts, :mem_mb, 64)

    native =
      if Code.ensure_loaded?(Ferroplan) and function_exported?(Ferroplan, :session_repair, 4) do
        apply(Ferroplan, :session_repair, [handle, evals, mem_mb, []])
      else
        :unavailable
      end

    case native do
      {:ok, result} when is_map(result) ->
        {:ok, normalize_repair(result, :native_follow_before_rethink)}

      :unavailable ->
        fallback_repair_session(handle, evals, mem_mb)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Evaluate reversible counterfactuals over cheap Ferroplan forks.

  Each candidate may provide `:goal`, `:observations` and
  `:restrict_contains`. The parent session is never mutated. If the pinned
  producer exposes native `session_probe`, it is preferred; otherwise the
  same semantics are composed from `session_fork` and existing session ops.
  """
  @spec probe_session(non_neg_integer(), [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def probe_session(handle, candidates, opts \\ [])
      when is_integer(handle) and is_list(candidates) and candidates != [] do
    evals = Keyword.get(opts, :evals, 10_000)
    mem_mb = Keyword.get(opts, :mem_mb, 64)

    native =
      if Code.ensure_loaded?(Ferroplan) and function_exported?(Ferroplan, :session_probe, 5) do
        wire_candidates =
          Enum.map(candidates, fn candidate ->
            %{
              "id" => to_string(Map.fetch!(candidate, :id)),
              "goal" => Map.get(candidate, :goal),
              "sight" =>
                candidate
                |> Map.get(:observations, [])
                |> Enum.map(&Tuple.to_list/1),
              "restrict_contains" => Map.get(candidate, :restrict_contains)
            }
          end)

        apply(Ferroplan, :session_probe, [handle, wire_candidates, evals, mem_mb, []])
      else
        :unavailable
      end

    case native do
      {:ok, result} when is_map(result) ->
        {:ok,
         %{
           candidate_count: Map.get(result, "candidate_count", length(candidates)),
           results: Map.get(result, "results", []),
           backend: :native_forks,
           authority_ceiling: :select
         }}

      :unavailable ->
        results =
          Enum.map(candidates, &fallback_probe_candidate(handle, &1, evals, mem_mb))

        {:ok,
         %{
           candidate_count: length(results),
           results: results,
           backend: :host_forks,
           authority_ceiling: :select
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Recompile an explicitly supplied hierarchy only after the caller has
  decided the local-session repair boundary was exhausted.

  This is a bounded CONSTRUCT operation over exact HDDL source. It returns a
  SELECT candidate with deterministic evidence; an unsolved hierarchy names
  `:strategic_recompile` as the next boundary but never invokes one.
  """
  @spec hddl_recompile(String.t(), String.t(), map() | nil) ::
          {:ok, map()} | {:error, term()}
  def hddl_recompile(domain, problem, limits \\ nil)
      when is_binary(domain) and is_binary(problem) and (is_map(limits) or is_nil(limits)) do
    case Ferroplan.hddl_solve(domain, problem, limits) do
      {:ok, %{"error" => error}} ->
        {:error,
         {:hddl_refused,
          %{
            error: error,
            next_escalation: :strategic_recompile,
            authority_ceiling: :select
          }}}

      {:ok, %{"solved" => true} = plan} ->
        {:ok,
         %{
           kind: :hddl_recompile,
           plan: plan,
           plan_evidence_hash: deterministic_hash({domain, problem, limits, plan}),
           next_escalation: nil,
           authority_ceiling: :select
         }}

      {:ok, plan} ->
        {:error,
         {:hddl_unsolved,
          %{
            plan: plan,
            plan_evidence_hash: deterministic_hash({domain, problem, limits, plan}),
            next_escalation: :strategic_recompile,
            authority_ceiling: :select
          }}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Admit one exact FOND policy branch using Ferroplan's independent policy
  validator before exposing the action as a SELECT candidate.

  No state inference is performed: callers provide the exact universal-plan
  state id. A missing validator, invalid policy, or uncovered state is typed
  rather than repaired with LLM reasoning.
  """
  @spec admit_fond_branch(String.t(), map(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def admit_fond_branch(problem_json, plan, state_id)
      when is_binary(problem_json) and is_map(plan) and is_binary(state_id) do
    if Code.ensure_loaded?(Ferroplan) and function_exported?(Ferroplan, :fond_validate, 3) do
      case apply(Ferroplan, :fond_validate, [problem_json, plan, []]) do
        {:ok, %{"valid" => true, "guarantee" => guarantee} = validation} ->
          case Enum.find(Map.get(plan, "policy", []), &(Map.get(&1, "state") == state_id)) do
            %{"action" => action, "outcomes" => outcomes} ->
              evidence_hash =
                deterministic_hash({
                  state_id,
                  action,
                  outcomes,
                  guarantee,
                  Map.get(validation, "reachable_states", [])
                })

              {:ok,
               %{
                 kind: :fond_policy_branch,
                 state_id: state_id,
                 action: action,
                 outcomes: outcomes,
                 guarantee: guarantee,
                 policy_evidence_hash: evidence_hash,
                 authority_ceiling: :select
               }}

            nil ->
              {:error, {:fond_state_uncovered, state_id}}
          end

        {:ok, %{"valid" => false} = validation} ->
          {:error, {:fond_policy_invalid, Map.get(validation, "issues", [])}}

        {:ok, %{"error" => error}} ->
          {:error, {:fond_validation_refused, error}}

        {:error, _} = error ->
          error

        other ->
          {:error, {:fond_validation_unexpected, other}}
      end
    else
      {:error, :fond_validator_unavailable}
    end
  end

  @doc "Construct a stale-plan refusal only from explicit admitted and observed identities."
  @spec stale_plan_refusal(String.t(), String.t(), String.t()) :: nil | map()
  def stale_plan_refusal(plan_id, admitted_preimage_hash, observed_preimage_hash)
      when is_binary(plan_id) and is_binary(admitted_preimage_hash) and
             is_binary(observed_preimage_hash) do
    if admitted_preimage_hash == observed_preimage_hash do
      nil
    else
      %{
        plan_id: plan_id,
        admitted_preimage_hash: admitted_preimage_hash,
        observed_preimage_hash: observed_preimage_hash,
        authority_ceiling: :select
      }
    end
  end

  defp fallback_repair_session(handle, evals, mem_mb) do
    with {:ok, %{"goal_met" => goal_met}} <- Ferroplan.session_goal_met?(handle) do
      if goal_met do
        {:ok,
         finalize_repair(%{
           decision: :goal_met,
           trigger: :goal_met,
           plan_valid: nil,
           previous_suffix: [],
           suffix: [],
           plan: nil,
           backend: :host_fallback
         })}
      else
        fallback_repair_open_goal(handle, evals, mem_mb)
      end
    end
  end

  defp fallback_repair_open_goal(handle, evals, mem_mb) do
    with {:ok, %{"has_plan" => has_plan}} <- Ferroplan.session_has_plan?(handle) do
      if has_plan do
        with {:ok, previous_suffix} <- Ferroplan.session_suffix(handle),
             {:ok, %{"valid" => valid}} <- Ferroplan.session_valid?(handle) do
          if valid do
            {:ok,
             finalize_repair(%{
               decision: :reuse_suffix,
               trigger: :none,
               plan_valid: true,
               previous_suffix: previous_suffix,
               suffix: previous_suffix,
               plan: nil,
               backend: :host_fallback
             })}
          else
            fallback_full_replan(handle, previous_suffix, :invalid_plan, false, evals, mem_mb)
          end
        end
      else
        fallback_full_replan(handle, [], :no_plan, nil, evals, mem_mb)
      end
    end
  end

  defp fallback_full_replan(handle, previous_suffix, trigger, plan_valid, evals, mem_mb) do
    case Ferroplan.session_think(handle, evals, mem_mb) do
      {:ok, %{"error" => error}} ->
        {:ok,
         finalize_repair(%{
           decision: :replan_refused,
           trigger: trigger,
           plan_valid: plan_valid,
           previous_suffix: previous_suffix,
           suffix: [],
           plan: nil,
           replan_error: error,
           backend: :host_fallback
         })}

      {:ok, %{"solved" => true} = plan} ->
        with {:ok, suffix} <- Ferroplan.session_suffix(handle) do
          {:ok,
           finalize_repair(%{
             decision: :replanned_full,
             trigger: trigger,
             plan_valid: plan_valid,
             previous_suffix: previous_suffix,
             suffix: suffix,
             plan: plan,
             backend: :host_fallback
           })}
        end

      {:ok, plan} ->
        {:ok,
         finalize_repair(%{
           decision: :replan_unsolved,
           trigger: trigger,
           plan_valid: plan_valid,
           previous_suffix: previous_suffix,
           suffix: [],
           plan: plan,
           backend: :host_fallback
         })}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_repair(result, backend) do
    decision =
      result
      |> Map.get("decision", "replan_unsolved")
      |> String.to_existing_atom()

    trigger =
      result
      |> Map.get("trigger", "none")
      |> String.to_existing_atom()

    finalize_repair(%{
      decision: decision,
      trigger: trigger,
      plan_valid: Map.get(result, "plan_valid"),
      previous_suffix: Map.get(result, "previous_suffix", []),
      suffix: Map.get(result, "suffix", []),
      plan: Map.get(result, "solution"),
      backend: backend
    })
  rescue
    ArgumentError ->
      finalize_repair(%{
        decision: :replan_unsolved,
        trigger: :none,
        plan_valid: nil,
        previous_suffix: Map.get(result, "previous_suffix", []),
        suffix: Map.get(result, "suffix", []),
        plan: Map.get(result, "solution"),
        backend: backend
      })
  end

  defp finalize_repair(repair) do
    previous_plan_id = plan_id(Map.get(repair, :previous_suffix, []))
    current_plan_id = plan_id(Map.get(repair, :suffix, []))

    lineage =
      if previous_plan_id && current_plan_id && previous_plan_id != current_plan_id do
        %{
          plan_id: current_plan_id,
          parent_plan_id: previous_plan_id,
          lineage_hash: deterministic_hash({previous_plan_id, current_plan_id, repair.decision})
        }
      end

    memory =
      if current_plan_id do
        evidence_hash =
          deterministic_hash({
            repair.decision,
            repair.trigger,
            Map.get(repair, :plan_valid),
            Map.get(repair, :backend)
          })

        %{
          plan_id: current_plan_id,
          evidence_hash: evidence_hash,
          memory_hash: deterministic_hash({current_plan_id, evidence_hash})
        }
      end

    escalation =
      if repair.decision in [:replan_unsolved, :replan_refused] do
        [:hddl_recompile, :strategic_recompile]
      else
        []
      end

    repair
    |> Map.put_new(:replan_error, nil)
    |> Map.put(:previous_plan_id, previous_plan_id)
    |> Map.put(:plan_id, current_plan_id)
    |> Map.put(:plan_lineage, lineage)
    |> Map.put(:plan_memory, memory)
    |> Map.put(:escalation, escalation)
    |> Map.put(:authority_ceiling, :select)
  end

  defp fallback_probe_candidate(parent_handle, candidate, evals, mem_mb) do
    id = to_string(Map.fetch!(candidate, :id))

    case Ferroplan.session_fork(parent_handle) do
      {:ok, %{"handle" => fork}} ->
        try do
          with :ok <- maybe_set_goal(fork, Map.get(candidate, :goal)),
               :ok <- maybe_restrict(fork, Map.get(candidate, :restrict_contains)),
               {:ok, surprises} <-
                 maybe_observe(fork, Map.get(candidate, :observations, [])),
               {:ok, solution} <- Ferroplan.session_think(fork, evals, mem_mb),
               {:ok, %{"bytes" => world_bytes}} <- Ferroplan.session_world_bytes(fork),
               {:ok, %{"bytes" => mind_bytes}} <- Ferroplan.session_mind_bytes(fork) do
            %{
              id: id,
              outcome: if(Map.get(solution, "solved"), do: :solved, else: :unsolved),
              surprises: surprises,
              solution: solution,
              plan_id:
                plan_id(
                  case Map.get(solution, "plan") do
                    %{"steps" => steps} when is_list(steps) -> steps
                    _ -> []
                  end
                ),
              world_bytes: world_bytes,
              mind_bytes: mind_bytes,
              authority_ceiling: :select
            }
          else
            {:error, reason} ->
              %{
                id: id,
                outcome: :refused,
                reason: reason,
                authority_ceiling: :select
              }
          end
        after
          _ = Ferroplan.session_free(fork)
        end

      {:error, reason} ->
        %{id: id, outcome: :refused, reason: reason, authority_ceiling: :select}
    end
  end

  defp maybe_set_goal(_handle, nil), do: :ok

  defp maybe_set_goal(handle, goal) when is_binary(goal) do
    case Ferroplan.session_set_goal(handle, goal) do
      {:ok, %{"ok" => true}} -> :ok
      {:error, _} = error -> error
      other -> {:error, {:set_goal, other}}
    end
  end

  defp maybe_restrict(_handle, nil), do: :ok

  defp maybe_restrict(handle, filter) when is_binary(filter) do
    case Ferroplan.session_restrict_contains(handle, filter) do
      {:ok, %{"ok" => true}} -> :ok
      {:error, _} = error -> error
      other -> {:error, {:restrict, other}}
    end
  end

  defp maybe_observe(_handle, []), do: {:ok, []}

  defp maybe_observe(handle, observations) when is_list(observations) do
    Ferroplan.session_observe(handle, observations)
  end

  defp plan_id([]), do: nil

  defp plan_id(steps) when is_list(steps) do
    "plan:" <> deterministic_hash(steps)
  end

  defp deterministic_hash(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  # --- Standalone AutoFDE Typer CLI Bridge (priv/bin/autofde) ---

  @doc "Locate the standalone autofde CLI executable."
  @spec autofde_cli_path() :: String.t()
  def autofde_cli_path do
    Application.get_env(:beam4pm, :autofde_cli_path) ||
      System.get_env("AUTOFDE_CLI_PATH") ||
      Path.expand("priv/bin/autofde")
  end

  @doc "Check if the standalone autofde CLI binary is available."
  @spec autofde_cli_available?() :: boolean()
  def autofde_cli_available? do
    path = autofde_cli_path()
    File.exists?(path)
  end

  @doc "Execute a command against the standalone AutoFDE Typer CLI."
  @spec run_autofde_cli([String.t()]) :: {:ok, map()} | {:error, term()}
  def run_autofde_cli(args) do
    bin = autofde_cli_path()

    if File.exists?(bin) do
      case System.cmd(bin, args, stderr_to_stdout: false) do
        {output, 0} ->
          case JSON.decode(output) do
            {:ok, parsed} -> {:ok, parsed}
            {:error, err} -> {:error, {:invalid_json, err, output}}
          end

        {err_output, code} ->
          {:error, {:cli_failed, code, err_output}}
      end
    else
      {:error, {:binary_missing, bin}}
    end
  end

  @doc "Query AutoFDE-Lab's catalog of registered domains and solvers via standalone Typer CLI."
  @spec catalog() :: {:ok, %{domains: [String.t()], solvers: [String.t()]}} | {:error, term()}
  def catalog do
    case run_autofde_cli(["fabric", "catalog"]) do
      {:ok, %{"domains" => domains, "solvers" => solvers}} ->
        {:ok, %{domains: domains, solvers: solvers}}

      other ->
        other
    end
  end

  @doc "Check OCEL 2.0 object-centric conformance using AutoFDE-Lab's standalone Typer CLI."
  @spec ocel_conformance(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def ocel_conformance(log_path, intended_traces) do
    traces_json = JSON.encode!(intended_traces)

    case run_autofde_cli(["ocel", "conformance", log_path, traces_json]) do
      {:ok, %{"ok" => true} = resp} -> {:ok, resp}
      {:ok, %{"error" => err}} -> {:error, {:conformance_error, err}}
      other -> other
    end
  end

  @doc "Compute canonical GraphLaw BLAKE3 graph hash via standalone AutoFDE/GraphLaw WASM engine."
  @spec graphlaw_hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  def graphlaw_hash(ttl_content) do
    case run_autofde_cli(["sa2a", "graphlaw", "hash", "--ttl", ttl_content]) do
      {:ok, %{"ok" => true, "graph_hash" => hash}} -> {:ok, hash}
      {:ok, %{"error" => err}} -> {:error, {:graphlaw_error, err}}
      other -> other
    end
  end

  @doc "Execute native Praxis GraphLaw validation (SHACL, ShEx, Datalog, N3 denials) via standalone engine."
  @spec graphlaw_validate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def graphlaw_validate(ttl_content, opts \\ []) do
    args = ["sa2a", "graphlaw", "validate", "--ttl", ttl_content]

    args =
      case Keyword.get(opts, :shacl) do
        nil -> args
        shacl -> args ++ ["--shacl", shacl]
      end

    case run_autofde_cli(args) do
      {:ok, %{"action" => "validate"} = resp} -> {:ok, resp}
      {:ok, %{"error" => err}} -> {:error, {:graphlaw_error, err}}
      other -> other
    end
  end

  @doc "Execute Knowledge Hooks transition against base graph via standalone GraphLaw WASM engine."
  @spec graphlaw_hooks(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def graphlaw_hooks(base_ttl, event_ttl) do
    case run_autofde_cli(["sa2a", "graphlaw", "hooks", "--ttl", base_ttl, "--event-ttl", event_ttl]) do
      {:ok, %{"action" => "hooks", "result" => res}} -> {:ok, res}
      {:ok, %{"error" => err}} -> {:error, {:graphlaw_error, err}}
      other -> other
    end
  end
end

