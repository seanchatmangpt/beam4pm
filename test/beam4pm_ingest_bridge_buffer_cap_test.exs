# beam4pm_ingest_bridge_buffer_cap_test.exs -- SOAK-1 blocker regression
# qualification for the bounded `BeamPM.Ingest.Bridge` buffer
# (scripts/ingest_telemetry.exs). The previous `:persistent_term`
# literal-list buffer was unbounded and O(n) per write (~397us at 2k
# events); 20k realtime events crashed the VM (literal_alloc +
# erl_crash.dump). This court runs the REAL bridge (the real script-defined
# module, real ets table, real GenServer owner -- no mocks) against the
# exact failure shape that crashed the VM: a 60k-event soak.

defmodule Beam4pmIngestBridgeBufferCapTest do
  use ExUnit.Case, async: false

  @cap_keyword :ingest_buffer_cap

  defp bridge_reset, do: apply(BeamPM.Ingest.Bridge, :reset, [])
  defp bridge_events, do: apply(BeamPM.Ingest.Bridge, :events, [])

  defp event(i) do
    {:ok, ev} =
      BeamPM.Types.OcelEvent.new(%{
        event_id: "evt_cap_#{i}",
        event_type: "cap_test",
        event_time: DateTime.to_iso8601(DateTime.utc_now()),
        attributes: %{"trace_id" => "case_cap_#{rem(i, 100)}"}
      })

    ev
  end

  defp ingest(i) do
    apply(BeamPM.Ingest.Bridge, :ingest, [event(i)])
  end

  setup do
    # --no-start run: the real beam4pm app (with its Bandit listeners on
    # fixed ports 4210/4211, held on this host by an unrelated long-lived
    # VM) is NOT started; the bridge's real collaborators here are pure
    # modules (:telemetry, BeamPM.Types, BeamPM.Discovery) plus the
    # script-defined module itself.
    {:ok, _} = Application.ensure_all_started(:telemetry)
    System.put_env("BEAM4PM_INGEST_SKIP_DEMO", "1")
    Code.require_file("scripts/ingest_telemetry.exs", File.cwd!())
    assert :ok = BeamPM.Evidence.ensure_ingest_bridge_loaded()
    assert :ok = bridge_reset()
    :ok
  end

  @tag :soak
  test "60k ingests complete without crash and process memory stays bounded" do
    pre = :erlang.memory(:processes)

    assert :ok == Enum.each(1..60_000, &ingest/1)

    post = :erlang.memory(:processes)

    # 60k OcelEvents each ~ a few hundred bytes; bounded buffer must keep
    # the delta far below what 60k retained events would cost (delta may be
    # negative -- GC may reclaim more than the soak allocates).
    delta = post - pre
    assert delta < 40_000_000, "process memory grew by #{delta} bytes"

    # Buffer actually capped at the default 50k.
    assert length(bridge_events()) == 50_000
  end

  @tag :soak
  test "events/0 returns exactly the newest cap entries in insertion order" do
    small = 1_000
    Application.put_env(:beam4pm, @cap_keyword, small)

    try do
      for i <- 1..(small + 250), do: ingest(i)

      events = bridge_events()
      assert length(events) == small

      ids = Enum.map(events, & &1.event_id)
      first_kept = small + 250 - small + 1

      assert ids == Enum.map(first_kept..(small + 250)//1, &"evt_cap_#{&1}")
    after
      Application.delete_env(:beam4pm, @cap_keyword)
    end
  end

  test "reset/0 clears the buffer" do
    for i <- 1..10, do: ingest(i)
    assert length(bridge_events()) == 10
    assert :ok = bridge_reset()
    assert bridge_events() == []
  end

  test "malformed input returns a typed error instead of raising" do
    assert {:error, {:invalid_ocel_event, :nope}} =
             apply(BeamPM.Ingest.Bridge, :ingest, [:nope])

    assert {:error, {:invalid_ocel_event, %MapSet{}}} =
             apply(BeamPM.Ingest.Bridge, :ingest, [MapSet.new()])

    # buffer untouched by the refused input
    assert bridge_events() == []
  end

  @tag :soak
  test "ingest cost stays flat: last-10k mean within 3x of first-10k mean" do
    n = 60_000

    {first_sum, _, last_sum, _} =
      Enum.reduce(1..n, {0, 0, 0, 0}, fn i, {f_sum, f_n, l_sum, l_n} ->
        {us, :ok} = :timer.tc(fn -> ingest(i) end)

        cond do
          i <= 10_000 -> {f_sum + us, f_n + 1, l_sum, l_n}
          i > n - 10_000 -> {f_sum, f_n, l_sum + us, l_n + 1}
          true -> {f_sum, f_n, l_sum, l_n}
        end
      end)

    first_mean = first_sum / 10_000
    last_mean = last_sum / 10_000

    assert last_mean < 3 * first_mean,
           "ingest cost grew: first-10k mean #{first_mean}us, last-10k mean #{last_mean}us"
  end
end
