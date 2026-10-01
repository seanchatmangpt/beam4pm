defmodule Beam4pmEx4pmSoakCorrectnessTest do
  @moduledoc """
  Chicago-style concurrent soak over the REALTIME ex4pm -> beam4pm seam:
  notifier-shaped envelopes -> `Ex4pm.Stream.Ingest.ingest_envelope/2`
  (broadcaster from `Application.get_env(:ash_ex4pm, :broadcaster)`) ->
  `BeamPM.Evidence.Ex4pmBridge` (scripts/ex4pm_bridge.exs) ->
  `BeamPM.Ingest.Bridge.ingest/1` (scripts/ingest_telemetry.exs, ETS buffer
  capped by `Application.get_env(:beam4pm, :ingest_buffer_cap, 50_000)`).

  Every collaborator is real: the real `Ex4pm.Evidence.Store` GenServer
  (node singleton, `async: false`), the real ingest engine
  (deps/ex4pm/lib/ex4pm/stream/ingest.ex), the real script-defined
  `BeamPM.Evidence.Ex4pmBridge` and `BeamPM.Ingest.Bridge`, the real
  `:telemetry` application. No mocks, no sleep-polling: telemetry delivery
  is drained from the test process's own mailbox -- the broadcaster runs
  synchronously inside `ingest_envelope/2`'s call stack (and the bridge's
  `:telemetry.execute/3` inside the broadcaster), so by the time an ingest
  returns its telemetry has ALREADY been relayed into this mailbox and a
  non-blocking drain is exact, not racy. The only bounded wait in the file
  is on a supervisor child restart, never on telemetry.

  Assertions are on FINAL STATE ONLY (Chicago): buffer contents, ingest
  return values, drained telemetry counts.

  Known-behavior documentation (L5 MAJOR, measured with numbers): with the
  `Ex4pm.Evidence.Store` down (supervisor-restarted with empty state), the
  content-hash dedup (ingest.ex:66-69) finds no `:outcome` receipt, so
  re-ingesting the SAME envelope returns `:ingested` both times and the
  event is broadcast TWICE (the identical event_id appears exactly 2x in
  the buffer). This test MEASURES and asserts the behavior AS CURRENTLY
  DOCUMENTED; if another lane fixes dedup upstream, the 2x assertion fails
  and must be relabeled as the fixed behavior.
  """

  use ExUnit.Case, async: false

  @ingested [:beam4pm, :ex4pm, :envelope, :ingested]
  @refused [:beam4pm, :ex4pm, :envelope, :refused]
  @producer_agent_id "beam4pm_ex4pm_soak_correctness_test"

  # Hard cap: the soak loop itself never runs past 90 seconds.
  @soak_cap_s 90
  @soak_s min(String.to_integer(System.get_env("SOAK_SECONDS") || "60"), @soak_cap_s)

  # The two bridge collaborators are script-defined (scripts/), so they are
  # required in setup before any use -- the same pattern the realtime bridge
  # test uses. The scripts' demo blocks must not run inside the test VM.
  setup do
    System.put_env("BEAM4PM_EX4PM_BRIDGE_SKIP_DEMO", "1")
    System.put_env("BEAM4PM_INGEST_SKIP_DEMO", "1")

    Code.require_file("scripts/ingest_telemetry.exs", File.cwd!())
    Code.require_file("scripts/ex4pm_bridge.exs", File.cwd!())

    assert :ok = BeamPM.Evidence.ensure_ingest_bridge_loaded()
    assert :ok = apply(BeamPM.Evidence.Ex4pmBridge, :ensure_loaded, [])

    previous = apply(BeamPM.Evidence.Ex4pmBridge, :attach, [])
    apply(BeamPM.Ingest.Bridge, :reset, [])

    on_exit(fn ->
      Application.put_env(:ash_ex4pm, :broadcaster, previous)
    end)

    :ok
  end

  @tag timeout: 150_000
  test "concurrent 8-way soak: no loss, no double-broadcast, every event_id unique" do
    collect_telemetry!(self(), :soak)
    apply(BeamPM.Ingest.Bridge, :reset, [])

    deadline = System.monotonic_time(:millisecond) + @soak_s * 1000
    {fresh_count, all_event_ids, refused_count} = soak_waves(deadline)

    events = buffer_events()
    event_ids = Enum.map(events, & &1.event_id)

    # 1. Uniqueness / no loss / no double-broadcast: exactly one buffered
    #    OcelEvent per fresh ingest, all ids distinct, ids match the set
    #    of ingested envelopes.
    assert length(events) == fresh_count,
           "buffered #{length(events)} events for #{fresh_count} fresh ingests"

    assert length(Enum.uniq(event_ids)) == length(event_ids),
           "duplicate event_id in the buffer"

    assert Enum.sort(event_ids) == Enum.sort(all_event_ids)

    # 5. Telemetry: exactly one [:beam4pm, :ex4pm, :envelope, :ingested]
    #    per fresh envelope, none missing, none extra.
    assert drained_telemetry_count(:soak) == fresh_count

    # 3. Refusals interleaved one-per-wave: every malformed envelope was
    #    typed-refused, none buffered, and no refused-family telemetry
    #    fired (refusal happens in validate_envelope, before any
    #    broadcaster exists in the flow).
    assert refused_count > 0, "expected at least one interleaved refusal wave"
    refute_receive {:soak, _, _}
    refute_receive {{:refused, :soak}, _, _}
  end

  test "dedup under a live store: N re-ingests return :duplicate_ignored, buffer unchanged, zero extra telemetry" do
    collect_telemetry!(self(), :dedup)
    apply(BeamPM.Ingest.Bridge, :reset, [])

    envelopes = for _ <- 1..12, do: unique_envelope()

    fresh =
      Task.async_stream(envelopes, &realtime_ingest/1,
        max_concurrency: 8,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(fresh, &match?({:ok, %{status: :ingested}}, &1)) == 12
    assert length(drain_telemetry()) == 12

    buffer_before = buffer_events()
    assert length(buffer_before) == 12

    # Re-ingest EVERY envelope again, concurrently, with the store up.
    again =
      Task.async_stream(envelopes, &realtime_ingest/1,
        max_concurrency: 8,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    # Every single re-ingest is deduplicated by content hash.
    assert Enum.all?(again, &match?({:ok, %{status: :duplicate_ignored}}, &1)),
           "expected every re-ingest to be :duplicate_ignored, got: #{inspect(again)}"

    # The dedup path returns BEFORE do_ingest/4, so the broadcaster never
    # fires: buffer byte-identical, mailbox empty after the drain.
    assert buffer_events() == buffer_before
    refute_receive {:dedup, _, _}
    refute_receive {{:refused, :dedup}, _, _}
  end

  test "malformed envelopes are all refused: typed error, none buffered" do
    collect_telemetry!(self(), :malformed)
    apply(BeamPM.Ingest.Bridge, :reset, [])

    malformed = for _ <- 1..8, do: unique_envelope(include_events?: false)
    m = length(malformed)

    results =
      Task.async_stream(malformed, &realtime_ingest/1,
        max_concurrency: 8,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:error, %Ex4pm.Refusal{code: :missing_envelope_events}}, &1)) == m

    assert buffer_events() == []
    refute_receive {:malformed, _, _}
    refute_receive {{:refused, :malformed}, _, _}
  end

  @tag timeout: 60_000
  test "L5 MAJOR documented behavior: with the evidence store restarted empty, the same envelope broadcasts twice" do
    collect_telemetry!(self(), :store_down)
    apply(BeamPM.Ingest.Bridge, :reset, [])

    envelope = unique_envelope()
    expected_event_id = "ev_soak_#{envelope["sequence"]}"

    assert {:ok, %{status: :ingested}} = realtime_ingest(envelope)
    assert length(drain_telemetry()) == 1
    assert length(buffer_events()) == 1

    # Take the store down through its own supervisor (one_for_one restarts
    # it with EMPTY state -- exactly the "fresh store" condition).
    {:links, links} = Process.info(Process.whereis(Ex4pm.Evidence.Store), :links)

    supervisor =
      Enum.find(links, fn pid ->
        case Process.info(pid, :registered_name) do
          {:registered_name, name} -> name == Ex4pm.Supervisor
          _ -> false
        end
      end)

    assert is_pid(supervisor), "Ex4pm.Supervisor not found among the store's links"

    store_pid = Process.whereis(Ex4pm.Evidence.Store)
    ref = Process.monitor(store_pid)
    :ok = Supervisor.terminate_child(supervisor, Ex4pm.Evidence.Store)

    assert_receive {:DOWN, ^ref, :process, ^store_pid, _reason}, 5_000

    # Measure ONLY the post-restart window: clear the pre-restart copy and
    # its telemetry so the double-broadcast count below is exact.
    apply(BeamPM.Ingest.Bridge, :reset, [])
    _ = drain_telemetry()

    # Store down => dedup finds no receipt => the SAME envelope is treated
    # as fresh and broadcast AGAIN (documented L5 MAJOR gap, measured).
    assert {:ok, %{status: :ingested}} = realtime_ingest(envelope)
    assert {:ok, %{status: :ingested}} = realtime_ingest(envelope)

    ids = Enum.map(buffer_events(), & &1.event_id)

    assert Enum.frequencies(ids)[expected_event_id] == 2,
           "expected the SAME event_id exactly 2x (documented double-broadcast), " <>
             "got: #{inspect(Enum.frequencies(ids))}"

    assert length(drain_telemetry()) == 2

    # Restore the node singleton through the supervisor; the restarted
    # store starts empty, but every envelope in this file carries
    # System.unique_integer content, so no later test can collide with
    # (or depend on) prior dedup state.
    {:ok, _pid} = Supervisor.restart_child(supervisor, Ex4pm.Evidence.Store)
    assert wait_until_alive!(5_000), "store did not come back after restart_child"
  end

  # --- soak harness -----------------------------------------------------------

  defp soak_waves(deadline) do
    soak_waves(deadline, 0, [], 0)
  end

  defp soak_waves(deadline, fresh, event_ids, refused) do
    if System.monotonic_time(:millisecond) >= deadline do
      {fresh, event_ids, refused}
    else
      wave = for _ <- 1..8, do: unique_envelope()
      malformed = unique_envelope(include_events?: false)

      results =
        Task.async_stream(wave, &realtime_ingest/1,
          max_concurrency: 8,
          timeout: 30_000,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert {:error, %Ex4pm.Refusal{code: :missing_envelope_events}} =
               realtime_ingest(malformed)

      fresh_results = Enum.filter(results, &match?({:ok, %{status: :ingested}}, &1))

      assert Enum.count(fresh_results) == 8,
             "every wave envelope must be a fresh ingest: #{inspect(results)}"

      wave_ids = Enum.map(wave, fn env -> "ev_soak_#{env["sequence"]}" end)

      soak_waves(deadline, fresh + 8, event_ids ++ wave_ids, refused + 1)
    end
  end

  defp wait_until_alive!(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_until_alive_loop(deadline)
  end

  defp wait_until_alive_loop(deadline) do
    cond do
      alive_store?() ->
        true

      System.monotonic_time(:millisecond) < deadline ->
        Process.sleep(50)
        wait_until_alive_loop(deadline)

      true ->
        false
    end
  end

  defp alive_store? do
    case Process.whereis(Ex4pm.Evidence.Store) do
      pid when is_pid(pid) -> Process.alive?(pid) and GenServer.whereis(Ex4pm.Evidence.Store) == pid
      _ -> false
    end
  end

  # S1's events/0 currently folds over the whole ETS table including the
  # {seq_key, 0} counter sentinel row; filter to real OcelEvents so these
  # assertions stay correct under either implementation.
  defp buffer_events do
    apply(BeamPM.Ingest.Bridge, :events, [])
    |> Enum.filter(&match?(%BeamPM.Types.OcelEvent{}, &1))
  end

  defp realtime_ingest(envelope) do
    Ex4pm.Stream.Ingest.ingest_envelope(envelope,
      broadcaster: Application.get_env(:ash_ex4pm, :broadcaster)
    )
  end

  defp unique_envelope(opts \\ []) do
    include_events? = Keyword.get(opts, :include_events?, true)
    n = System.unique_integer([:positive])
    object_id = "obj_soak_#{n}"

    base = %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => @producer_agent_id,
        "runtime" => "beam",
        "resource" => "Beam4pmEx4pmSoakCorrectnessTest"
      },
      "sequence" => n,
      "objects" => %{object_id => %{"id" => object_id, "type" => "SoakProof"}},
      "object_relationships" => []
    }

    if include_events? do
      Map.put(base, "events", [
        %{
          "id" => "ev_soak_#{n}",
          "activity" => "soak_proof_#{n}",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "relationships" => [%{"objectId" => object_id, "qualifier" => "primary"}],
          "attributes" => %{}
        }
      ])
    else
      base
    end
  end

  defp collect_telemetry!(test_pid, tag) do
    :ok =
      :telemetry.attach(
        {__MODULE__, tag, :ingested},
        @ingested,
        &__MODULE__.relay/4,
        {test_pid, tag}
      )

    :ok =
      :telemetry.attach(
        {__MODULE__, tag, :refused},
        @refused,
        &__MODULE__.relay/4,
        {test_pid, {:refused, tag}}
      )

    on_exit(fn ->
      :telemetry.detach({__MODULE__, tag, :ingested})
      :telemetry.detach({__MODULE__, tag, :refused})
    end)

    :ok
  end

  @doc false
  def relay(_name, measurements, metadata, {test_pid, tag}) do
    send(test_pid, {tag, measurements, metadata})
  end

  # Non-blocking drain: the broadcaster runs synchronously inside
  # ingest_envelope/2, so every matching telemetry event has already been
  # relayed into this mailbox by the time the triggering ingest returned.
  defp drain_telemetry do
    drain_telemetry([])
  end

  defp drain_telemetry(acc) do
    receive do
      {tag, _, _} = msg when is_atom(tag) -> drain_telemetry([msg | acc])
      _other -> drain_telemetry(acc)
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp drained_telemetry_count(tag) do
    drained = drain_telemetry()
    Enum.count(drained, fn {t, _, _} -> t == tag end)
  end
end
