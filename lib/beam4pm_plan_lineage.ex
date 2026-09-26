defmodule BeamPM.PlanLineage do
  @moduledoc """
  Hand-authored hash chain over plan generations, emitting the generated
  `BeamPM.Types.PlanLineage` struct (CO-047) per link.

  Digests are `sha256` (lowercase hex) of a canonical JSON rendering: map keys
  are stringified and sorted, lists keep their order, atoms render as strings,
  and there is no insignificant whitespace. The same term therefore always
  digests to the same value regardless of map construction order.

  Each link's `lineage_hash` is the digest of
  `%{"parent_lineage_hash", "parent_plan_id", "payload_digest", "plan_id"}`,
  so the head hash commits to every earlier generation. `verify/1` recomputes
  the chain from the stored payload digests and refuses the first link that
  does not match.

  Authority: NONE. A lineage is evidence (ceiling CONSTRUCT); it never grants
  permission to actuate a plan.
  """

  alias BeamPM.Types.PlanLineage, as: Link

  @genesis "genesis"

  defstruct links: []

  @typedoc "One chain entry: the emitted struct plus the payload digest it commits to."
  @type entry :: %{link: Link.t(), payload_digest: String.t()}

  @type t :: %__MODULE__{links: [entry()]}

  @doc "An empty chain."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The genesis parent hash every chain starts from."
  @spec genesis_hash() :: String.t()
  def genesis_hash, do: @genesis

  @doc "Canonical, sorted-key JSON of `term` as a binary."
  @spec canonical_json(term()) :: String.t()
  def canonical_json(term), do: term |> encode() |> IO.iodata_to_binary()

  @doc "sha256 hex of the canonical JSON of `term`."
  @spec digest(term()) :: String.t()
  def digest(term) do
    :crypto.hash(:sha256, canonical_json(term)) |> Base.encode16(case: :lower)
  end

  @doc "Current head link, or `nil` for an empty chain."
  @spec head(t()) :: Link.t() | nil
  def head(%__MODULE__{links: []}), do: nil
  def head(%__MODULE__{links: [%{link: link} | _]}), do: link

  @doc "Current head `lineage_hash`, or the genesis hash for an empty chain."
  @spec head_hash(t()) :: String.t()
  def head_hash(chain) do
    case head(chain) do
      nil -> @genesis
      %Link{lineage_hash: hash} -> hash
    end
  end

  @doc "Links oldest-first."
  @spec links(t()) :: [Link.t()]
  def links(%__MODULE__{links: links}), do: links |> Enum.reverse() |> Enum.map(& &1.link)

  @doc """
  Appends a generation `plan_id` derived from the current head, committing to
  `payload` (any JSON-shaped term). Returns the emitted struct and the new chain.
  """
  @spec derive(t(), String.t(), term()) :: {Link.t(), t()}
  def derive(%__MODULE__{links: links} = chain, plan_id, payload) when is_binary(plan_id) do
    parent_plan_id =
      case head(chain) do
        nil -> nil
        %Link{plan_id: id} -> id
      end

    payload_digest = digest(payload)
    hash = link_hash(head_hash(chain), parent_plan_id, plan_id, payload_digest)

    {:ok, link} =
      Link.new(%{plan_id: plan_id, parent_plan_id: parent_plan_id, lineage_hash: hash})

    {link, %__MODULE__{links: [%{link: link, payload_digest: payload_digest} | links]}}
  end

  @doc """
  Recomputes every link from genesis. `:ok` or
  `{:error, {:lineage_broken, index, plan_id}}` naming the first bad link
  (0 = oldest).
  """
  @spec verify(t()) :: :ok | {:error, {:lineage_broken, non_neg_integer(), String.t() | nil}}
  def verify(%__MODULE__{links: links}) do
    links
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce_while({@genesis, nil}, fn {%{link: link, payload_digest: pd}, idx},
                                             {prev_hash, prev_plan} ->
      expected = link_hash(prev_hash, prev_plan, link.plan_id, pd)

      if link.lineage_hash == expected and link.parent_plan_id == prev_plan do
        {:cont, {expected, link.plan_id}}
      else
        {:halt, {:error, {:lineage_broken, idx, link.plan_id}}}
      end
    end)
    |> case do
      {:error, _} = err -> err
      {_hash, _plan} -> :ok
    end
  end

  defp link_hash(parent_hash, parent_plan_id, plan_id, payload_digest) do
    digest(%{
      "parent_lineage_hash" => parent_hash,
      "parent_plan_id" => parent_plan_id,
      "payload_digest" => payload_digest,
      "plan_id" => plan_id
    })
  end

  # -- canonical JSON encoder ------------------------------------------------

  defp encode(%_{} = struct), do: struct |> Map.from_struct() |> encode()

  defp encode(map) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {k, v} -> {key(k), v} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> [JSON.encode!(k), ?:, encode(v)] end)
      |> Enum.intersperse(?,)

    [?{, pairs, ?}]
  end

  defp encode(list) when is_list(list),
    do: [?[, list |> Enum.map(&encode/1) |> Enum.intersperse(?,), ?]]

  defp encode(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> encode()
  defp encode(nil), do: "null"
  defp encode(bool) when is_boolean(bool), do: JSON.encode!(bool)
  defp encode(atom) when is_atom(atom), do: JSON.encode!(Atom.to_string(atom))
  defp encode(other), do: JSON.encode!(other)

  defp key(k) when is_binary(k), do: k
  defp key(k) when is_atom(k), do: Atom.to_string(k)
  defp key(k), do: canonical_json(k)
end
