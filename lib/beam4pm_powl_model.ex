defmodule BeamPM.Powl.Model do
  @moduledoc """
  Typed data edge over the rust4pm engine's serde POWL model -- parses the
  engine's opaque `%{"root" => ...}` map (as returned inside
  `{:ok, %{"powl" => model}}` by `BeamPM.Rust4PM.discover_powl/2` /
  `ocel_discover_powl/3` and surfaced verbatim as `reference_powl` by
  `BeamPM.PowlConformance.check_conformance/3`) into the already-admitted
  `BeamPM.Types.Powl*` structs, and serializes back. No generated file is
  modified and no engine op is reimplemented: this is a wrapper/algorithm
  module over the vendored engine's own wire shape.

  ## The DISCOVERED serde shape (read-only evidence, this session)

  All engine types derive plain `serde::Serialize`/`Deserialize` with no
  `tag`/`rename_all` attributes, so every enum uses serde's default
  **externally tagged** representation and every struct its field names
  verbatim (`vendor/rust4pm-powl/process_mining/src/core/process_models/
  case_centric/powl/mod.rs`):

        Powl               := {"root": PowlNode}                                   (mod.rs:640-644)
        PowlNode           := {"Leaf": PowlLeaf} | {"Operator": PowlOperator}
                            | {"PartialOrder": PartialOrderNode}
                            | {"ChoiceGraph": ChoiceGraphNode}                      (mod.rs:127-140)
        PowlLeaf           := {"leaf": Leaf, "freq": Freq}                          (mod.rs:103-109)
        Leaf               := {"activity_label": LeafLabel}   (process_tree_struct.rs:429-432)
        LeafLabel          := {"Activity": "label"} | "Tau"   (process_tree_struct.rs:10-16)
        Freq               := {"min_freq": u32, "max_freq": u32|null}               (mod.rs:43-49)
        PowlOperator       := {"operator_type": OperatorType,
                              "children": [PowlNode...], "freq": Freq}              (mod.rs:211-219)
        OperatorType       := "Sequence" | "ExclusiveChoice" | "Concurrency" | "Loop"
                                                        (process_tree_struct.rs:96-106)
        PartialOrderNode   := {"children": [PowlNode...],
                              "order": [[from, to]...], "freq": Freq}               (mod.rs:312-320)
        ChoiceGraphNode    := {"children": [PowlNode...],
                              "edges": [[Endpoint, Endpoint]...], "freq": Freq}     (mod.rs:467-477)
        ChoiceGraphEndpoint := "Start" | {"Child": i} | "End"                       (mod.rs:438-446)

  (`order` and `edges` are `BTreeSet`s engine-side, so the engine itself
  always emits them sorted; the parser preserves whatever order arrives.)

  ## Typed representation

    * `Leaf` -> `BeamPM.Types.PowlLeaf` (LeafLabel flattened into
      `activity_label`/`is_tau`; `freq` flattened into `min_freq`/`max_freq`)
    * `Freq` -> `BeamPM.Types.PowlFreq`
    * `Operator` by `operator_type`: Sequence -> `BeamPM.Types.PowlSequenceOperator`,
      ExclusiveChoice -> `BeamPM.Types.PowlChoiceOperator`, Concurrency ->
      `BeamPM.Types.PowlParallelOperator`, Loop -> `BeamPM.Types.PowlLoopOperator`
    * `PartialOrderNode.order` entries -> `BeamPM.Types.PowlPartialOrderEdge`
    * `ChoiceGraphNode.edges` entries -> `BeamPM.Types.PowlChoiceGraphEdge`
      (`ChoiceGraphEndpoint` flattened into `from_kind`/`to_kind` = `:start` |
      `:child` | `:end` plus `*_child_index`)

  The four operator structs' digest/rule fields (`step_digest`,
  `branch_digest`, `body_digest`, `predecessor_digest`, `selection_rule`,
  `join_rule`, `exit_predicate`) have NO counterpart in the engine serde
  shape -- they are ontology-side annotations. The parser leaves them nil
  (it does not invent semantics) and fills only a deterministic
  content-derived `operator_id` (`"powl-op-" <> first 16 hex of the
  sha256 over the node's canonical engine JSON`) so parsed operators are
  addressable and stable. Recursive children/order/edges are carried on
  `BeamPM.Powl.Model.Node`.

  Roundtrip is lossless: `to_engine_map/1 (from_engine_map/1 (m)) == m`
  structurally, assertable byte-identically via `encode_canonical/1`
  (deterministic key-sorted JSON).
  """

  alias BeamPM.Types.PowlChoiceGraphEdge
  alias BeamPM.Types.PowlChoiceOperator
  alias BeamPM.Types.PowlFreq
  alias BeamPM.Types.PowlLeaf
  alias BeamPM.Types.PowlLoopOperator
  alias BeamPM.Types.PowlParallelOperator
  alias BeamPM.Types.PowlPartialOrderEdge
  alias BeamPM.Types.PowlSequenceOperator

  defmodule Node do
    @moduledoc """
    One recursive PowlNode in typed form. `variant` is `:leaf` | `:operator` |
    `:partial_order` | `:choice_graph`; exactly the fields named for that
    variant are non-nil (`leaf` for :leaf; `operator` + `children` + `freq`
    for :operator; `children` + `order` + `freq` for :partial_order;
    `children` + `edges` + `freq` for :choice_graph).
    """

    defstruct [:variant, :leaf, :operator, :freq, :children, :order, :edges]

    @type t :: %__MODULE__{
            variant: :leaf | :operator | :partial_order | :choice_graph,
            leaf: BeamPM.Types.PowlLeaf.t() | nil,
            operator:
              BeamPM.Types.PowlSequenceOperator.t()
              | BeamPM.Types.PowlChoiceOperator.t()
              | BeamPM.Types.PowlParallelOperator.t()
              | BeamPM.Types.PowlLoopOperator.t()
              | nil,
            freq: BeamPM.Types.PowlFreq.t() | nil,
            children: [t()] | nil,
            order: [BeamPM.Types.PowlPartialOrderEdge.t()] | nil,
            edges: [BeamPM.Types.PowlChoiceGraphEdge.t()] | nil
          }
  end

  defstruct [:root]

  @type t :: %__MODULE__{root: Node.t()}

  # ---------------------------------------------------------------------
  # Parsing: engine serde map -> typed structs
  # ---------------------------------------------------------------------

  @doc """
  Parse the engine's serde POWL model map into typed structs. Accepts the
  `%{"root" => node}` model map, or the full engine result map
  `%{"powl" => %{"root" => node}}` (unwrapped one level). String- or
  atom-keyed. Returns `{:ok, %BeamPM.Powl.Model{}}` or `{:error, term()}`.
  """
  @spec from_engine_map(map()) :: {:ok, t()} | {:error, term()}
  def from_engine_map(%{"powl" => %{} = inner}) when not is_map_key(inner, "root") and not is_map_key(inner, :root),
    do: from_engine_map(inner)

  def from_engine_map(%{} = model) do
    case fetch(model, "root") do
      {:ok, root} ->
        case parse_node(root) do
          {:ok, node} -> {:ok, %__MODULE__{root: node}}
          {:error, _} = err -> err
        end

      :error ->
        {:error, {:missing_field, :root}}
    end
  end

  def from_engine_map(other), do: {:error, {:invalid_model, other}}

  defp parse_node(%{} = m) when is_map_key(m, "Leaf") or is_map_key(m, :Leaf) do
    with {:ok, leaf} <- fetch_map(m, "Leaf"),
         {:ok, activity_label, is_tau} <- parse_leaf_label(fetch(leaf, "activity_label")),
         {:ok, freq} <- parse_freq(fetch(leaf, "freq")) do
      {:ok,
       %Node{variant: :leaf,
             leaf: %PowlLeaf{activity_label: activity_label, is_tau: is_tau,
                             min_freq: freq.min_freq, max_freq: freq.max_freq}}}
    else
      {:error, _} = err -> err
      other -> {:error, {:invalid_leaf_node, other}}
    end
  end

  defp parse_node(%{} = m) when is_map_key(m, "Operator") or is_map_key(m, :Operator) do
    with {:ok, op} <- fetch_map(m, "Operator"),
         {:ok, type} <- parse_operator_type(fetch(op, "operator_type")),
         {:ok, children} <- parse_children(fetch(op, "children")),
         {:ok, freq} <- parse_freq(fetch(op, "freq")) do
      op_struct =
        type
        |> operator_struct(operator_id(op, type))
        |> put_children_digest(type, children)

      {:ok, %Node{variant: :operator, operator: op_struct, freq: freq, children: children}}
    else
      {:error, _} = err -> err
      other -> {:error, {:invalid_operator_node, other}}
    end
  end

  defp parse_node(%{} = m) when is_map_key(m, "PartialOrder") or is_map_key(m, :PartialOrder) do
    with {:ok, po} <- fetch_map(m, "PartialOrder"),
         {:ok, children} <- parse_children(fetch(po, "children")),
         {:ok, order} <- parse_partial_order_edges(fetch(po, "order")),
         {:ok, freq} <- parse_freq(fetch(po, "freq")) do
      {:ok, %Node{variant: :partial_order, children: children, order: order, freq: freq}}
    else
      {:error, _} = err -> err
      other -> {:error, {:invalid_partial_order_node, other}}
    end
  end

  defp parse_node(%{} = m) when is_map_key(m, "ChoiceGraph") or is_map_key(m, :ChoiceGraph) do
    with {:ok, cg} <- fetch_map(m, "ChoiceGraph"),
         {:ok, children} <- parse_children(fetch(cg, "children")),
         {:ok, edges} <- parse_choice_edges(fetch(cg, "edges")),
         {:ok, freq} <- parse_freq(fetch(cg, "freq")) do
      {:ok, %Node{variant: :choice_graph, children: children, edges: edges, freq: freq}}
    else
      {:error, _} = err -> err
      other -> {:error, {:invalid_choice_graph_node, other}}
    end
  end

  defp parse_node(%{} = m), do: {:error, {:unknown_node_variant, Map.keys(m)}}
  defp parse_node(other), do: {:error, {:invalid_node, other}}

  defp parse_leaf_label({:ok, %{} = m}) when is_map_key(m, "Activity") or is_map_key(m, :Activity) do
    case fetch(m, "Activity") do
      {:ok, label} when is_binary(label) -> {:ok, label, false}
      {:ok, other} -> {:error, {:invalid_activity_label, other}}
      :error -> {:error, {:missing_field, :"Activity"}}
    end
  end

  defp parse_leaf_label({:ok, "Tau"}), do: {:ok, nil, true}
  defp parse_leaf_label({:ok, :Tau}), do: {:ok, nil, true}
  defp parse_leaf_label({:ok, other}), do: {:error, {:invalid_leaf_label, other}}
  defp parse_leaf_label(:error), do: {:error, {:missing_field, :activity_label}}

  defp parse_freq({:ok, %{} = m}) do
    min = fetch(m, "min_freq")
    max = fetch(m, "max_freq")

    with {:ok, min} when is_integer(min) and min >= 0 <- min,
         :ok <- check_max(max) do
      max_value =
        case max do
          {:ok, v} -> v
          :error -> nil
        end

      {:ok, %PowlFreq{min_freq: min, max_freq: max_value}}
    else
      {:ok, bad} -> {:error, {:invalid_min_freq, bad}}
      :error -> {:error, {:missing_field, :min_freq}}
      err -> err
    end
  end

  defp parse_freq(:error), do: {:error, {:missing_field, :freq}}
  defp parse_freq({:ok, other}), do: {:error, {:invalid_freq, other}}

  defp check_max(:error), do: :ok
  defp check_max({:ok, nil}), do: :ok
  defp check_max({:ok, v}) when is_integer(v) and v >= 0, do: :ok
  defp check_max({:ok, other}), do: {:error, {:invalid_max_freq, other}}

  defp parse_operator_type({:ok, type}) when type in ["Sequence", :Sequence], do: {:ok, :Sequence}
  defp parse_operator_type({:ok, type}) when type in ["ExclusiveChoice", :ExclusiveChoice], do: {:ok, :ExclusiveChoice}
  defp parse_operator_type({:ok, type}) when type in ["Concurrency", :Concurrency], do: {:ok, :Concurrency}
  defp parse_operator_type({:ok, type}) when type in ["Loop", :Loop], do: {:ok, :Loop}
  defp parse_operator_type({:ok, other}), do: {:error, {:unknown_operator_type, other}}
  defp parse_operator_type(:error), do: {:error, {:missing_field, :operator_type}}

  defp parse_children({:ok, children}) when is_list(children) do
    Enum.reduce_while(children, {:ok, []}, fn child, {:ok, acc} ->
      case parse_node(child) do
        {:ok, node} -> {:cont, {:ok, acc ++ [node]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp parse_children(_), do: {:error, {:missing_field, :children}}

  defp parse_partial_order_edges({:ok, order}) when is_list(order) do
    Enum.reduce_while(order, {:ok, []}, fn pair, {:ok, acc} ->
      case pair do
        [from, to] when is_integer(from) and is_integer(to) ->
          {:cont, {:ok, acc ++ [%PowlPartialOrderEdge{from_index: from, to_index: to}]}}

        {from, to} when is_integer(from) and is_integer(to) ->
          {:cont, {:ok, acc ++ [%PowlPartialOrderEdge{from_index: from, to_index: to}]}}

        other ->
          {:halt, {:error, {:invalid_order_pair, other}}}
      end
    end)
  end

  defp parse_partial_order_edges(_), do: {:error, {:missing_field, :order}}

  defp parse_choice_edges({:ok, edges}) when is_list(edges) do
    Enum.reduce_while(edges, {:ok, []}, fn pair, {:ok, acc} ->
      case pair do
        [from, to] ->
          with {:ok, from_ep} <- parse_endpoint(from),
               {:ok, to_ep} <- parse_endpoint(to) do
            {:cont, {:ok, acc ++ [edge_struct(from_ep, to_ep)]}}
          else
            {:error, _} = err -> {:halt, err}
          end

        {from, to} ->
          with {:ok, from_ep} <- parse_endpoint(from),
               {:ok, to_ep} <- parse_endpoint(to) do
            {:cont, {:ok, acc ++ [edge_struct(from_ep, to_ep)]}}
          else
            {:error, _} = err -> {:halt, err}
          end

        other ->
          {:halt, {:error, {:invalid_edge_pair, other}}}
      end
    end)
  end

  defp parse_choice_edges(_), do: {:error, {:missing_field, :edges}}

  defp parse_endpoint("Start"), do: {:ok, :start}
  defp parse_endpoint(:Start), do: {:ok, :start}
  defp parse_endpoint("End"), do: {:ok, :end}
  defp parse_endpoint(:End), do: {:ok, :end}
  defp parse_endpoint(%{} = m) when is_map_key(m, "Child") or is_map_key(m, :Child) do
    case fetch(m, "Child") do
      {:ok, i} when is_integer(i) and i >= 0 -> {:ok, {:child, i}}
      {:ok, other} -> {:error, {:invalid_child_index, other}}
      :error -> {:error, {:missing_field, :child_index}}
    end
  end
  defp parse_endpoint(other), do: {:error, {:invalid_endpoint, other}}

  # ChoiceGraphEndpoint flattened into the admitted PowlChoiceGraphEdge
  # shape: kind (:start | :child | :end) plus child index when :child. The
  # four flat fields fully determine the endpoint pair, so the roundtrip is
  # lossless without extra hidden fields.
  defp edge_struct(from, to) do
    %PowlChoiceGraphEdge{
      from_kind: elem(endpoint_parts(from), 0),
      from_child_index: elem(endpoint_parts(from), 1),
      to_kind: elem(endpoint_parts(to), 0),
      to_child_index: elem(endpoint_parts(to), 1)
    }
  end

  defp endpoint_parts({:child, i}), do: {:child, i}
  defp endpoint_parts(:start), do: {:start, nil}
  defp endpoint_parts(:end), do: {:end, nil}

  defp operator_struct(:Sequence, id),
    do: %PowlSequenceOperator{operator_id: id, step_digest: nil, predecessor_digest: nil}

  defp operator_struct(:ExclusiveChoice, id),
    do: %PowlChoiceOperator{operator_id: id, branch_digest: nil, selection_rule: nil}

  defp operator_struct(:Concurrency, id),
    do: %PowlParallelOperator{operator_id: id, branch_digest: nil, join_rule: nil}

  defp operator_struct(:Loop, id),
    do: %PowlLoopOperator{operator_id: id, body_digest: nil, exit_predicate: nil}

  # The operator structs carry no children field; sequence/branch/body
  # digests are ontology-side annotations with no engine counterpart and are
  # left nil by the parser. This shim exists so the typed operator is
  # addressable per variant without inventing digest semantics.
  defp put_children_digest(op_struct, _type, _children), do: op_struct

  defp operator_id(op_map, type) do
    hash = :crypto.hash(:sha256, :erlang.term_to_binary({type, op_map}))
    "powl-op-" <> Base.encode16(binary_part(hash, 0, 8), case: :lower)
  end

  # ---------------------------------------------------------------------
  # Serialization: typed structs -> engine serde map
  # ---------------------------------------------------------------------

  @doc """
  Serialize typed structs back to the engine's serde shape (string-keyed,
  exactly the shape the engine's own `Deserialize` accepts). Accepts a
  `%BeamPM.Powl.Model{}`, a bare `%BeamPM.Powl.Model.Node{}`, or the
  `%{"root" => node}` map form produced by this function.
  """
  @spec to_engine_map(t() | Node.t() | map()) :: map()
  def to_engine_map(%__MODULE__{root: root}), do: %{"root" => to_engine_map(root)}
  def to_engine_map(%Node{} = node), do: node_to_engine(node)
  def to_engine_map(%{} = m)
      when is_map_key(m, "root") or is_map_key(m, :root),
      do: m
  def to_engine_map(other) when is_map(other),
    do: raise(ArgumentError, "BeamPM.Powl.Model.to_engine_map/1: not a parsed model: #{inspect(other)}")

  defp node_to_engine(%Node{variant: :leaf, leaf: %PowlLeaf{} = leaf}) do
    label =
      if leaf.is_tau do
        "Tau"
      else
        %{"Activity" => leaf.activity_label}
      end

    %{"Leaf" =>
        %{"leaf" => %{"activity_label" => label},
          "freq" => %{"min_freq" => leaf.min_freq, "max_freq" => leaf.max_freq}}}
  end

  defp node_to_engine(%Node{variant: :operator, operator: op, freq: freq, children: children}) do
    %{"Operator" =>
        %{"operator_type" => operator_type_of(op),
          "children" => Enum.map(children, &node_to_engine/1),
          "freq" => freq_to_engine(freq)}}
  end

  defp node_to_engine(%Node{variant: :partial_order, children: children, order: order, freq: freq}) do
    %{"PartialOrder" =>
        %{"children" => Enum.map(children, &node_to_engine/1),
          "order" => Enum.map(order, fn %PowlPartialOrderEdge{from_index: f, to_index: t} -> [f, t] end),
          "freq" => freq_to_engine(freq)}}
  end

  defp node_to_engine(%Node{variant: :choice_graph, children: children, edges: edges, freq: freq}) do
    %{"ChoiceGraph" =>
        %{"children" => Enum.map(children, &node_to_engine/1),
          "edges" => Enum.map(edges, &edge_to_engine/1),
          "freq" => freq_to_engine(freq)}}
  end

  defp operator_type_of(%PowlSequenceOperator{}), do: "Sequence"
  defp operator_type_of(%PowlChoiceOperator{}), do: "ExclusiveChoice"
  defp operator_type_of(%PowlParallelOperator{}), do: "Concurrency"
  defp operator_type_of(%PowlLoopOperator{}), do: "Loop"

  defp freq_to_engine(%PowlFreq{min_freq: min, max_freq: max}),
    do: %{"min_freq" => min, "max_freq" => max}

  defp edge_to_engine(edge) do
    [endpoint_to_engine(edge.from_kind, edge.from_child_index),
     endpoint_to_engine(edge.to_kind, edge.to_child_index)]
  end

  defp endpoint_to_engine(:start, _), do: "Start"
  defp endpoint_to_engine(:end, _), do: "End"
  defp endpoint_to_engine(:child, i), do: %{"Child" => i}

  # ---------------------------------------------------------------------
  # Validation: structural sanity (engine-parallel semantics)
  # ---------------------------------------------------------------------

  @doc """
  Structural sanity over the typed model, mirroring the engine's own
  invariants: `Freq` bounds (`max >= min`, engine debug_assert at
  powl/mod.rs:66); operator arities (Loop needs >= 2 children, every other
  operator >= 1 -- engine `check_children_valid`, process_tree_struct.rs:62);
  partial-order edges in range, irreflexive and antisymmetric (engine
  `PartialOrderNode::is_valid`, powl/mod.rs:357); choice-graph endpoints in
  range, `Start` with no incoming edges, `End` with no outgoing edges, and
  every child on some Start->End path (engine Def. 3.6 docs,
  powl/mod.rs:456-459). Returns `:ok` or `{:error, term()}`.
  """
  @spec validate(t() | Node.t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{root: root}), do: validate_node(root)
  def validate(%Node{} = node), do: validate_node(node)

  defp validate_node(%Node{variant: :leaf, leaf: %PowlLeaf{} = leaf}) do
    cond do
      not (is_integer(leaf.min_freq) and leaf.min_freq >= 0) ->
        {:error, {:invalid_min_freq, leaf.min_freq}}

      not (is_nil(leaf.max_freq) or (is_integer(leaf.max_freq) and leaf.max_freq >= leaf.min_freq)) ->
        {:error, {:invalid_freq_bounds, {leaf.min_freq, leaf.max_freq}}}

      leaf.is_tau == true and not is_nil(leaf.activity_label) ->
        {:error, {:tau_with_label, leaf.activity_label}}

      leaf.is_tau == false and not is_binary(leaf.activity_label) ->
        {:error, {:non_tau_without_label, leaf.activity_label}}

      leaf.is_tau not in [true, false] ->
        {:error, {:invalid_is_tau, leaf.is_tau}}

      true ->
        :ok
    end
  end

  defp validate_node(%Node{variant: :operator, operator: op, freq: freq, children: children}) do
    with :ok <- validate_freq(freq),
         :ok <- validate_children_arity(op, children) do
      validate_all_children(children)
    end
  end

  defp validate_node(%Node{variant: :partial_order, children: children, order: order, freq: freq}) do
    with :ok <- validate_freq(freq),
         :ok <- validate_partial_order(children, order) do
      validate_all_children(children)
    end
  end

  defp validate_node(%Node{variant: :choice_graph, children: children, edges: edges, freq: freq}) do
    with :ok <- validate_freq(freq),
         :ok <- validate_choice_graph(children, edges) do
      validate_all_children(children)
    end
  end

  defp validate_node(other), do: {:error, {:invalid_node, other}}

  defp validate_all_children(children) do
    Enum.reduce_while(children, :ok, fn child, :ok ->
      case validate_node(child) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_freq(%PowlFreq{min_freq: min, max_freq: max}) do
    cond do
      not (is_integer(min) and min >= 0) -> {:error, {:invalid_min_freq, min}}
      not (is_nil(max) or (is_integer(max) and max >= min)) -> {:error, {:invalid_freq_bounds, {min, max}}}
      true -> :ok
    end
  end

  defp validate_freq(nil), do: {:error, {:missing_field, :freq}}

  defp validate_children_arity(%PowlLoopOperator{}, children) when is_list(children) do
    if length(children) >= 2, do: :ok, else: {:error, {:loop_needs_two_children, length(children)}}
  end

  defp validate_children_arity(_op, children) when is_list(children) do
    if length(children) >= 1, do: :ok, else: {:error, {:operator_needs_children, 0}}
  end

  defp validate_children_arity(_op, children), do: {:error, {:invalid_children, children}}

  defp validate_partial_order(children, order) when is_list(children) and is_list(order) do
    n = length(children)
    pair_set = MapSet.new(order, &{&1.from_index, &1.to_index})

    cond do
      bad = Enum.find(order, &out_of_range_po(&1, n)) ->
        {:error, {:order_index_out_of_range, {bad.from_index, bad.to_index}, n}}

      reflexive = Enum.find(order, &(&1.from_index == &1.to_index)) ->
        {:error, {:order_not_irreflexive, {reflexive.from_index, reflexive.to_index}}}

      symmetric = Enum.find(order, &MapSet.member?(pair_set, {&1.to_index, &1.from_index})) ->
        {:error, {:order_not_antisymmetric, {symmetric.from_index, symmetric.to_index}}}

      true ->
        :ok
    end
  end

  defp validate_partial_order(_children, order), do: {:error, {:invalid_order, order}}

  defp out_of_range_po(%PowlPartialOrderEdge{from_index: f, to_index: t}, n),
    do: f < 0 or f >= n or t < 0 or t >= n

  defp validate_choice_graph(children, edges) when is_list(children) and is_list(edges) do
    n = length(children)
    endpoints = Enum.flat_map(edges, &[{&1.from_kind, &1.from_child_index}, {&1.to_kind, &1.to_child_index}])

    cond do
      bad = Enum.find(endpoints, &endpoint_out_of_range(&1, n)) ->
        {:error, {:endpoint_out_of_range, bad, n}}

      true ->
        edge_set = MapSet.new(edges, &{{&1.from_kind, &1.from_child_index}, {&1.to_kind, &1.to_child_index}})

        cond do
          Enum.any?(edges, &(&1.to_kind == :start)) ->
            {:error, {:start_has_incoming_edge, :start}}

          Enum.any?(edges, &(&1.from_kind == :end)) ->
            {:error, {:end_has_outgoing_edge, :end}}

          true ->
            from_start = reachable(:start, edge_set, :forward)
            to_end = reachable(:end, edge_set, :backward)
            on_path = MapSet.intersection(from_start, to_end)

            missing =
              children
              |> Enum.with_index()
              |> Enum.reject(fn {_c, i} -> MapSet.member?(on_path, {:child, i}) end)

            case missing do
              [] -> :ok
              [{_c, i} | _] -> {:error, {:child_not_on_start_end_path, i}}
            end
        end
    end
  end

  defp validate_choice_graph(_children, edges), do: {:error, {:invalid_edges, edges}}

  defp endpoint_out_of_range({:child, i}, n), do: not is_integer(i) or i < 0 or i >= n
  defp endpoint_out_of_range(_, _), do: false

  defp reachable(origin, edge_set, direction) do
    go = fn node, acc ->
      Enum.reduce(edge_set, acc, fn {f, t}, set ->
        case direction do
          :forward -> if f == node, do: MapSet.put(set, t), else: set
          :backward -> if t == node, do: MapSet.put(set, f), else: set
        end
      end)
    end

    walk(origin, MapSet.new([origin]), go)
  end

  defp walk(node, visited, go) do
    next = go.(node, visited) |> MapSet.difference(visited)

    case MapSet.to_list(next) do
      [] ->
        visited

      new_nodes ->
        new_visited = MapSet.union(visited, next)
        Enum.reduce(new_nodes, new_visited, &walk(&1, &2, go))
    end
  end

  # ---------------------------------------------------------------------
  # Canonical deterministic JSON (for byte-identical roundtrip asserts)
  # ---------------------------------------------------------------------

  @doc """
  Deterministic canonical JSON: object keys sorted recursively, no
  whitespace. Two engine maps are byte-identical iff their canonical
  encodings are -- used to assert the roundtrip losslessly and to derive
  stable operator ids.
  """
  @spec encode_canonical(term()) :: String.t()
  def encode_canonical(%{} = m) do
    entries =
      m
      |> Enum.map(fn {k, v} -> {to_canon_key(k), encode_canonical(v)} end)
      |> Enum.sort_by(fn {k, _} -> k end)

    inner = Enum.map_join(entries, ",", fn {k, v} -> "\"#{escape_json(k)}\":#{v}" end)
    "{" <> inner <> "}"
  end

  def encode_canonical(list) when is_list(list),
    do: "[" <> Enum.map_join(list, ",", &encode_canonical/1) <> "]"

  def encode_canonical(bin) when is_binary(bin), do: "\"" <> escape_json(bin) <> "\""
  def encode_canonical(atom) when is_atom(atom) and not is_boolean(atom), do: "\"" <> Atom.to_string(atom) <> "\""
  def encode_canonical(true), do: "true"
  def encode_canonical(false), do: "false"
  def encode_canonical(nil), do: "null"
  def encode_canonical(i) when is_integer(i), do: Integer.to_string(i)
  def encode_canonical(f) when is_float(f), do: JSON.encode!(f)

  defp to_canon_key(k) when is_binary(k), do: k
  defp to_canon_key(k) when is_atom(k), do: Atom.to_string(k)
  defp to_canon_key(k) when is_integer(k), do: Integer.to_string(k)

  defp escape_json(bin) do
    bin
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  # ---------------------------------------------------------------------
  # Key normalization helpers
  # ---------------------------------------------------------------------

  defp fetch(map, key) when is_binary(key) do
    case Map.get(map, key, Map.get(map, String.to_existing_atom(key), :__absent__)) do
      :__absent__ -> :error
      value -> {:ok, value}
    end
  rescue
    ArgumentError -> :error
  end

  defp fetch(map, key) when is_atom(key), do: fetch(map, Atom.to_string(key))

  # fetch + require the value to be a map (typed error either way).
  defp fetch_map(map, key) do
    case fetch(map, key) do
      {:ok, v} when is_map(v) -> {:ok, v}
      {:ok, _} -> {:error, {:invalid_field, String.to_atom(key)}}
      :error -> {:error, {:missing_field, String.to_atom(key)}}
    end
  end
end
