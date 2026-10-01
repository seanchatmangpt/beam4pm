# ex4pm_soak.exs -- 5-minute soak harness over the REAL realtime ex4pm path:
#
#   notifier-shaped envelope
#     -> Ex4pm.Stream.Ingest.ingest_envelope/2 (broadcaster from app env)
#     -> BeamPM.Evidence.Ex4pmBridge.broadcaster/1
#     -> BeamPM.Ingest.Bridge.ingest/1
#     -> [:beam4pm, :ex4pm, :envelope, :ingested] telemetry
#
# Lane S2. Run from ~/beam4pm:
#
#     MIX_BUILD_ROOT=_build-soak2 mix run scripts/ex4pm_soak.exs
#
# Env knobs: SOAK_SECONDS (default 300), SOAK_RATE (default 50/s),
# SOAK_CONCURRENCY (default 8). Writes notes/ex4pm-soak-<unix-ts>.md and
# prints one SOAK SUMMARY line. Exits non-zero if the store is down or a
# NEW erl_crash.dump appeared in cwd during the run.

defmodule BeamPM.Soak.Ex4pmSoak do
  @moduledoc false

  @producer_agent_id "ex4pm_soak"

  def main do
    start_mono = System.monotonic_time(:millisecond)
    seconds = env_int("SOAK_SECONDS", 300)
    rate = env_int("SOAK_RATE", 50)
    concurrency = env_int("SOAK_CONCURRENCY", 8)

    # ---- boot prerequisites ----
    System.put_env("BEAM4PM_INGEST_SKIP_DEMO", "1")
    System.put_env("BEAM4PM_EX4PM_BRIDGE_SKIP_DEMO", "1")

    # Boot-tolerant mode: under `mix run --no-start` (used when a sibling
    # lane's VM already holds beam4pm's default Bandit ports), pick free
    # ports and start :beam4pm (which starts :ex4pm's store) here.
    if is_nil(Process.whereis(Ex4pm.Evidence.Store)) do
      Application.put_env(:beam4pm, :ocel_ingest_port, free_port())
      Application.put_env(:beam4pm, :a2a_port, free_port())
      {:ok, _} = Application.ensure_all_started(:beam4pm)
    end

    Code.require_file(Path.join([File.cwd!(), "scripts", "ingest_telemetry.exs"]))
    Code.require_file(Path.join([File.cwd!(), "scripts", "ex4pm_bridge.exs"]))
    :ok = BeamPM.Evidence.Ex4pmBridge.ensure_loaded()

    previous = BeamPM.Evidence.Ex4pmBridge.attach()

    broadcaster = Application.get_env(:ash_ex4pm, :broadcaster)
    unless is_function(broadcaster, 1) do
      IO.puts(:stderr, "SOAK FATAL: no broadcaster registered under :ash_ex4pm app env")
      System.halt(2)
    end

    unless is_pid(Process.whereis(Ex4pm.Evidence.Store)) and
             Process.alive?(Process.whereis(Ex4pm.Evidence.Store)) do
      IO.puts(:stderr, "SOAK FATAL: Ex4pm.Evidence.Store is not registered/alive")
      System.halt(2)
    end

    IO.puts("broadcaster attached, Ex4pm.Evidence.Store alive: #{inspect(Process.whereis(Ex4pm.Evidence.Store))}")

    # baseline crash-dump fingerprint
    dump_path = Path.join(File.cwd!(), "erl_crash.dump")
    baseline_dump = dump_fingerprint(dump_path)

    # ---- telemetry counters ----
    counters = :counters.new(4, [:write_concurrency])
    # 1 ingested envelope events, 2 refused, 3 buffer-cap firings
    :ok =
      :telemetry.attach(
        {__MODULE__, :ingested},
        [:beam4pm, :ex4pm, :envelope, :ingested],
        fn _n, m, _meta, _ -> :counters.add(counters, 1, Map.get(m, :event_count, 1)) end,
        nil
      )

    :ok =
      :telemetry.attach(
        {__MODULE__, :refused},
        [:beam4pm, :ex4pm, :envelope, :refused],
        fn _n, m, _meta, _ -> :counters.add(counters, 2, Map.get(m, :event_count, 1)) end,
        nil
      )

    :ok =
      :telemetry.attach(
        {__MODULE__, :buffer_cap},
        [:beam4pm, :ingest, :buffer, :cap],
        fn _n, _m, _meta, _ -> :counters.add(counters, 3, 1) end,
        nil
      )

    # ---- soak loop ----
    totals = %{fresh: 0, dup: 0, refused: 0, other: 0}
    samples = []
    total_sent = 0
    peak_total_mem = 0

    {totals, samples, total_sent, peak_total_mem, elapsed_ms} =
      soak_loop(seconds, rate, concurrency, totals, samples, total_sent, peak_total_mem, start_mono)

    # ---- final ----
    final_mem = :erlang.memory(:total)
    final_dump = dump_fingerprint(dump_path)
    crash? = final_dump != baseline_dump and final_dump != nil

    final_fresh = :counters.get(counters, 1)
    final_refused = :counters.get(counters, 2)
    cap_fired = :counters.get(counters, 3)

    :telemetry.detach({__MODULE__, :ingested})
    :telemetry.detach({__MODULE__, :refused})
    :telemetry.detach({__MODULE__, :buffer_cap})
    Application.put_env(:ash_ex4pm, :broadcaster, previous)

    write_report(%{
      seconds: seconds,
      rate: rate,
      concurrency: concurrency,
      totals: totals,
      total_sent: total_sent,
      peak_total_mem: peak_total_mem,
      final_mem: final_mem,
      elapsed_ms: elapsed_ms,
      final_fresh: final_fresh,
      final_refused: final_refused,
      cap_fired: cap_fired,
      samples: Enum.reverse(samples),
      crash: crash?,
      dump_fingerprint: final_dump
    })

    status = cond do
      crash? -> "CRASH-DUMP"
      totals.refused > 0 -> "REFUSALS"
      true -> "OK"
    end

    IO.puts(
      "SOAK SUMMARY: status=#{status} sent=#{total_sent} fresh=#{totals.fresh} " <>
        "dup=#{totals.dup} refused=#{totals.refused} elapsed_ms=#{elapsed_ms} " <>
        "rate_actual=#{Float.round(total_sent / (elapsed_ms / 1000), 2)}/s " <>
        "peak_mem_mb=#{div(peak_total_mem, 1024 * 1024)} final_mem_mb=#{div(final_mem, 1024 * 1024)} " <>
        "buffer_cap_fired=#{cap_fired} crash_dump=#{crash?}"
    )

    if crash?, do: System.halt(3)
  end

  defp soak_loop(seconds, rate, concurrency, totals, samples, total_sent, peak, start_mono) do
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    # SOAK_RATE envelopes PER SECOND: fire one batch of `rate` each second,
    # sample every 10 ticks (10s cadence).
    ticks = seconds
    do_ticks(deadline, ticks, rate, concurrency, totals, samples, total_sent, peak, start_mono, 0)
  end

  defp do_ticks(deadline, 0, _rate, _c, totals, samples, total_sent, peak, start_mono, _n) do
    {totals, samples, total_sent, peak, System.monotonic_time(:millisecond) - start_mono}
  end

  defp do_ticks(deadline, ticks_left, rate, concurrency, totals, samples, total_sent, peak, start_mono, n) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {totals, samples, total_sent, peak, now - start_mono}
    else
      {new_totals, sent, fresh, dup, refused, other, _results} =
        fire_batch(rate, concurrency, totals)

      tick_end = System.monotonic_time(:millisecond) + 1000
      drift = tick_end - System.monotonic_time(:millisecond)
      if drift > 0, do: Process.sleep(drift)

      if rem(n + 1, 10) == 0 do
        {ing, pt_words} = ets_words()
        mem = :erlang.memory(:total)
        peak = max(peak, mem)
        buf_len = bridge_buffer_length()

        sample = %{
          t_ms: System.monotonic_time(:millisecond) - start_mono,
          sent: sent,
          fresh: fresh,
          dup: dup,
          refused: refused,
          other: other,
          mem_total: mem,
          store_words: ing,
          persistent_term_words: pt_words,
          buf_len: buf_len
        }

        do_ticks(deadline, ticks_left - 1, rate, concurrency, new_totals, [sample | samples],
          total_sent + sent, peak, start_mono, n + 1)
      else
        do_ticks(deadline, ticks_left - 1, rate, concurrency, new_totals, samples,
          total_sent + sent, peak, start_mono, n + 1)
      end
    end
  end

  defp fire_batch(rate, concurrency, totals) do
    envelopes = Enum.map(1..rate, fn _ -> unique_envelope() end)

    results =
      envelopes
      |> Task.async_stream(
        fn env ->
          case Ex4pm.Stream.Ingest.ingest_envelope(env, broadcaster_opts()) do
            {:ok, %{status: status}} -> status
            {:error, %Ex4pm.Refusal{}} -> :refused
            {:error, other} -> {:error, other}
          end
        end,
        max_concurrency: concurrency,
        timeout: 60_000
      )
      |> Enum.to_list()

    statuses =
      results
      |> Enum.map(fn
        {:ok, s} -> s
        {:exit, reason} -> {:exit, reason}
      end)

    fresh = Enum.count(statuses, &(&1 == :ingested))
    dup = Enum.count(statuses, &(&1 == :duplicate_ignored))
    refused = Enum.count(statuses, &(&1 == :refused))
    other = length(statuses) - fresh - dup - refused

    new_totals = %{
      totals
      | fresh: totals.fresh + fresh,
        dup: totals.dup + dup,
        refused: totals.refused + refused,
        other: totals.other + other
    }

    {new_totals, length(statuses), fresh, dup, refused, other, statuses}
  end

  defp broadcaster_opts do
    case Application.get_env(:ash_ex4pm, :broadcaster) do
      nil -> []
      fun when is_function(fun, 1) -> [broadcaster: fun]

      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        [broadcaster: fn payload -> apply(mod, fun, args ++ [payload]) end]
    end
  end

  # One notifier-shaped envelope (AshEx4pm.Notifier.build_envelope/2 wire
  # shape, test/beam4pm_ex4pm_runtime_test.exs unique_envelope/1 template)
  # with run-unique content.
  defp unique_envelope do
    n = System.unique_integer([:positive])
    object_id = "obj_soak_#{n}"

    %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => @producer_agent_id,
        "runtime" => "beam",
        "resource" => "BeamPM.Soak.Ex4pmSoak"
      },
      "sequence" => n,
      "objects" => %{object_id => %{"id" => object_id, "type" => "SoakProof"}},
      "object_relationships" => [],
      "events" => [
        %{
          "id" => "ev_soak_#{n}",
          "activity" => "soak_proof_#{n}",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "relationships" => [%{"objectId" => object_id, "qualifier" => "primary"}],
          "attributes" => %{}
        }
      ]
    }
  end

  # ETS word size for the store's table (Ex4pm.Evidence.Store names its own
  # table via @table __MODULE__) + the :persistent_term subsystem total (the
  # bridge buffer lives there, per scripts/ingest_telemetry.exs).
  defp ets_words do
    ing = table_words(Ex4pm.Evidence.Store)
    pt_words = :persistent_term.info()[:memory] || 0
    {ing, pt_words}
  end

  defp table_words(name) when is_atom(name) do
    case :ets.info(name, :word_size) do
      :undefined -> 0
      n -> n
    end
  end

  defp bridge_buffer_length do
    # The bridge buffer is :persistent_term (ingest_telemetry.exs), not ETS.
    try do
      length(BeamPM.Ingest.Bridge.events())
    rescue
      _ -> -1
    catch
      _, _ -> -1
    end
  end

  defp dump_fingerprint(nil), do: nil

  defp dump_fingerprint(path) do
    case File.stat(path) do
      {:ok, %{size: size, mtime: mtime}} -> {size, mtime}
      {:error, _} -> nil
    end
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      s ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> default
        end
    end
  end

  defp free_port do
    {:ok, sock} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(sock)
    :gen_tcp.close(sock)
    port
  end

  # ---- report ----
  defp write_report(a) do
    ts = System.system_time(:second)
    path = Path.join([File.cwd!(), "notes", "ex4pm-soak-#{ts}.md"])

    header = """
    # ex4pm soak run — #{DateTime.utc_now() |> DateTime.to_iso8601()}

    Config: SOAK_SECONDS=#{a.seconds} SOAK_RATE=#{a.rate}/s SOAK_CONCURRENCY=#{a.concurrency}

    ## Samples (10s cadence, one row per interval)

    | t_ms | sent | fresh | dup | refused | other | mem_total | store_ets_words | persistent_term_words | bridge_buf_len |
    |---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
    """

    rows =
      a.samples
      |> Enum.map(fn s ->
        "| #{s.t_ms} | #{s.sent} | #{s.fresh} | #{s.dup} | #{s.refused} | #{s.other} | #{s.mem_total} | #{s.store_words} | #{s.persistent_term_words} | #{s.buf_len} |"
      end)
      |> Enum.join("\n")

    summary = """

    ## Final summary

    - total sent: #{a.total_sent}
    - fresh ingested: #{a.totals.fresh} (telemetry ingest_count: #{a.final_fresh})
    - duplicate_ignored: #{a.totals.dup}
    - refused: #{a.totals.refused} (telemetry refused_count: #{a.final_refused})
    - other/errors: #{a.totals.other}
    - elapsed_ms: #{a.elapsed_ms}
    - peak total memory: #{a.peak_total_mem} bytes (#{div(a.peak_total_mem, 1024 * 1024)} MB)
    - final total memory: #{a.final_mem} bytes (#{div(a.final_mem, 1024 * 1024)} MB)
    - ingest_buffer_cap telemetry firings: #{a.cap_fired}
    - NEW erl_crash.dump in cwd: #{a.crash}
    - crash dump fingerprint at end: #{inspect(a.dump_fingerprint)}
    """

    File.mkdir_p(Path.dirname(path))
    File.write!(path, header <> rows <> summary)
    IO.puts("report: #{path}")
  end
end

BeamPM.Soak.Ex4pmSoak.main()
