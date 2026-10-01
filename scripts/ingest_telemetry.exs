# ingest_telemetry.exs -- zero-manual-wiring `:telemetry` -> `ocel_event`
# bridge, VISION-2030's "no manual wiring" ingestion gap (FMEA gap 2) made
# real as a hand-authored capability script, the same pattern as
# scripts/discover_report.exs: this is app orchestration behavior over
# ALREADY-GENERATED capital (`BeamPM.Types.OcelEvent.new/1`,
# `BeamPM.Discovery.traces_from_events/2`), not a new `bpm:RecordType`
# projection -- so it lives under scripts/ (a hand-editable manufacturing
# input per CLAUDE.md's doctrine), never under lib/, and therefore never
# needs a `bpm:HandAuthoredSource` admission or trips
# scripts/gate_authorship_check.sh.
#
# `:telemetry` (hex 1.4.2) is already a transitive dependency (via
# :ash/:reactor/:plug per mix.lock) -- confirmed absent as a direct mix.exs
# line, present transitively, exactly as flagged as a to-verify item in the
# prior Explore-phase report before writing any code.
#
# What this module does, real end to end:
#   1. `BeamPM.Ingest.Bridge.attach/2` calls `:telemetry.attach/4` for one
#      event name, with a caller-supplied mapper (defaults to
#      `default_mapper/2`, which reads OTel/Ash-style measurement/metadata
#      maps -- `:duration_native`, `:system_time_native`, `:resource`,
#      `:action`/`:query`, `:trace_id`/`:span_id` -- into the fields
#      `ocel_event` actually has: event_id, event_type, event_time,
#      attributes).
#   2. Every fired event is buffered in a bounded named `:ets` `:ordered_set`
#      owned by a lazily-started GenServer (oldest-drop cap, O(1) ingest --
#      the buffer lives outside the calling process so a caller crash
#      cannot destroy it) as a real `%BeamPM.Types.OcelEvent{}`
#      struct built via the GENERATED `BeamPM.Types.OcelEvent.new/1`
#      constructor -- never a hand-rolled struct literal, so the
#      constructor's own field-presence validation is exercised on every
#      event.
#   3. `BeamPM.Ingest.Bridge.events/0` returns the buffered list;
#      `BeamPM.Ingest.Bridge.traces/1` feeds it straight into the
#      GENERATED `BeamPM.Discovery.traces_from_events/2` -- so a caller
#      gets real case-centric traces out of raw `:telemetry.execute/3`
#      calls with exactly one `attach/2` line, no endpoint, no auth, no
#      network hop.
#
# Usage (from the repo root; needs `mix deps.get` already run):
#
#     mix run scripts/ingest_telemetry.exs
#
# Running this script directly exercises `default_mapper/2` and the full
# attach -> execute -> buffer -> traces pipeline against real
# `:telemetry.execute/3` calls (no mocked telemetry API -- the real
# `:telemetry` application already loaded by this repo's own deps) and
# prints a real report. `scripts/ingest_telemetry_check.exs` (run via
# `mix run scripts/ingest_telemetry_check.exs`, exit code 0/1) is the
# Chicago-style self-test: real `:telemetry.execute/3` calls, real
# `%BeamPM.Types.OcelEvent{}` structs, real assertions on the returned
# state -- no `Mock`/`patch`/`monkeypatch` equivalent anywhere in either
# file.

