# bench/ex4pm_bridge_bench.exs -- realtime OCEL v2 capture-path benchmark
# (lane S4): notifier-shaped envelopes -> `Ex4pm.Stream.Ingest.ingest_envelope/2`
# (broadcaster opts) -> `BeamPM.Evidence.Ex4pmBridge.broadcaster/1`
# (scripts/ex4pm_bridge.exs: EventLog -> %BeamPM.Types.OcelEvent{} mapping +
# telemetry) -> `BeamPM.Ingest.Bridge.ingest/1`.
#
#   MIX_BUILD_ROOT=_build-soak4 MIX_ENV=test mix run --no-start bench/ex4pm_bridge_bench.exs
#
# Real collaborators only (Chicago): real envelope maps, real Ex4pm
# normalization + content hashing, real OcelEvent structs, real :telemetry
# execution, real :persistent_term buffer. No mocks.
#
# Baseline: lane S1's fix (bounded ETS buffer with `ingest_buffer_cap`) has
# already landed on this tree, so no unfixed-vs-fixed A/B is possible here
# (a git-stash A/B is forbidden by lane rules). The audit's figures are
# cited as the historical baseline instead:
#   notes/ex4pm-realtime-audit.md: ~397us/event at 2k buffered events,
#   VM crash at 20k (unbounded :persistent_term literal list).

