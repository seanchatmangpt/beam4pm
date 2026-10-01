defmodule Beam4pmEx4pmRuntimeTest do
  @moduledoc """
  Falsifiable proof that the ex4pm evidence store — the sink
  `AshEx4pm.Notifier` writes into via `Ex4pm.Stream.Ingest.ingest_envelope/2`
  (`deps/ash_ex4pm/lib/ash_ex4pm/notifier.ex:153`) — is ALIVE under beam4pm's
  boot, and that ingest behaves as documented.

  Assertions are made against the real, read source:

  - `deps/ex4pm/lib/ex4pm/application.ex:14-20` — `Ex4pm.Application`
    (the `:ex4pm` mod, `deps/ex4pm/mix.exs:59`) starts
    `Ex4pm.Evidence.Store` unconditionally; `config :ex4pm, wasm_host: false`
    (config/config.exs:54, resolution R6) only drops ex4pm's own wasm hosts,
    never the store.
  - `deps/ex4pm/lib/ex4pm/evidence.ex:78-98` — the store is a GenServer
    registered under its own module name, with `get_by_subject/1` as the
    public read path.
  - `deps/ex4pm/lib/ex4pm/stream/ingest.ex:139-148` — success returns
    `{:ok, %{status: :ingested, subject_hash, event_count, object_count,
    sequence, agent_id, run_id}}`; `run_id` defaults to `agent_id`
    (ingest.ex:100).
  - `deps/ex4pm/lib/ex4pm/stream/ingest.ex:63-86` — duplicates are detected
    by a deterministic content hash of the normalized log
    (`log.subject.hash`) matched against an existing `:outcome` receipt,
    returning `{:ok, %{status: :duplicate_ignored, ..., original_receipt_hash}}`.
  - `deps/ex4pm/lib/ex4pm/ocel.ex:442-446` — an envelope without `events`
    is refused `{:error, %Ex4pm.Refusal{code: :missing_envelope_events}}`
    (`Ex4pm.Refusal` struct: deps/ex4pm/lib/ex4pm/core.ex:30-49).

  Envelopes are built exactly like `AshEx4pm.Notifier.build_envelope/2`
  (`deps/ash_ex4pm/lib/ash_ex4pm/notifier.ex:243-273`): string keys
  `"schema"`/`"producer"`/`"sequence"`/`"objects"`/`"object_relationships"`/
  `"events"`, integer sequence, event maps with `"id"`/`"activity"`/
  `"timestamp"`/`"relationships"`/`"attributes"`.

  The store is a node singleton, so every envelope carries
  `System.unique_integer([:positive])`-derived event id, activity name,
  object id and sequence: the dedup key is normalized CONTENT
  (ingest.ex:54-62), so unique content gives every test an independent
  dedup domain regardless of execution order. `async: false` per lane
  contract (store + ports are shared).
  """

  use ExUnit.Case, async: false

  @producer_agent_id "beam4pm_ex4pm_runtime_test"

  # Builds one notifier-shaped envelope (AshEx4pm.Notifier.build_envelope/2
  # wire shape) with run-unique content. opts:
  #   :include_events? — set false to produce the events-less variant used
  #   by the typed-refusal test (same unique content otherwise).
  defp unique_envelope(opts \\ []) do
    include_events? = Keyword.get(opts, :include_events?, true)
    n = System.unique_integer([:positive])
    object_id = "obj_runtime_#{n}"

    base = %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => @producer_agent_id,
        "runtime" => "beam",
        "resource" => "Beam4pmEx4pmRuntimeTest"
      },
      "sequence" => n,
      "objects" => %{object_id => %{"id" => object_id, "type" => "RuntimeProof"}},
      "object_relationships" => []
    }

    if include_events? do
      Map.put(base, "events", [
        %{
          "id" => "ev_runtime_#{n}",
          "activity" => "runtime_proof_#{n}",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "relationships" => [%{"objectId" => object_id, "qualifier" => "primary"}],
          "attributes" => %{}
        }
      ])
    else
      base
    end
  end

  @tag :ex4pm_runtime
  test "Ex4pm.Evidence.Store is alive after beam4pm boot" do
    # Ex4pm.Application starts {Ex4pm.Evidence.Store, name: Ex4pm.Evidence.Store}
    # unconditionally (deps/ex4pm/lib/ex4pm/application.ex:16) — wasm_host: false
    # (config/config.exs:54) must not take the sink down (resolution R6).
    pid = Process.whereis(Ex4pm.Evidence.Store)
    assert is_pid(pid), "Ex4pm.Evidence.Store is not registered — the notifier sink is down"
    assert Process.alive?(pid)
  end

  @tag :ex4pm_runtime
  test "a valid notifier-shaped envelope ingests and receipts land in the evidence store" do
    envelope = unique_envelope()

    assert {:ok, result} = Ex4pm.Stream.Ingest.ingest_envelope(envelope)
    # Exact documented success shape (ingest.ex:139-148).
    assert %{
             status: :ingested,
             subject_hash: subject_hash,
             event_count: 1,
             object_count: 1,
             sequence: sequence,
             agent_id: @producer_agent_id,
             run_id: @producer_agent_id
           } = result

    assert subject_hash == result.subject_hash
    assert is_binary(subject_hash)
    assert sequence == envelope["sequence"]

    # The sink actually received the outcome receipt this ingest wrote
    # (ingest.ex:110-126 stores pending + outcome; read back via the real
    # public API, deps/ex4pm/lib/ex4pm/evidence.ex:92-93).
    receipts = Ex4pm.Evidence.Store.get_by_subject(subject_hash)
    assert is_list(receipts) and receipts != []

    outcome = Enum.find(receipts, &(&1.phase == :outcome))

    assert %Ex4pm.Evidence.Receipt{} = outcome,
           "no :outcome receipt in the store for this subject"

    assert outcome.subject_hash == subject_hash
    assert outcome.standing == :alive
  end

  @tag :ex4pm_runtime
  test "resubmitting the identical envelope is deduplicated by content hash" do
    # Same envelope object twice: the second must hit the content-hash dedup
    # (ingest.ex:63-69: an existing :outcome receipt for log.subject.hash),
    # not ingest a second copy.
    envelope = unique_envelope()

    assert {:ok, first} = Ex4pm.Stream.Ingest.ingest_envelope(envelope)
    assert first.status == :ingested

    assert {:ok, second} = Ex4pm.Stream.Ingest.ingest_envelope(envelope)

    assert %{
             status: :duplicate_ignored,
             subject_hash: subject_hash,
             original_receipt_hash: original_receipt_hash
           } = second

    assert subject_hash == first.subject_hash
    assert is_binary(original_receipt_hash)

    # original_receipt_hash names the real :outcome receipt the first ingest
    # stored (duplicate_result/3, ingest.ex:84) — cross-checked against the
    # store, not taken on faith.
    outcome =
      Enum.find(Ex4pm.Evidence.Store.get_by_subject(subject_hash), &(&1.phase == :outcome))

    assert %Ex4pm.Evidence.Receipt{} = outcome
    assert original_receipt_hash == outcome.hash
  end

  @tag :ex4pm_runtime
  test "an envelope without events is refused with the typed :missing_envelope_events code" do
    # Same otherwise-valid envelope, minus "events" — validate_envelope/1
    # refuses with code :missing_envelope_events (ocel.ex:442-446) and the
    # struct is Ex4pm.Refusal (core.ex:30-49).
    envelope = unique_envelope() |> Map.delete("events")

    assert {:error, refusal} = Ex4pm.Stream.Ingest.ingest_envelope(envelope)
    assert %Ex4pm.Refusal{} = refusal
    assert refusal.code == :missing_envelope_events
    assert is_binary(refusal.message) and refusal.message != ""
  end
end
