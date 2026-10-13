defmodule BeamPM.ZcodeOcelVerifier do
  @moduledoc """
  Ingests and judges zcode-cli OCEL 2.0 court evidence: decodes the
  `.jsonocel` envelope, verifies the hash chain bound into the events
  (faithful port of zcode-cli's `scripts/ocel-verify.ts` chain law, which is
  itself the generated `verifyChain` in `src/generated/ocel.ts`), verifies
  the sibling receipt chain (port of the generated `verify` in
  `src/generated/receipt.ts`), and classifies every event/object type against
  a pinned copy of zcode-cli's shared-vocabulary manifest
  (`test/fixtures/zcode_ocel/zcode_vocab_manifest.json`, provenance-pinned by
  the source file's sha256). Admits only well-formed envelopes whose types
  are all in the (disjoint) zcode registry; refuses cross-vocabulary leakage
  with typed refusals: a CastleOcel event name appearing in a zcode log, or a
  zcode type appearing in a CastleOcel log, is `{:refused, refusals}` — never
  a silent pass.

  Hand-written computation over admitted wire shapes (same convention as
  `BeamPM.Ocel`): nothing here is a projection of the ontology graph, and no
  generated file is modified.

  ## Chain law (ported verbatim from ocel-verify.ts / ocel.ts)

  For each event in document order, with `parent` starting at `""`:

    1. the `pi_parent` attribute must equal the previous event's hash;
    2. `pi_hash` must equal
       `sha256(parent <> "\\n" <> canon(event, phase, pending_ref))`
       where `canon/3` is the cross-language canonical JSON form (keys
       sorted: `id`, optional `pendingRef`/`phase` when phased,
       `relationships` in document order, `time`, `type`) and `phase` comes
       from the generated `PHASED` table — empty for every zcode type, so
       phase is always `""` and `pending_ref` is never bound;
    3. the phase attribute (`pi_phase`), when the PHASED table is non-empty,
       must match the table; open/close pairing closes over the CLOSES table
       (also empty for zcode — any pending/outcome-phased event is a pairing
       mismatch, which is the faithful port of `CLOSES: []`).

  The port covers the chain, file-digest, event-count, receipt-chain and
  undeclared-type checks of ocel-verify.ts. Deliberately NOT ported: the
  zcode turn-machine replay (`replayZcodeTurn` deviations), which is
  zcode-internal session law, not receipt/chain law, and the `--require`
  coverage flag, which is caller policy, not evidence admissibility.
  """

  @genesis String.duplicate("0", 64)
  # Port of src/generated/receipt.ts: FIELDS / PHASES / STANDINGS / NEUTRAL.
  @receipt_fields ~w(entry_id parent_hash phase standing subject action pending_ref)
  @receipt_phases ["pending", "outcome"]
  @receipt_standings ~w(alive blocked build_broken partial_alive unknown unsupported)
  @neutral_standing "unknown"

  @typedoc "A typed refusal: refusal code plus human-readable detail."
  @type refusal :: {atom(), String.t()}

  @typedoc "Admission report for a verified zcode OCEL log."
  @type report :: %{
          required(:event_count) => pos_integer(),
          required(:head_hash) => String.t(),
          required(:object_count) => non_neg_integer(),
          required(:event_types) => [String.t()],
          required(:object_types) => [String.t()],
          required(:receipt_intact) => boolean(),
          required(:file_sha256) => String.t()
        }

  @doc """
  Verifies a zcode `.jsonocel` log against its sibling `.receipt.json`.

  `log_path` must end in `.jsonocel`; the receipt defaults to the same path
  with the extension replaced by `.receipt.json`. Returns `{:ok, report}`
  only when every check holds; any failure yields
  `{:refused, [refusal, ...]}` with typed codes — never an exception and
  never a silent pass.
  """
  @spec verify(String.t(), keyword()) :: {:ok, report()} | {:refused, [refusal(), ...]}
  def verify(log_path, opts \\ []) when is_binary(log_path) and is_list(opts) do
    receipt_path = Keyword.get(opts, :receipt_path, default_receipt_path(log_path))

    state =
      %{}
      |> decode_envelope(log_path)
      |> decode_receipt(receipt_path)
      |> check_file_digest()
      |> check_event_count()
      |> check_ocel_chain()
      |> check_receipt_chain()

    case Map.get(state, :refusals, []) do
      [] ->
        doc = state.doc
        events = doc["events"]

        {:ok,
         %{
           event_count: length(events),
           head_hash: state.receipt["head_hash"],
           object_count: length(doc["objects"]),
           event_types: events |> Enum.map(& &1["type"]) |> Enum.uniq(),
           object_types: doc["objects"] |> Enum.map(& &1["type"]) |> Enum.uniq(),
           receipt_intact: true,
           file_sha256: state.file_sha256
         }}

      refusals_rev ->
        {:refused, Enum.reverse(refusals_rev)}
    end
  end

  @doc """
  Vocabulary-direction check, usable on its own for either direction:
  `:zcode` requires every event/object type in the decoded doc to be in the
  pinned zcode registry AND not in the CastleOcel vocabulary; `:castle` is
  the mirrored law (every type in the CastleOcel vocabulary, none in the
  zcode registry). This is the seam the CastleOcel side uses to refuse zcode
  types appearing in CastleOcel logs.
  """
  @spec verify_vocabulary(map(), :zcode | :castle) :: :ok | {:refused, [refusal(), ...]}
  def verify_vocabulary(%{} = doc, direction) when direction in [:zcode, :castle] do
    case vocabulary_refusals(doc, direction) do
      [] -> :ok
      refusals -> {:refused, Enum.uniq(refusals)}
    end
  end

  # -- orchestration ---------------------------------------------------------

  @acc_key :zcode_ocel_verifier_acc

  defp decode_envelope(state, log_path) do
    case read_file(log_path) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, doc} ->
            case envelope_shape_ok(doc) do
              :ok ->
                state
                |> put(%{doc: doc, raw_text: text})
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

  defp envelope_shape_ok(%{"objectTypes" => ots, "eventTypes" => ets, "objects" => objs, "events" => evs})
       when is_list(ots) and is_list(ets) and is_list(objs) and is_list(evs) do
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
    do: {:malformed, "doc needs objectTypes/eventTypes/objects/events lists"}

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

  defp object_id_qualifier?(%{"objectId" => oid, "qualifier" => q}) when is_binary(oid) and is_binary(q),
    do: true

  defp object_id_qualifier?(_), do: false

  defp decode_receipt(state, receipt_path) do
    case read_file(receipt_path) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, receipt} ->
            put(state, %{receipt: receipt})

          {:error, %Jason.DecodeError{}} ->
            refuse(state, {:unparseable_receipt, "receipt is not valid JSON"})
        end

      {:error, reason} ->
        refuse(state, {:receipt_missing, "could not read #{receipt_path}: #{inspect(reason)}"})
    end
  end

  defp check_file_digest(%{raw_text: raw, receipt: %{"ocel_file_sha256" => claimed}} = state)
       when is_binary(raw) do
    actual = sha256_hex(raw)

    if actual == claimed do
      put(state, %{file_sha256: actual})
    else
      refuse(state, {:file_digest_mismatch, "ocel_file_sha256 differs from the log bytes"})
    end
  end

  defp check_file_digest(%{raw_text: raw} = state) when is_binary(raw) do
    refuse(state, {:envelope_malformed, "receipt lacks ocel_file_sha256"})
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

  # -- OCEL event hash chain (port of ocel.ts verifyChain) -------------------

  defp check_ocel_chain(%{doc: %{"events" => events}} = state) do
    case Enum.reduce_while(events, {:ok, ""}, fn event, {:ok, parent} ->
           case chain_step(event, parent) do
             {:ok, hash} -> {:cont, {:ok, hash}}
             {:mismatch, detail} -> {:halt, {:mismatch, detail}}
           end
         end) do
      {:ok, head} -> put(state, %{chain_head: head})
      {:mismatch, detail} -> refuse(state, {:ocel_chain_broken, detail})
    end
  end

  defp check_ocel_chain(state), do: state

  # PHASED table is empty in the zcode registry: no type is phased.
  defp phased(_type), do: nil

  defp chain_step(event, parent) do
    attr = fn name ->
      case Enum.find(event["attributes"], &(&1["name"] == name)) do
        %{"value" => v} -> v
        nil -> nil
      end
    end

    phase = phased(event["type"]) || ""
    ref = attr.("pi_pending_ref") || ""
    hash = attr.("pi_hash")

    cond do
      attr.("pi_parent") != parent ->
        {:mismatch, "parent mismatch at #{event["id"]}"}

      hash != sha256_hex(parent <> "\n" <> canon(event, phase, ref)) ->
        {:mismatch, "hash mismatch at #{event["id"]}"}

      (attr.("pi_phase") || "") != phase ->
        {:mismatch, "phase mismatch at #{event["id"]}"}

      phase == "pending" ->
        if ref == "" do
          {:ok, hash}
        else
          {:mismatch, "pairing mismatch at #{event["id"]}"}
        end

      phase == "outcome" ->
        # CLOSES is empty in the zcode registry, so no close ever pairs —
        # faithful port of closesPair() over CLOSES: [].
        {:mismatch, "pairing mismatch at #{event["id"]}"}

      true ->
        {:ok, hash}
    end
  end

  @doc false
  @spec canon(map(), String.t(), String.t()) :: String.t()
  def canon(event, phase, ref) do
    rels =
      event["relationships"]
      |> Enum.map(fn r ->
        ~s({"objectId":#{json(r["objectId"])},"qualifier":#{json(r["qualifier"])}})
      end)
      |> Enum.join(",")

    bound =
      if phase == "" do
        ""
      else
        ~s(,"pendingRef":#{json(ref)},"phase":#{json(phase)})
      end

    ~s({"id":#{json(event["id"])}#{bound},"relationships":[#{rels}],"time":#{json(event["time"])},"type":#{json(event["type"])}})
  end

  # JS JSON.stringify-identical string encoding for canonical hashing.
  defp json(s) when is_binary(s), do: Jason.encode!(s)

  # -- receipt chain (port of receipt.ts verify) -----------------------------

  defp check_receipt_chain(%{receipt: %{"chain" => chain}} = state) when is_list(chain) do
    if receipt_chain_intact?(chain) do
      state
    else
      refuse(state, {:receipt_chain_broken, "receipt chain not intact"})
    end
  end

  defp check_receipt_chain(%{receipt: %{}} = state) do
    refuse(state, {:envelope_malformed, "receipt lacks chain"})
  end

  defp check_receipt_chain(state), do: state

  @doc """
  Faithful port of the generated `verify(chain)` from zcode-cli
  `src/generated/receipt.ts`: every entry's `hash` must be sha256 of its
  `field=value` canonical form, parents must link from genesis, pending
  entries carry neutral standing and empty `pending_ref`, outcome entries
  pair an open pending with the same action, seals require every pending
  closed and no prior seal, at most one seal, and a seal must be the final
  entry.
  """
  @spec receipt_chain_intact?(list()) :: boolean()
  def receipt_chain_intact?(chain) when is_list(chain) do
    receipt_walk(chain, @genesis, 0, %{}, MapSet.new(), true)
  end

  # `after_seal` enforces the final conjunct `(seals == 0 || last entry is a
  # seal)`: any entry following a seal fails, so a walked seal was last.
  # Unpaired pendings in an unsealed chain are NOT a verify() failure in the
  # source (receipt.ts reports them via unpaired/1, not verify/1) — the port
  # matches that exactly.
  defp receipt_walk([], _prev, seals, _seen, _used, _after_seal) do
    seals <= 1
  end

  defp receipt_walk([e | rest], prev, seals, seen, used, after_seal) do
    cond do
      after_seal == false ->
        false

      not entry_shape_ok?(e) ->
        false

      e["parent_hash"] != prev or e["hash"] != receipt_digest(e) ->
        false

      e["phase"] == "pending" ->
        if e["standing"] == @neutral_standing and e["pending_ref"] == "" do
          receipt_walk(rest, e["hash"], seals, Map.put(seen, e["hash"], e), used, true)
        else
          false
        end

      e["seal"] == true ->
        cond do
          e["pending_ref"] != "" ->
            false

          Enum.any?(Map.keys(seen), fn h -> not MapSet.member?(used, h) end) ->
            false

          true ->
            receipt_walk(rest, e["hash"], seals + 1, seen, used, false)
        end

      true ->
        # outcome entry pairing an open pending
        p = seen[e["pending_ref"]]

        if p && p["action"] == e["action"] and not MapSet.member?(used, e["pending_ref"]) do
          receipt_walk(rest, e["hash"], seals, seen, MapSet.put(used, e["pending_ref"]), true)
        else
          false
        end
    end
  end

  defp entry_shape_ok?(%{} = e) do
    Enum.all?(@receipt_fields, &is_binary(e[&1])) and is_binary(e["hash"]) and
      e["phase"] in @receipt_phases and e["standing"] in @receipt_standings
  end

  defp entry_shape_ok?(_), do: false

  defp receipt_digest(e) do
    @receipt_fields
    |> Enum.map(fn f ->
      v = e[f]

      if String.contains?(v, "\n") do
        raise ArgumentError, "LF in field #{f}"
      end

      f <> "=" <> v
    end)
    |> Enum.join("\n")
    |> sha256_hex()
  end

  # -- vocabulary classification (pinned manifest) ---------------------------

  defp add_vocabulary_refusals(state, doc) do
    case vocabulary_refusals(doc, :zcode) do
      [] -> state
      refusals -> Enum.reduce(refusals, state, fn r, st -> refuse(st, r) end)
    end
  end

  defp vocabulary_refusals(doc, direction) do
    manifest = pinned_manifest()
    registry = manifest["registry"]
    zcode_events = MapSet.new(registry["event_types"])
    zcode_objects = MapSet.new(registry["object_types"])
    castle_events = MapSet.new(manifest["castle_event_types"])
    castle_objects = MapSet.new(manifest["castle_object_types"])

    event_types = Enum.map(doc["events"] || [], & &1["type"])

    object_types =
      Enum.uniq(Enum.map(doc["objectTypes"] || [], & &1["name"]) ++ Enum.map(doc["objects"] || [], & &1["type"]))

    {allowed_events, forbidden_events} =
      if direction == :zcode do
        {zcode_events, castle_events}
      else
        {castle_events, zcode_events}
      end

    {allowed_objects, forbidden_objects} =
      if direction == :zcode do
        {zcode_objects, castle_objects}
      else
        {castle_objects, zcode_objects}
      end

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
      end)
  end

  @doc """
  The pinned manifest as a decoded map. Path overridable via `:manifest_path`
  (used by the drift test); defaults to
  `test/fixtures/zcode_ocel/zcode_vocab_manifest.json` under the project
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
    # app_dir is .../_build/test/lib/beam4pm; the pinned fixture lives in the
    # source tree, two levels above the profile dir.
    Path.expand("../../../../test/fixtures/zcode_ocel/zcode_vocab_manifest.json", app_dir)
  end

  # -- plumbing --------------------------------------------------------------

  defp put(state, map), do: Map.merge(state, map)

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

  defp sha256_hex(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  @doc false
  def __acc_key__, do: @acc_key
end
