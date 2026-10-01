defmodule Beam4pmEx4pmRealtimeBridgeTest do
  @moduledoc """
  Chicago-style qualification of the REALTIME ex4pm -> beam4pm push seam:
  a broadcaster fun handed to `Ex4pm.Stream.Ingest.ingest_envelope/2` (the
  `Application.get_env(:ash_ex4pm, :broadcaster)` value `AshEx4pm.Notifier`
  forwards, deps/ash_ex4pm/lib/ash_ex4pm/notifier.ex:153) fires ONLY on a
  fresh ingest, and `BeamPM.Evidence.Ex4pmBridge` maps that firing into real
  `%BeamPM.Types.OcelEvent{}` structs buffered by `BeamPM.Ingest.Bridge`
  plus a real `[:beam4pm, :ex4pm, :envelope, :ingested]` telemetry event.

  Every collaborator is real: the real `Ex4pm.Evidence.Store` GenServer
  (node singleton -- `async: false`), the real ingest engine
  (deps/ex4pm/lib/ex4pm/stream/ingest.ex:19-39), the real script-defined
  `BeamPM.Evidence.Ex4pmBridge` (scripts/ex4pm_bridge.exs) and
  `BeamPM.Ingest.Bridge` (scripts/ingest_telemetry.exs, loaded via
  `BeamPM.Evidence.ensure_ingest_bridge_loaded/0`), and the real `:telemetry`
  application -- no mocks, no polling sleeps: delivery of the telemetry
  event is asserted with `assert_receive` against the test process's own
  mailbox.

  The test calls `ingest_envelope/2` exactly the way the upstream notifier
  does, reading the broadcaster from application env:

      Ex4pm.Stream.Ingest.ingest_envelope(envelope,
        broadcaster: Application.get_env(:ash_ex4pm, :broadcaster)
      )

  Note on the refused telemetry: `[:beam4pm, :ex4pm, :envelope, :refused]`
  (scripts/ex4pm_bridge.exs:111-115) fires only when the BRIDGE itself
  refuses an event (OcelEvent.new/1 or Bridge.ingest/1 failing inside
  broadcaster/1) -- an upstream envelope REFUSAL happens before the
  broadcaster is ever called (ingest.ex:24-26 with-guards; the broadcaster
  call at ingest.ex:128-140 sits inside do_ingest/4's success path only),
  so a refused envelope can neither reach the bridge nor fire any telemetry.
  The refusal test below asserts exactly that contract: typed
  `{:error, %Ex4pm.Refusal{}}`, buffer unchanged, and NO telemetry of
  either family.
  """

  use ExUnit.Case, async: false

  # The two bridge collaborators are script-defined (scripts/), not compiled
  # lib/ modules, so they are referenced with apply/3 (no compile-time alias
  # warning) and required in setup before any use.
  defp bridge_reset, do: apply(BeamPM.Ingest.Bridge, :reset, [])
  defp bridge_events, do: apply(BeamPM.Ingest.Bridge, :events, [])
  defp bridge_attach, do: apply(BeamPM.Evidence.Ex4pmBridge, :attach, [])

  @ingested [:beam4pm, :ex4pm, :envelope, :ingested]
  @refused [:beam4pm, :ex4pm, :envelope, :refused]
  @producer_agent_id "beam4pm_ex4pm_realtime_bridge_test"

  defp unique_envelope(opts \\ []) do
    include_events? = Keyword.get(opts, :include_events?, true)
    n = System.unique_integer([:positive])
    object_id = "obj_rt_bridge_#{n}"

    base = %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => @producer_agent_id,
        "runtime" => "beam",
        "resource" => "Beam4pmEx4pmRealtimeBridgeTest"
      },
      "sequence" => n,
      "objects" => %{object_id => %{"id" => object_id, "type" => "RealtimeProof"}},
      "object_relationships" => []
    }

    if include_events? do
      Map.put(base, "events", [
        %{
          "id" => "ev_rt_bridge_#{n}",
          "activity" => "realtime_bridge_proof_#{n}",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "relationships" => [%{"objectId" => object_id, "qualifier" => "primary"}],
          "attributes" => %{}
        }
      ])
    else
      base
    end
  end

  # Exactly the call the upstream notifier makes (notifier.ex:153 plus the
  # env-read broadcaster the realtime seam defines).
  defp realtime_ingest(envelope) do
    Ex4pm.Stream.Ingest.ingest_envelope(envelope,
      broadcaster: Application.get_env(:ash_ex4pm, :broadcaster)
    )
  end

  # Real :telemetry handler: forwards every matching event into the test
  # process's mailbox. No sleeps anywhere -- assert_receive/refute_receive
  # wait on real asynchronous delivery. Tags are per-test so concurrent
  # attaching/detaching never collides.
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

  setup do
    # Load the two script-defined collaborators. The bridge script's demo
    # block must not run inside the test VM (it would attach telemetry and
    # mutate the shared buffer): guard it off before the first require.
    System.put_env("BEAM4PM_EX4PM_BRIDGE_SKIP_DEMO", "1")

    Code.require_file("scripts/ingest_telemetry.exs", File.cwd!())
    Code.require_file("scripts/ex4pm_bridge.exs", File.cwd!())

    assert :ok = BeamPM.Evidence.ensure_ingest_bridge_loaded()
    assert :ok = apply(BeamPM.Evidence.Ex4pmBridge, :ensure_loaded, [])

    previous = bridge_attach()
    bridge_reset()

    on_exit(fn ->
      Application.put_env(:ash_ex4pm, :broadcaster, previous)
    end)

    :ok
  end

  test "a fresh ingest pushes OcelEvents into the bridge buffer and delivers the ingested telemetry without polling" do
    collect_telemetry!(self(), :positive)
    envelope = unique_envelope()
    n = envelope["sequence"]

    assert {:ok,
            %{
              status: :ingested,
              subject_hash: subject_hash,
              event_count: 1,
              sequence: ^n
            }} = realtime_ingest(envelope)

    # Synchronous push: the broadcaster runs inside ingest_envelope's own
    # call stack (ingest.ex:128-140), so by the time it returns the events
    # are already in the bridge buffer.
    assert [%BeamPM.Types.OcelEvent{} = pushed] = bridge_events()
    assert pushed.event_id == "ev_rt_bridge_#{n}"
    assert pushed.event_type == "realtime_bridge_proof_#{n}"
    assert is_binary(subject_hash)
    assert pushed.attributes["object_ids"] == ["obj_rt_bridge_#{n}"]

    # Real delivered telemetry, received from the mailbox -- never a sleep.
    assert_receive {:positive, %{event_count: 1},
                    %{subject_hash: ^subject_hash, event_ids: ["ev_rt_bridge_" <> _]}}
  end

  test "a duplicate ingest returns :duplicate_ignored, fires no broadcaster, and leaves the buffer untouched" do
    collect_telemetry!(self(), :duplicate)
    envelope = unique_envelope()

    assert {:ok, %{status: :ingested}} = realtime_ingest(envelope)
    assert_receive {:duplicate, _, _}

    assert [%BeamPM.Types.OcelEvent{} = first] = bridge_events()

    assert {:ok,
            %{
              status: :duplicate_ignored,
              subject_hash: subject_hash,
              original_receipt_hash: original_receipt_hash
            }} = realtime_ingest(envelope)

    # The dedup path (ingest.ex:63-86) returns before do_ingest/4, so the
    # broadcaster never fires a second time: no new telemetry, buffer
    # byte-identical.
    refute_receive {:duplicate, _, _}
    assert bridge_events() == [first]
    assert is_binary(original_receipt_hash)
    assert is_binary(subject_hash)
  end

  test "a refused envelope is typed {:error, %Ex4pm.Refusal{}}, adds no OcelEvents, and fires no telemetry" do
    collect_telemetry!(self(), :refusal)
    envelope = unique_envelope(include_events?: false)

    assert {:error, %Ex4pm.Refusal{} = refusal} = realtime_ingest(envelope)
    assert refusal.code == :missing_envelope_events

    # Refusal happens in validate_envelope, before the broadcaster exists
    # in the flow: buffer untouched, neither telemetry family fired.
    assert bridge_events() == []
    refute_receive {:refusal, _, _}
    refute_receive {{:refused, :refusal}, _, _}
  end
end
