defmodule BeamPM.Powl.HddlPowl do
  @moduledoc """
  HDDL task network -> POWL partial-order converter (the 法面 producer for
  `BeamPM.Types.PowlPartialOrderPlan` / `PowlPartialOrderEdge` / `PowlLeaf`).

  `BeamPM.Types.HddlTaskNetwork` (lib/beam4pm_types.ex:9840) carries only
  `task_set_digest`/`ordering_digest` -- opaque digests that cannot be
  inverted into structure. This converter therefore accepts the explicit
  network structure (`%{tasks: [binary], ordering: [{i, j}]}` with indices
  into `tasks`) and PRODUCES the typed POWL structs plus the real plan
  digests: `order_digest` is computed over the transitively-closed strict
  order relation (matching the engine's own `PartialOrderNode::new`
  transitive closure, vendor/rust4pm-powl .../powl/mod.rs:326-352), so the
  digest names the same relation the engine would hold.

  No digests are inverted or faked: the digests on the produced plan are
  content digests over the explicit structure given here.
  """

  alias BeamPM.Types.PowlLeaf
  alias BeamPM.Types.PowlPartialOrderEdge
  alias BeamPM.Types.PowlPartialOrderPlan

  defmodule Network do
    @moduledoc """
    Explicit HDDL task-network structure: an ordered list of task names and
    strict precedence pairs (i must happen before j, indices into `tasks`).
    """

    defstruct [:tasks, :ordering]

    @type t :: %__MODULE__{
            tasks: [String.t()],
            ordering: [{non_neg_integer(), non_neg_integer()}]
          }
  end

  @doc """
  Convert an explicit task network into an admitted
  `BeamPM.Types.PowlPartialOrderPlan`: `operator_digest` over the ordered
  task list, `order_digest` over the transitively-closed order relation.
  The full typed POWL node (PowlLeaf children + PowlPartialOrderEdge set)
  is built by `build_partial_order/1` and is what the digests are computed
  over. Returns `{:ok, %PowlPartialOrderPlan{}}` or `{:error, term()}`.
  """
  @spec from_network(map() | Network.t()) :: {:ok, PowlPartialOrderPlan.t()} | {:error, term()}
  def from_network(%Network{} = network) do
    with {:ok, %{node: node, tasks: tasks}} <- build_partial_order(network) do
      n = length(tasks)
      closed = transitive_closure(MapSet.new(node.order, &{&1.from_index, &1.to_index}), n)

      plan_id =
        :crypto.hash(:sha256, :erlang.term_to_binary({tasks, MapSet.to_list(closed)}))
        |> Base.encode16(case: :lower)
        |> then(&"hddl-plan-" <> binary_part(&1, 0, 16))

       {:ok,
       %PowlPartialOrderPlan{
         plan_id: plan_id,
         operator_digest: digest_term({:tasks, tasks}),
         order_digest: digest_term({:order, MapSet.to_list(closed) |> Enum.sort()})
       }}
    else
      {:error, _} = err -> err
    end
  end

  def from_network(%{tasks: tasks, ordering: ordering}),
    do: from_network(%Network{tasks: tasks, ordering: ordering})

  def from_network(other), do: {:error, {:invalid_network, other}}

  @doc """
  Build the typed POWL partial-order node for a task network: one
  `BeamPM.Types.PowlLeaf` per task (in task order), one
  `BeamPM.Types.PowlPartialOrderEdge` per strict-order pair. The order set
  is NOT transitively closed here (matching the parser's exact-preservation
  stance); `from_network/1` computes closure over this edge set for its
  `order_digest`. Returns `{:ok, %{node: BeamPM.Powl.Model.Node.t(), tasks: tasks}}`
  or `{:error, term()}`.
  """
  @spec build_partial_order(map() | Network.t()) ::
          {:ok, %{node: BeamPM.Powl.Model.Node.t(), tasks: [String.t()]}} | {:error, term()}
  def build_partial_order(%Network{tasks: tasks, ordering: ordering}) do
    cond do
      not is_list(tasks) ->
        {:error, {:invalid_field, :tasks}}

      tasks == [] ->
        {:error, {:invalid_field, :empty_tasks}}

      not Enum.all?(tasks, &is_binary/1) ->
        {:error, {:invalid_field, :task_names}}

      not is_list(ordering) ->
        {:error, {:invalid_field, :ordering}}

      true ->
        with :ok <- check_indices(ordering, length(tasks)),
             :ok <- check_antisymmetric(ordering) do
          children = Enum.map(tasks, &%PowlLeaf{activity_label: &1, is_tau: false, min_freq: 1, max_freq: 1})

          order =
            ordering
            |> Enum.uniq()
            |> Enum.sort()
            |> Enum.map(fn {i, j} -> %PowlPartialOrderEdge{from_index: i, to_index: j} end)

          # A partial-order node in the engine model always carries a Freq
          # tag (powl/mod.rs:313-320); default exactly-once.
          node = %BeamPM.Powl.Model.Node{
            variant: :partial_order,
            children: children,
            order: order,
            freq: %BeamPM.Types.PowlFreq{min_freq: 1, max_freq: 1}
          }

          {:ok, %{node: node, tasks: tasks}}
        else
          {:error, _} = err -> err
        end
    end
  end

  def build_partial_order(%{tasks: tasks, ordering: ordering}),
    do: build_partial_order(%Network{tasks: tasks, ordering: ordering})

  def build_partial_order(other), do: {:error, {:invalid_network, other}}

  defp check_indices(ordering, n) do
    bad = Enum.find(ordering, fn {i, j} -> not (is_integer(i) and is_integer(j)) end)

    cond do
      bad != nil ->
        {:error, {:invalid_order_pair, bad}}

      out = Enum.find(ordering, fn {i, j} -> i < 0 or i >= n or j < 0 or j >= n end) ->
        {:error, {:order_index_out_of_range, out, n}}

      refl = Enum.find(ordering, fn {i, j} -> i == j end) ->
        {:error, {:order_not_irreflexive, refl}}

      true ->
        :ok
    end
  end

  defp check_antisymmetric(ordering) do
    pair_set = MapSet.new(ordering)

    case Enum.find(ordering, &MapSet.member?(pair_set, {elem(&1, 1), elem(&1, 0)})) do
      nil -> :ok
      pair -> {:error, {:order_not_antisymmetric, pair}}
    end
  end

  # Floyd-Warshall-style closure over the strict order relation, matching
  # the engine's PartialOrderNode::new (powl/mod.rs:330-345).
  @doc false
  @spec transitive_closure(MapSet.t(), non_neg_integer()) :: MapSet.t()
  def transitive_closure(closed, n) do
    changed? = fn set ->
      Enum.any?(set, fn {a, b} ->
        Enum.any?(0..(n - 1), fn c -> MapSet.member?(set, {b, c}) and not MapSet.member?(set, {a, c}) end)
      end)
    end

    step = fn set ->
      Enum.reduce(set, set, fn {a, b}, acc ->
        Enum.reduce(0..(n - 1), acc, fn c, acc2 ->
          if MapSet.member?(set, {b, c}), do: MapSet.put(acc2, {a, c}), else: acc2
        end)
      end)
    end

    fixpoint(closed, n, changed?, step)
  end

  defp fixpoint(set, n, changed?, step) do
    if changed?.(set) do
      fixpoint(step.(set), n, changed?, step)
    else
      set
    end
  end

  defp digest_term(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> Base.encode16(case: :lower)
end