defmodule BeamPM.Ingest.Bridge do
  @moduledoc """
  Zero-config `:telemetry` -> `BeamPM.Types.OcelEvent` bridge.

  Hand-authored orchestration over already-generated beam4pm capital
  (`BeamPM.Types.OcelEvent`, `BeamPM.Discovery`) -- not itself a
  `bpm:RecordType` projection, so it is a script, not a `lib/` module.
  """

  # The buffer is a bounded, named, public `:ets` `:ordered_set` owned by a
  # tiny lazily-started GenServer (SOAK-1 blocker fix): the previous
  # `:persistent_term` literal-list buffer was unbounded, O(n) per write
  # (~397us at 2k events), and 20k realtime events crashed the VM
  # (literal_alloc + erl_crash.dump). The table lives OUTSIDE the calling
  # process (owner GenServer + public writers), so a caller crash cannot
  # destroy buffered evidence -- mirroring how `Ex4pm.Evidence.Store`
  # survives. Cap (oldest-drop) comes from
  # `Application.get_env(:beam4pm, :ingest_buffer_cap, 50_000)`.
  @ets :beam4pm_ingest_bridge_buffer
  @owner :beam4pm_ingest_bridge_owner
  @seq_key :ingest_seq
  @default_cap 50_000

  @doc """
  Attaches a `:telemetry` handler for `event_name` (a `[atom()]` telemetry
  event name, e.g. `[:ash, :action, :stop]`). `mapper` receives the real
  `(measurements, metadata)` maps `:telemetry.execute/3` was called with
  and must return a map with the four keys `default_mapper/2` returns
  (`:event_id`, `:event_type`, `:event_time`, `:attributes`) -- exactly the
  keys `BeamPM.Types.OcelEvent.new/1` requires.

  Returns `:ok` (matching `:telemetry.attach/4`'s own success contract) or
  `{:error, :already_exists}` if this exact handler id is already attached.
  """
  @spec attach([atom()], (map(), map() -> map())) :: :ok | {:error, :already_exists}
  def attach(event_name, mapper \\ &__MODULE__.default_mapper/2) when is_list(event_name) do
    reset_buffer_if_absent()
    handler_id = {__MODULE__, event_name}

    :telemetry.attach(
      handler_id,
      event_name,
      &__MODULE__.handle_event/4,
      %{mapper: mapper}
    )
  end

  @doc "Detaches the handler previously attached for `event_name`."
  @spec detach([atom()]) :: :ok | {:error, :not_found}
  def detach(event_name) when is_list(event_name) do
    :telemetry.detach({__MODULE__, event_name})
  end

  @doc """
  Attaches `attach/2`'s default mapper to every event name in `event_names`
  in one call, via `:telemetry.attach_many/4` -- used by
  `BeamPM.Evidence.attach_all/0` (`lib/beam4pm_evidence.ex`) to wire the
  full `[:beam4pm, :engine, engine, op]` family (79 admitted ops) without
  79 separate `attach/2` calls. Returns `{:error, :already_exists}` if this
  exact handler id is already attached (same idempotency contract as
  `attach/2`).
  """
  @spec attach_many([[atom()]], (map(), map() -> map())) :: :ok | {:error, :already_exists}
  def attach_many(event_names, mapper \\ &__MODULE__.default_mapper/2) when is_list(event_names) do
    reset_buffer_if_absent()
    handler_id = {__MODULE__, :many}

    :telemetry.attach_many(
      handler_id,
      event_names,
      &__MODULE__.handle_event/4,
      %{mapper: mapper}
    )
  end

  @doc false
  @spec handle_event([atom()], map(), map(), %{mapper: (map(), map() -> map())}) :: :ok
  def handle_event(_event_name, measurements, metadata, %{mapper: mapper}) do
    mapped = mapper.(measurements, metadata)

    case BeamPM.Types.OcelEvent.new(mapped) do
      {:ok, event} -> ingest(event)
      {:error, reason} -> {:error, reason}
    end

    :ok
  end

  @doc """
  Appends one already-constructed `%BeamPM.Types.OcelEvent{}` to the bounded
  buffer (O(1) -- ets insert + cap trim, oldest dropped when over cap).
  Malformed input (not matching `%BeamPM.Types.OcelEvent{}`) returns a typed
  `{:error, {:invalid_ocel_event, term}}` instead of raising.
  """
  @spec ingest(BeamPM.Types.OcelEvent.t()) :: :ok
  def ingest(%BeamPM.Types.OcelEvent{} = event) do
    ensure_started()

    # The monotonic sequence lives in a counter row in the same table:
    # `:ets.update_counter/4` with an insert-default is atomic under
    # concurrency (a :persistent_term read-modify-write is NOT -- concurrent
    # ingests collided and overwrote rows in the 8-way soak). The row sorts
    # AFTER every integer seq key (atoms > integers in ETS term order), so
    # `:ets.first/1` still returns the oldest event row and every consumer
    # filters the bookkeeping key out.
    seq = :ets.update_counter(@ets, @seq_key, 1, {@seq_key, 0})
    :ets.insert(@ets, {seq, event})

    # +1: the counter row itself counts toward :size. One insert => at most
    # one row over cap; drop the oldest (lowest seq).
    if :ets.info(@ets, :size) > cap() + 1 do
      :ets.delete(@ets, :ets.first(@ets))
    end

    :ok
  end

  def ingest(other), do: {:error, {:invalid_ocel_event, other}}

  @doc "Every buffered event, oldest first (at most the newest `cap` entries)."
  @spec events() :: [BeamPM.Types.OcelEvent.t()]
  def events do
    ensure_started()

    :ets.foldl(
      fn
        {@seq_key, _}, acc -> acc
        {_seq, event}, acc -> [event | acc]
      end,
      [],
      @ets
    )
    |> Enum.reverse()
  end

  @doc "Clears the buffer (used between independent runs/tests)."
  @spec reset() :: :ok
  def reset do
    ensure_started()
    :ets.delete_all_objects(@ets)
    :ets.insert(@ets, {@seq_key, 0})
    :ok
  end

  # --- bounded ets buffer plumbing -------------------------------------------

  defp cap do
    Application.get_env(:beam4pm, :ingest_buffer_cap, @default_cap)
  end

  defp ensure_started do
    case GenServer.whereis(@owner) do
      nil ->
        case GenServer.start(__MODULE__, [], name: @owner) do
          {:ok, _pid} -> :ok

          {:error, {:already_started, pid}} ->
            # we raced the registered server: if OUR init created the table,
            # hand it to the winner so it survives this (losing) process exit
            if :ets.whereis(@ets) != :undefined and :ets.info(@ets, :owner) == self() do
              :ets.give_away(@ets, pid, nil)
            end

            :ok

          {:error, reason} ->
            raise "BeamPM.Ingest.Bridge init failed: #{inspect(reason)}"
        end

      _pid ->
        :ok
    end
  end

  @doc false
  def init(_) do
    tid = ensure_table(50)
    :ets.insert(tid, {@seq_key, 0})
    {:ok, %{cap: cap()}}
  end

  # Race-safe table acquisition. Two concurrent inits can both observe
  # whereis == :undefined; the :ets.new loser adopts the winner's table (or,
  # if the creator died in between, retries). Bounded retries so a hostile
  # environment cannot spin forever.
  defp ensure_table(retries) do
    case :ets.whereis(@ets) do
      tid when tid != :undefined ->
        tid

      :undefined ->
        try do
          # NOTE: :read_concurrency is intentionally absent -- this host's
          # OTP 28.5.0.2 rejects it in :ets.new options ("invalid options");
          # it is a performance hint only, no semantic effect.
          :ets.new(@ets, [
            :ordered_set,
            :named_table,
            :public,
            {:write_concurrency, true}
          ])
        rescue
          ArgumentError ->
            case :ets.whereis(@ets) do
              :undefined when retries > 0 -> ensure_table(retries - 1)
              :undefined -> raise "BeamPM.Ingest.Bridge: cannot create buffer table"
              tid -> tid
            end
        end
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp reset_buffer_if_absent do
    ensure_started()
    :ok
  end

  @doc """
  Feeds every buffered event through the GENERATED
  `BeamPM.Discovery.traces_from_events/2`, grouping by `case_attr_key`
  (the attribute key inside each event's `attributes` map that names the
  case/process instance -- e.g. `"trace_id"`).
  """
  @spec traces(String.t()) :: [BeamPM.Types.LogTrace.t()]
  def traces(case_attr_key) when is_binary(case_attr_key) do
    BeamPM.Discovery.traces_from_events(events(), case_attr_key)
  end

  @doc """
  Default OTel/Ash-shaped mapper: reads the real fields Ash's own
  `:telemetry.execute/3` instrumentation and OTel-style span metadata
  carry (`metadata[:resource]`, `metadata[:action]`/`metadata[:query]`,
  `metadata[:trace_id]`, `metadata[:span_id]`) into the four fields
  `BeamPM.Types.OcelEvent.new/1` requires. Falls back to a generated
  `event_id`/`event_type`/`event_time` when the caller's metadata does not
  carry the expected keys, so `attach/2` never crashes on an unexpected
  telemetry payload shape -- an OCEL event with degraded provenance is
  still emitted, never silently dropped.
  """
  @spec default_mapper(map(), map()) :: map()
  def default_mapper(measurements, metadata) do
    resource = Map.get(metadata, :resource)
    action = Map.get(metadata, :action) || Map.get(metadata, :query)

    event_type =
      cond do
        is_atom(resource) and is_atom(action) -> "#{inspect(resource)}.#{action}"
        is_atom(action) -> to_string(action)
        true -> "telemetry_event"
      end

    trace_id = Map.get(metadata, :trace_id)
    span_id = Map.get(metadata, :span_id)

    event_id =
      case {trace_id, span_id} do
        {t, s} when is_binary(t) and is_binary(s) -> "#{t}:#{s}"
        {t, _} when is_binary(t) -> t
        _ -> "evt_" <> Integer.to_string(System.unique_integer([:positive]))
      end

    event_time =
      case Map.get(measurements, :system_time_native) do
        nil -> DateTime.utc_now() |> DateTime.to_iso8601()
        native -> native |> System.convert_time_unit(:native, :microsecond) |> DateTime.from_unix!(:microsecond) |> DateTime.to_iso8601()
      end

    attrs =
      metadata
      |> Map.take([:trace_id, :span_id, :resource, :action, :query])
      |> Map.new(fn {k, v} -> {to_string(k), if(is_binary(v), do: v, else: inspect(v))} end)
      |> Map.merge(
        case Map.get(measurements, :duration_native) do
          nil -> %{}
          d -> %{"duration_native" => Integer.to_string(d)}
        end
      )

    %{event_id: event_id, event_type: event_type, event_time: event_time, attributes: attrs}
  end
end

if System.get_env("BEAM4PM_INGEST_SKIP_DEMO") != "1" do
  BeamPM.Ingest.Bridge.reset()
  :ok = BeamPM.Ingest.Bridge.attach([:demo, :order, :stop])

  for {case_id, action} <- [{"case-1", :place}, {"case-1", :ship}, {"case-2", :place}] do
    :telemetry.execute(
      [:demo, :order, :stop],
      %{duration_native: 42, system_time_native: System.monotonic_time()},
      %{trace_id: case_id, span_id: "s#{:erlang.unique_integer([:positive])}", action: action}
    )
  end

  events = BeamPM.Ingest.Bridge.events()
  traces = BeamPM.Ingest.Bridge.traces("trace_id")

  IO.puts("== BeamPM.Ingest.Bridge demo ==")
  IO.puts("events ingested: #{length(events)}")
  IO.puts("traces mined:    #{length(traces)}")

  for %BeamPM.Types.LogTrace{case_id: cid, activity_sequence: seq} <- traces do
    IO.puts("  case #{inspect(cid)}: #{inspect(seq)}")
  end

  BeamPM.Ingest.Bridge.detach([:demo, :order, :stop])
end