defmodule Bench4pm.Ex4pmBridgeBench do
  @n_events 12_000
  @n_buffer_samples 2_000

  defp cap, do: Application.get_env(:beam4pm, :ingest_buffer_cap, 50_000)

  def run do
    System.put_env("BEAM4PM_INGEST_SKIP_DEMO", "1")
    System.put_env("BEAM4PM_EX4PM_BRIDGE_SKIP_DEMO", "1")

    {:ok, _} = Application.ensure_all_started(:telemetry)
    {:ok, _} = Ex4pm.Evidence.Store.start_link([])

    load_bridge()

    IO.puts("== ex4pm realtime capture-path bench ==")
    IO.puts("n_events=#{@n_events} buffer_samples=#{@n_buffer_samples} cap=#{cap()}")
    IO.puts("baseline: S1 fix already landed; audit 397us/event @2k cited (no stash A/B per lane rules)")

    mem0 = mem()

    scenario_a()
    scenario_b()
    scenario_c()
    mapping_overhead()
    store_probe()

    IO.puts("\n-- Bridge.ingest scaling (median us/event at fixed buffer depths) --")
    io_header()

    # Flatness check (task 2): 1k vs 10k vs cap on the FIXED bridge. On a
    # regressed/unfixed tree (cost at 10k >> 1k) the cap row is skipped --
    # the audit recorded a VM crash at 20k on the literal-list version.
    {med_1k, p99_1k} = ingest_scaling(BeamPM.Ingest.Bridge, 1_000)
    io_row("fixed bridge", 1_000, med_1k, p99_1k, mem())

    {med_10k, p99_10k} = ingest_scaling(BeamPM.Ingest.Bridge, 10_000)
    io_row("fixed bridge", 10_000, med_10k, p99_10k, mem())

    if med_10k <= 3 * max(med_1k, 1) do
      {med_cap, p99_cap} = ingest_scaling(BeamPM.Ingest.Bridge, cap())
      io_row("fixed bridge", cap(), med_cap, p99_cap, mem())
    else
      IO.puts("  REGRESSED: cost grows 1k->10k -- cap row skipped (audit: VM crash at 20k unfixed)")
    end

    mem1 = mem()
    IO.puts("\n-- memory --")
    IO.puts("start:     #{fmt_mem(mem0)}")
    IO.puts("after all: #{fmt_mem(mem1)}")

    :ok
  end

  ## Loading

  defp load_bridge do
    unless Code.ensure_loaded?(BeamPM.Ingest.Bridge) do
      Code.require_file(Path.expand("scripts/ingest_telemetry.exs", File.cwd!()))
    end

    unless Code.ensure_loaded?(BeamPM.Evidence.Ex4pmBridge) do
      Code.require_file(Path.expand("scripts/ex4pm_bridge.exs", File.cwd!()))
    end

    # DEFECT WORKAROUND (found by this bench, for lane S1 to fix in
    # scripts/ingest_telemetry.exs): ensure_table/1 passes the bare atom
    # `:read_concurrency` to :ets.new/2, which this OTP 28 build (stdlib
    # 7.2) rejects with badarg -- the tuple form {:read_concurrency, true}
    # is accepted. Until S1 fixes it, the buffer table is pre-created here
    # with the tuple form so Bridge.ensure_table/1's :ets.whereis/1 fast
    # path finds it and never calls :ets.new with the invalid option.
    if :ets.whereis(:beam4pm_ingest_bridge_buffer) == :undefined do
      tid =
        :ets.new(:beam4pm_ingest_bridge_buffer, [
          :ordered_set,
          :named_table,
          :public,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      :ets.insert(tid, {:ingest_seq, 0})
    end

    :ok
  end

  ## Scenario harness

  defp timed_samples(n, fun) do
    samples =
      for _i <- 1..n do
        {us, _} = :timer.tc(fun, :microsecond)
        us
      end
      |> Enum.sort()

    pct = fn p -> Enum.at(samples, min(n - 1, trunc(p * n))) end
    {pct.(0.5), pct.(0.99)}
  end

  defp run_scenario(name, fun) do
    BeamPM.Ingest.Bridge.reset()
    for i <- 1..200, do: fun.(envelope(i))
    BeamPM.Ingest.Bridge.reset()

    {med, p99} =
      timed_samples(@n_events, fn ->
        fun.(envelope(:erlang.unique_integer([:positive])))
      end)

    print_row(name, @n_events, med, p99, mem())
  end

  defp ingest_scaling(mod, size) do
    mod.reset()
    for i <- 1..size, do: mod.ingest(scale_event(i))

    samples =
      for i <- (size + 1)..(size + @n_buffer_samples) do
        {us, _} = :timer.tc(fn -> mod.ingest(scale_event(i)) end, :microsecond)
        us
      end
      |> Enum.sort()

    pct = fn p -> Enum.at(samples, min(@n_buffer_samples - 1, trunc(p * @n_buffer_samples))) end
    {pct.(0.5), pct.(0.99)}
  end

  ## Scenarios

  # (a) ingest_envelope alone, no broadcaster. store: nil / miner: nil so the
  # measurement isolates Stream.Ingest from evidence-store growth; the Store's
  # own O(n) dedup scan is probed separately in store_probe/0.
  defp scenario_a do
    IO.puts("\n-- per-event scenarios (median/p99 us, n=#{@n_events}) --")
    run_scenario("a:ingest_envelope_alone", fn env ->
      Ex4pm.Stream.Ingest.ingest_envelope(env, store: nil, miner: nil)
    end)
  end

  defp scenario_b do
    run_scenario("b:noop_broadcaster", fn env ->
      Ex4pm.Stream.Ingest.ingest_envelope(env,
        store: nil,
        miner: nil,
        broadcaster: fn _payload -> :ok end
      )
    end)
  end

  defp scenario_c do
    run_scenario("c:full_path_bridge_broadcaster", fn env ->
      Ex4pm.Stream.Ingest.ingest_envelope(env,
        store: nil,
        miner: nil,
        broadcaster: &BeamPM.Evidence.Ex4pmBridge.broadcaster/1
      )
    end)
  end

  # Task 3: mapping overhead in isolation.
  defp mapping_overhead do
    IO.puts("\n-- mapping overhead (median/p99 us, n=#{@n_events}) --")
    BeamPM.Ingest.Bridge.reset()

    {med_new, p99_new} =
      timed_samples(@n_events, fn ->
        {:ok, _} =
          BeamPM.Types.OcelEvent.new(%{
            event_id: "evt-map-#{:erlang.unique_integer([:positive])}",
            event_type: "order.place",
            event_time: "2026-10-01T00:00:00Z",
            attributes: %{"object_ids" => ["order-1", "customer-1"], "k" => "v"}
          })

        :ok
      end)

    print_row("map:ocel_event_new_only", @n_events, med_new, p99_new, mem())

    log = one_event_log()

    {med_broad, p99_broad} =
      timed_samples(@n_events, fn ->
        payload = %{
          envelope: %{sequence: System.unique_integer([:positive])},
          log: log,
          event_count: 1
        }

        _ = BeamPM.Evidence.Ex4pmBridge.broadcaster(payload)
        :ok
      end)

    IO.puts(
      "  (broadcaster 1-event ~= mapping + telemetry + Bridge.ingest-at-tiny-buffer; " <>
        "subtract the Bridge.ingest median at ~1k for a mapping-only estimate)"
    )

    print_row("map:broadcaster_1event", @n_events, med_broad, p99_broad, mem())
    :ok
  end

  # Probe: the real Ex4pm.Evidence.Store dedup scan (get_by_subject/1 is
  # :ets.tab2list() + filter == O(store size) per ingest_envelope call). 2_000
  # unique envelopes against the real Store GenServer.
  defp store_probe do
    IO.puts("\n-- probe: ingest_envelope vs real Ex4pm.Evidence.Store --")

    {med, p99} =
      timed_samples(2_000, fn ->
        env = envelope(:erlang.unique_integer([:positive]))
        {:ok, _} = Ex4pm.Stream.Ingest.ingest_envelope(env, miner: nil)
        :ok
      end)

    print_row("probe:real_store_dedup", 2_000, med, p99, mem())
    receipts = Ex4pm.Evidence.Store.all()

    IO.puts(
      "  (Store receipts at probe end: #{length(receipts)}; " <>
        "get_by_subject/1 is a tab2list+filter, cost grows with this count)"
    )
  end

  ## Fixtures

  defp envelope(i) do
    %{
      "schema" => "ocel.v2",
      "producer" => %{"agent_id" => "bench", "run_id" => "bench-run"},
      "sequence" => i,
      "events" => [
        %{
          "id" => "evt-bench-#{i}",
          "activity" => "order.place",
          "timestamp" => "2026-10-01T00:00:0" <> Integer.to_string(rem(i, 10)) <> "Z",
          "attributes" => %{"k" => "v"}
        }
      ],
      "objects" => %{"order-1" => %{"type" => "order"}},
      "object_relationships" => []
    }
  end

  defp scale_event(i) do
    {:ok, e} =
      BeamPM.Types.OcelEvent.new(%{
        event_id: "evt-scale-#{i}",
        event_type: "order.place",
        event_time: "2026-10-01T00:00:00Z",
        attributes: %{"object_ids" => ["order-1"], "k" => "v"}
      })

    e
  end

  defp one_event_log do
    events = [
      %Ex4pm.Event{
        id: "evt-map",
        activity: "order.place",
        timestamp: ~U[2026-10-01 00:00:00Z],
        object_ids: ["order-1", "customer-1"]
      }
    ]

    objects = [
      %Ex4pm.ObjectRef{id: "order-1", type: "order"},
      %Ex4pm.ObjectRef{id: "customer-1", type: "customer"}
    ]

    normalized = %{events: events, objects: objects, object_relationships: []}

    %Ex4pm.EventLog{
      events: events,
      objects: objects,
      object_relationships: [],
      subject: Ex4pm.Subject.new(:event_log, normalized)
    }
  end

  ## Output

  defp print_row(name, n, med, p99, mem) do
    IO.puts(
      :io_lib.format("  ~-38s n=~6w  median=~8w us  p99=~8w us  ~s", [
        name,
        n,
        med,
        p99,
        fmt_mem(mem)
      ])
    )
  end

  defp io_header, do: IO.puts("  scenario                buffer   median_us   p99_us   memory")

  defp io_row(label, size, med, p99, mem) do
    IO.puts(:io_lib.format("  ~-12s @ ~7w      ~7w   ~7w   ~s", [label, size, med, p99, fmt_mem(mem)]))
  end

  defp fmt_mem({procs, ets, pt_words}) do
    "procs=#{div(procs, 1024)}KiB ets=#{div(ets, 1024)}KiB pt=#{div(pt_words * 8, 1024)}KiB"
  end

  defp mem do
    pt_words = :persistent_term.info().memory
    {:erlang.memory(:processes), :erlang.memory(:ets), pt_words}
  end
end

Bench4pm.Ex4pmBridgeBench.run()
