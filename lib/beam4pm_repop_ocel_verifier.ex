defmodule BeamPM.RepopOcelVerifier do
  @moduledoc """
  Ingest verifier for repop OCEL flushes: the beam4pm-side sibling of
  `BeamPM.ZcodeOcelVerifier` (reusing its five-stage shape), specialized to
  the repop wire envelope and the repop closed activity vocabulary.

  ## Repop wire envelope

      {"events": [{"id", "type", "time", "attributes", "relationships"}],
       "objects": [{"id", "type", "attributes", "relationships"}]}

  with the repop closed vocabulary (`repop packages/worker/src/ocel/vocab.ts`,
  pinned in `test/fixtures/repop_ocel/repop_vocab_manifest.json`,
  provenance-bound to the source file's sha256):

    - activities: `start`, `assign`, `execute`, `complete`, `fail`
    - qualifiers: `exec`, `assoc`
    - object types: `wo`, `machine`

  ## Chain law (parameterized)

  Both the digest algorithm and the canonical serialization are
  parameterized so either repop seal tier verifies:

    - `:algorithm` — `:sha256` (default; beam4pm's `:crypto` reality) or
      `:fnv1a32` (pure-Elixir port of the repop FNV transport-tier chain).
      repop's chain.ts link law is `link = H(parent || u32le(len) || bytes)`
      with genesis `H("")` — the framing is shared, only `H` differs.
      (`:blake3` — repop's blake3 tamper tier — is NOT implemented here;
      requesting it is a typed `{:refused, [unsupported_algorithm]}`,
      never a silent downgraded verification.)
    - `:canonical_form` — `:repop_canon_v1` (default): the per-event
      canonical bytes are the JS-identical JSON serialization
      `{"id":..,"relationships":[{"objectId":..,"qualifier":..}...],"time":..,"type":..}`
      (fixed key order, relationships in document order, string encoding
      identical to `JSON.stringify`). This is the pinned Y8 form;
      byte-parity with repop's chain.ts canonical bytes is UNVERIFIED until
      Y2's seal-tier landing and a cross-check court runs.

  For each event in document order: `parent` starts at genesis
  (`H("")`), the link digest is
  `H(parent_bytes || u32le(byte_size(canon)) || canon)`, and the head is
  the final link's hex. A receipt lies unless its `head_hash` equals the
  recomputed head.

  ## Admission report / refusals

  Admits only well-formed envelopes whose types are all in the pinned
  repop registry; refuses cross-vocabulary leakage with zcode and castle
  with typed refusals — never a silent pass. Refusal codes mirror the
  zcode verifier: `:envelope_malformed`, `:unparseable_log`,
  `:log_unreadable`, `:receipt_missing`, `:unparseable_receipt`,
  `:file_digest_mismatch`, `:event_count_mismatch`, `:ocel_chain_broken`,
  `:head_hash_mismatch`, `:algorithm_mismatch`,
  `:unsupported_algorithm`, `:cross_vocabulary_event_type`,
  `:cross_vocabulary_object_type`, `:cross_vocabulary_qualifier`.
  """

  @genesis_algorithms [:sha256, :fnv1a32]

  @typedoc "A typed refusal: refusal code plus human-readable detail."
  @type refusal :: {atom(), String.t()}

  @typedoc "Admission report for a verified repop OCEL flush."
  @type report :: %{
          required(:event_count) => pos_integer(),
          required(:head_hash) => String.t(),
          required(:object_count) => non_neg_integer(),
          required(:event_types) => [String.t()],
          required(:object_types) => [String.t()],
          required(:algorithm) => :sha256 | :fnv1a32,
          required(:file_digest) => String.t()
        }

  @doc """
  Verifies a repop OCEL flush (`.jsonocel`) against its sibling receipt
  (`.receipt.json`). Options:

    - `:receipt_path` — explicit receipt path (default: extension swap)
    - `:algorithm` — `:sha256` (default) or `:fnv1a32`; must match the
      receipt's `algorithm` field
    - `:canonical_form` — `:repop_canon_v1` (only pinned form)

  Returns `{:ok, report}` only when every check holds; any failure yields
  `{:refused, [refusal, ...]}` — never an exception, never a silent pass.
  """
  @spec verify(String.t(), keyword()) :: {:ok, report()} | {:refused, [refusal(), ...]}
  def verify(log_path, opts \\ []) when is_binary(log_path) and is_list(opts) do
    receipt_path = Keyword.get(opts, :receipt_path, default_receipt_path(log_path))
    algorithm = Keyword.get(opts, :algorithm, :sha256)
    canonical_form = Keyword.get(opts, :canonical_form, :repop_canon_v1)

    state =
      %{}
      |> put_algorithm(algorithm)
      |> put_canonical_form(canonical_form)
      |> decode_envelope(log_path)
      |> decode_receipt(receipt_path)
      |> check_algorithm()
      |> check_file_digest()
      |> check_event_count()
      |> check_ocel_chain()
      |> check_head_hash()

    case Map.get(state, :refusals, []) do
      [] ->
        doc = state.doc
        events = doc["events"]

        {:ok,
         %{
           event_count: length(events),
           head_hash: state.chain_head,
           object_count: length(doc["objects"]),
           event_types: events |> Enum.map(& &1["type"]) |> Enum.uniq(),
           object_types: doc["objects"] |> Enum.map(& &1["type"]) |> Enum.uniq(),
           algorithm: state.algorithm,
           file_digest: state.file_digest
         }}

      refusals_rev ->
        {:refused, Enum.reverse(refusals_rev)}
    end
  end

  @doc """
  Vocabulary-direction check, usable on its own:
  `:repop` requires every event/object type in the decoded doc to be in the
  pinned repop registry AND not in the zcode or castle vocabularies;
  `:zcode` and `:castle` are the mirrored laws (every type in that
  vocabulary, none in the repop registry). This is the seam the zcode and
  castle sides use to refuse repop types appearing in their logs.
  """
  @spec verify_vocabulary(map(), :repop | :zcode | :castle) ::
          :ok | {:refused, [refusal(), ...]}
  def verify_vocabulary(%{} = doc, direction) when direction in [:repop, :zcode, :castle] do
    case vocabulary_refusals(doc, direction) do
      [] -> :ok
      refusals -> {:refused, Enum.uniq(refusals)}
    end
  end

  # -- orchestration ---------------------------------------------------------

  defp put_algorithm(state, :sha256), do: Map.put(state, :algorithm, :sha256)
  defp put_algorithm(state, :fnv1a32), do: Map.put(state, :algorithm, :fnv1a32)
  defp put_algorithm(state, other), do: Map.put(state, :algorithm, other)

  defp put_canonical_form(state, :repop_canon_v1), do: Map.put(state, :canonical_form, :repop_canon_v1)
  defp put_canonical_form(state, other), do: Map.put(state, :canonical_form, other)

  defp decode_envelope(state, log_path) do
    case read_file(log_path) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, doc} ->
            case envelope_shape_ok(doc) do
              :ok ->
                state
                |> Map.put(:doc, doc)
                |> Map.put(:raw_text, text)
                |> add_vocabulary_refusals(doc)

              {:malformed, detail} ->
                refuse(state, {:envelope_malformed, detail})
            end

          {:error, %Jason.DecodeError{}} ->
            refuse(state, {:unparseable_log, "log is not valid JSON"})
        end

      {:error, reason} ->
        refuse(state, {:log_unreadable, "could not read #{log_path}: #{inspect(reason)}"})
    end
  end

  # repop wire envelope: events + objects lists (no objectTypes/eventTypes
  # registry arrays — the repop vocabulary is the closed manifest, not a
  # per-log declaration).
  defp envelope_shape_ok(%{"events" => evs, "objects" => objs})
       when is_list(evs) and is_list(objs) do
    cond do
      not Enum.all?(evs, &event_shape_ok?/1) ->
        {:malformed, "every event needs string id/type/time plus attributes and relationships lists"}

      not Enum.all?(objs, &object_shape_ok?/1) ->
        {:malformed, "every object needs string id/type plus attributes and relationships lists"}

      true ->
        :ok
    end
  end

  defp envelope_shape_ok(_),
    do: {:malformed, "doc needs events/objects lists"}

  defp event_shape_ok?(%{"id" => id, "type" => t, "time" => time, "attributes" => attrs, "relationships" => rels})
       when is_binary(id) and is_binary(t) and is_binary(time) and is_list(attrs) and is_list(rels) do
    Enum.all?(attrs, &named_string_pair?/1) and Enum.all?(rels, &object_id_qualifier?/1)
  end

  defp event_shape_ok?(_), do: false

  defp object_shape_ok?(%{"id" => id, "type" => t, "attributes" => attrs, "relationships" => rels})
       when is_binary(id) and is_binary(t) and is_list(attrs) and is_list(rels) do
    Enum.all?(attrs, &named_string_pair?/1) and Enum.all?(rels, &object_id_qualifier?/1)
  end

  defp object_shape_ok?(_), do: false

  defp named_string_pair?(%{"name" => n, "value" => v}) when is_binary(n) and is_binary(v), do: true
  defp named_string_pair?(_), do: false

  defp object_id_qualifier?(%{"objectId" => oid, "qualifier" => q}) when is_binary(oid) and is_binary(q) do
    q in ["exec", "assoc"]
  end

  defp object_id_qualifier?(_), do: false

  defp decode_receipt(state, receipt_path) do
    case read_file(receipt_path) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, receipt} ->
            Map.put(state, :receipt, receipt)

          {:error, %Jason.DecodeError{}} ->
            refuse(state, {:unparseable_receipt, "receipt is not valid JSON"})
        end

      {:error, reason} ->
        refuse(state, {:receipt_missing, "could not read #{receipt_path}: #{inspect(reason)}"})
    end
  end

  defp check_algorithm(%{algorithm: alg} = state) when alg in @genesis_algorithms do
    case state[:receipt] do
      %{"algorithm" => claimed} when is_binary(claimed) ->
        expected = Atom.to_string(alg)

        if claimed == expected do
          state
        else
          refuse(state, {:algorithm_mismatch, "receipt algorithm #{inspect(claimed)} != requested #{inspect(expected)}"})
        end

      _ ->
        refuse(state, {:envelope_malformed, "receipt lacks algorithm"})
    end
  end

  defp check_algorithm(state) do
    refuse(state, {:unsupported_algorithm, "algorithm #{inspect(state[:algorithm])} is not implemented; implemented: sha256, fnv1a32"})
  end

  defp check_file_digest(%{raw_text: raw, receipt: %{"repop_file_digest" => claimed}, algorithm: alg} = state)
       when is_binary(raw) and alg in @genesis_algorithms do
    actual = digest_hex(state.algorithm, raw)

    if actual == claimed do
      Map.put(state, :file_digest, actual)
    else
      refuse(state, {:file_digest_mismatch, "repop_file_digest differs from the log bytes"})
    end
  end

  defp check_file_digest(%{raw_text: raw} = state) when is_binary(raw) do
    refuse(state, {:envelope_malformed, "receipt lacks repop_file_digest"})
  end

  defp check_file_digest(state), do: state

  defp check_event_count(%{doc: doc, receipt: %{"event_count" => claimed}} = state) do
    actual = length(doc["events"])

    if actual == claimed do
      state
    else
      refuse(state, {:event_count_mismatch, "receipt event_count #{claimed} != #{actual} events"})
    end
  end

  defp check_event_count(state), do: state

  # -- OCEL event hash chain (parameterized link framing) --------------------

  defp check_ocel_chain(%{doc: %{"events" => events}} = state) do
    case Enum.reduce_while(events, {:ok, genesis_hex(state.algorithm)}, fn event, {:ok, parent} ->
             case chain_step(state, event, parent) do
               {:ok, hash} -> {:cont, {:ok, hash}}
               {:mismatch, detail} -> {:halt, {:mismatch, detail}}
             end
           end) do
      {:ok, head} -> Map.put(state, :chain_head, head)
      {:mismatch, detail} -> refuse(state, {:ocel_chain_broken, detail})
    end
  end

  defp check_ocel_chain(state), do: state

  defp chain_step(%{algorithm: algorithm}, event, parent) do
    hash = attr_value(event, "rep_hash")

    cond do
      attr_value(event, "rep_parent") != parent ->
        {:mismatch, "parent mismatch at #{event["id"]}"}

      hash != link_digest_hex(parent, canon(event), algorithm) ->
        {:mismatch, "hash mismatch at #{event["id"]}"}

      true ->
        {:ok, hash}
    end
  end

  defp attr_value(event, name) do
    case Enum.find(event["attributes"], &(&1["name"] == name)) do
      %{"value" => v} -> v
      nil -> nil
    end
  end

  @doc """
  The canonical serialization for one repop event, pinned as
  `:repop_canon_v1`: JS-identical JSON with fixed key order `id`,
  `relationships` (document order, fixed key order `objectId`, `qualifier`),
  `time`, `type`.
  """
  @spec canon(map()) :: String.t()
  def canon(event) do
    rels =
      event["relationships"]
      |> Enum.map(fn r ->
        ~s({"objectId":#{json(r["objectId"])},"qualifier":#{json(r["qualifier"])}})
      end)
      |> Enum.join(",")

    ~s({"id":#{json(event["id"])},"relationships":[#{rels}],"time":#{json(event["time"])},"type":#{json(event["type"])}})
  end

  # JS JSON.stringify-identical string encoding for canonical hashing.
  defp json(s) when is_binary(s), do: Jason.encode!(s)

  @doc """
  The link digest: `H(parent_bytes || u32le(byte_size(canon)) || canon)`
  with genesis `H("")` — repop chain.ts's link framing, parameterized over
  the digest algorithm.
  """
  @spec link_digest_hex(String.t(), String.t(), :sha256 | :fnv1a32) :: String.t()
  def link_digest_hex(parent_hex, canon_bytes, algorithm \\ :sha256) do
    parent = decode_parent(parent_hex, algorithm)
    data = parent <> <<byte_size(canon_bytes)::unsigned-little-integer-size(32)>> <> canon_bytes
    digest_hex(algorithm, data)
  end

  @doc """
  The chain genesis: `H("")` — for `:sha256` the well-known empty-input
  sha256; for `:fnv1a32` the FNV offset basis rendered as 8 lowercase hex
  chars.
  """
  @spec genesis_hex(:sha256 | :fnv1a32) :: String.t()
  def genesis_hex(:sha256), do: digest_hex(:sha256, "")
  def genesis_hex(:fnv1a32), do: digest_hex(:fnv1a32, "")

  defp decode_parent(parent_hex, :sha256) when is_binary(parent_hex) do
    case Base.decode16(parent_hex, case: :mixed) do
      {:ok, bytes} -> bytes
      :error -> <<>>
    end
  end

  defp decode_parent(parent_hex, :fnv1a32) do
    case Base.decode16(parent_hex, case: :mixed) do
      {:ok, <<h::unsigned-little-integer-size(32)>>} ->
        <<h::unsigned-big-integer-size(32)>>

      {:ok, _} ->
        <<>>

      :error ->
        <<>>
    end
  end

  # -- digest algorithms -----------------------------------------------------

  defp digest_hex(:sha256, data), do: Base.encode16(:crypto.hash(:sha256, data), case: :lower)

  defp digest_hex(:fnv1a32, data) do
    hash =
      data
      |> :binary.bin_to_list()
      |> Enum.reduce(2_166_136_261, fn byte, h ->
        :erlang.band(:erlang.bxor(h, byte), 0xFFFFFFFF) * 16_777_619
      end)
      |> :erlang.band(0xFFFFFFFF)

    # FNV links carry their parent as the 4 little-endian state bytes.
    <<hash::unsigned-little-integer-size(32)>> |> Base.encode16(case: :lower)
  end

  # -- head-hash binding ------------------------------------------------------

  defp check_head_hash(%{chain_head: head, receipt: %{"head_hash" => claimed}} = state) do
    if head == claimed do
      state
    else
      refuse(state, {:head_hash_mismatch, "receipt head_hash #{inspect(claimed)} != recomputed chain head #{inspect(head)}"})
    end
  end

  defp check_head_hash(%{chain_head: _} = state) do
    refuse(state, {:envelope_malformed, "receipt lacks head_hash"})
  end

  defp check_head_hash(state), do: state

  # -- vocabulary classification (pinned manifest) ---------------------------

  defp add_vocabulary_refusals(state, doc) do
    case vocabulary_refusals(doc, :repop) do
      [] -> state
      refusals -> Enum.reduce(refusals, state, fn r, st -> refuse(st, r) end)
    end
  end

  defp vocabulary_refusals(doc, direction) do
    manifest = pinned_manifest()
    registry = manifest["registry"]
    repop_events = MapSet.new(registry["event_types"])
    repop_objects = MapSet.new(registry["object_types"])
    repop_qualifiers = MapSet.new(registry["qualifiers"])
    zcode_events = MapSet.new(manifest["zcode_event_types"])
    zcode_objects = MapSet.new(manifest["zcode_object_types"])
    castle_events = MapSet.new(manifest["castle_event_types"])
    castle_objects = MapSet.new(manifest["castle_object_types"])

    {allowed_events, forbidden_events} =
      if direction == :repop do
        {repop_events, MapSet.union(zcode_events, castle_events)}
      else
        {if(direction == :zcode, do: zcode_events, else: castle_events), repop_events}
      end

    {allowed_objects, forbidden_objects} =
      if direction == :repop do
        {repop_objects, MapSet.union(zcode_objects, castle_objects)}
      else
        {if(direction == :zcode, do: zcode_objects, else: castle_objects), repop_objects}
      end

    event_types = Enum.map(doc["events"] || [], & &1["type"])

    qualifiers =
      ((doc["events"] || []) ++ (doc["objects"] || []))
      |> Enum.flat_map(&Map.get(&1, "relationships", []))
      |> Enum.map(&Map.get(&1, "qualifier"))

    object_types =
      Enum.uniq(Enum.map(doc["objects"] || [], & &1["type"]))

    Enum.flat_map(event_types, fn t ->
      cond do
        not MapSet.member?(allowed_events, t) ->
          [{:cross_vocabulary_event_type, "#{direction} log carries event type #{inspect(t)} outside the #{direction} registry"}]

        MapSet.member?(forbidden_events, t) ->
          [{:cross_vocabulary_event_type, "#{direction} log carries event type #{inspect(t)} from the opposite vocabulary"}]

        true ->
          []
      end
    end) ++
      Enum.flat_map(object_types, fn t ->
        cond do
          not MapSet.member?(allowed_objects, t) ->
            [{:cross_vocabulary_object_type, "#{direction} log carries object type #{inspect(t)} outside the #{direction} registry"}]

          MapSet.member?(forbidden_objects, t) ->
            [{:cross_vocabulary_object_type, "#{direction} log carries object type #{inspect(t)} from the opposite vocabulary"}]

          true ->
            []
        end
      end) ++
      # qualifier law is repop-only (zcode/castle logs carry no repop
      # qualifier law of their own, so the check applies in the :repop
      # direction only).
      if direction == :repop do
        Enum.flat_map(qualifiers, fn q ->
          if MapSet.member?(repop_qualifiers, q) do
            []
          else
            [{:cross_vocabulary_qualifier, "repop log carries relationship qualifier #{inspect(q)} outside the repop qualifier registry"}]
          end
        end)
      else
        []
      end
  end

  @doc """
  The pinned manifest as a decoded map. Path overridable via `:manifest_path`
  (used by the drift test); defaults to
  `test/fixtures/repop_ocel/repop_vocab_manifest.json` under the project
  root.
  """
  @spec pinned_manifest(keyword()) :: map()
  def pinned_manifest(opts \\ []) do
    opts
    |> Keyword.get(:manifest_path, manifest_path())
    |> File.read!()
    |> Jason.decode!()
  end

  defp manifest_path do
    app_dir = Application.app_dir(:beam4pm)
    Path.expand("../../../../test/fixtures/repop_ocel/repop_vocab_manifest.json", app_dir)
  end

  # -- plumbing --------------------------------------------------------------

  defp refuse(state, {code, detail}) do
    Map.update(state, :refusals, [{code, detail}], &[{code, detail} | &1])
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_receipt_path(log_path), do: String.replace_suffix(log_path, ".jsonocel", ".receipt.json")
end
