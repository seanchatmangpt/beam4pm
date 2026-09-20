defmodule BeamPM.Dfcm do
  @compile {:no_warn_undefined, AshAutofde.CascadeAllocator}

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

