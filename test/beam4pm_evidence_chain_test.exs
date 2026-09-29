defmodule BeamPM.EvidenceChainTest do
  @moduledoc """
  Chicago-style, generalized end-to-end qualification of the OCEL
  evidence-contract chain wired in `lib/beam4pm_evidence.ex` (Phases 1-5 of
  this session's plan): a real `[:beam4pm, :engine, engine, op]`
  `:telemetry.execute/3` call, already emitted by every generated engine
  facade op, must produce THREE real, independently-checkable pieces of
  evidence, not a description of them:

    1. a real `%BeamPM.Types.OcelEvent{}` buffered in
       `BeamPM.Ingest.Bridge.events/0` (OCEL identity),
    2. a real OpenTelemetry span exported to this test process via the
       real `otel_exporter_pid` test exporter (swapped onto the running
       `:otel_batch_processor` for the duration of each test, then
       restored -- the same pattern verified working in this session's
       xaas work: real SDK, real message-based capture, no mock),
    3. a real, hash-chained `beam4pm-brce/v1` receipt on disk, verified by
       `BeamPM.ReceiptChain.verify/2` replaying the actual chain.

  ## Scope of this pass (Phase 6)

  One safely-invokable, no-external-fixture-or-tiny-fixture representative
  op per engine (4 total: petgraph, tract, rust4pm, ferroplan) plus one
  deliberate refusal-path case (`Rust4PM.import_xes("not xml")`, mirroring
  the real parse-failure case already exercised in
  `test/beam4pm_rust4pm_test.exs`'s T7). The harness itself
  (`assert_full_evidence_chain!/4`) is written to run against ANY
  `{engine, op}` pair given a thunk that performs the real call -- rolling
  it out against the remaining ops (up to all 79 admitted `bpm:EngineOp`
  facts) is Phase 16's separate follow-up, NOT claimed as done by this
  file. This file exercises 5 real invocations for real, not 79.

  A missing wasm artifact for any one engine is a NAMED SKIP for that
  engine's `describe` block, mirroring `beam4pm_petgraph_test.exs` /
  `beam4pm_tract_test.exs` / `beam4pm_rust4pm_test.exs` /
  `beam4pm_ferroplan_test.exs`'s own established `wasm_built?` pattern --
  never a silent pass.
  """

  use ExUnit.Case, async: false

  # `BeamPM.Ingest.Bridge` is defined in `scripts/ingest_telemetry.exs`
  # (loaded dynamically at runtime by `BeamPM.Evidence.
  # ensure_ingest_bridge_loaded/0`, not compiled into `lib/`) -- silencing
  # the undefined-at-compile-time warning here mirrors how
  # `lib/beam4pm_evidence.ex` itself calls it (`apply/3`, see its own
  # comment), since this is a real, deliberate dynamic-load pattern, not
  # an accidental missing dependency.
  @compile {:no_warn_undefined, BeamPM.Ingest.Bridge}

  alias BeamPM.{Petgraph, Tract, Rust4PM, Ferroplan, ReceiptChain}

  @linear_model Path.expand("qualification/fixtures/tract/linear_2x_plus_1.onnx")

  setup_all do
    # `mix test` does not actually boot BeamPM.Application in this repo's
    # test environment (confirmed: no Bandit listener log line appears
    # during a real `mix test` run of this file, unlike `mix run`), so
    # `BeamPM.Evidence.attach_all/0` is called here explicitly rather than
    # assumed to have already run at application boot. It is idempotent
    # (`:telemetry.attach_many/4`'s `{:error, :already_exists}` is
    # normalized to `:ok`), so this is safe to call even if the app WAS
    # already started elsewhere in the same VM.
    {:ok, _} = Application.ensure_all_started(:telemetry)
    {:ok, _} = Application.ensure_all_started(:opentelemetry_api)
    {:ok, _} = Application.ensure_all_started(:opentelemetry)
    {:ok, _} = Application.ensure_all_started(:beam4pm)
    :ok = BeamPM.Evidence.attach_all()
    :ok
  end

  setup do
    # This setup (a) resets the OCEL
    # buffer so each test sees only its own events, (b) swaps a fresh
    # `otel_exporter_pid` exporter onto the running batch processor so
    # this test process receives real `{:span, ...}` messages, restoring
    # the prior exporter on exit, and (c) points the receipt bridge at a
    # fresh per-test tmp directory so chain verification is isolated.
    BeamPM.Ingest.Bridge.reset()

    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())

    receipts_dir =
      Path.join(System.tmp_dir!(), "beam4pm_evidence_chain_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(receipts_dir)
    System.put_env("BEAM4PM_ENGINE_OP_RECEIPTS_DIR", receipts_dir)

    on_exit(fn ->
      System.delete_env("BEAM4PM_ENGINE_OP_RECEIPTS_DIR")
      File.rm_rf(receipts_dir)
    end)

    {:ok, receipts_dir: receipts_dir}
  end

  # ---------------------------------------------------------------------
  # Generalized harness -- works for ANY {engine, op} given a thunk that
  # performs the real call. Asserts on real state at all three hops, never
  # on "was telemetry called".
  # ---------------------------------------------------------------------

  @doc """
  Invokes `call_fn.()` for real, then asserts:

    * a real `OcelEvent` with `event_type == "<engine>.<op>"` is present
      in `BeamPM.Ingest.Bridge.events/0`,
    * a real OTel span named `"beam4pm.engine.<engine>.<op>"` arrived at
      this test process (via the pid exporter swapped in by `setup/0`),
      carrying the expected `ocel.outcome` (`"ok"` or `"error"`),
    * a real, independently-verified `beam4pm-brce/v1` receipt chain of
      length >= 1 exists for `chain_id = "<engine>.<op>"`.

  Returns `call_fn.()`'s own result so callers can assert on it too.
  """
  @spec assert_full_evidence_chain!(atom(), atom(), (-> term()), keyword()) :: term()
  def assert_full_evidence_chain!(engine, op, call_fn, opts \\ []) do
    expected_outcome = Keyword.get(opts, :expect, :ok)
    receipts_dir = Keyword.fetch!(opts, :receipts_dir)

    call_result = call_fn.()

    expected_event_type = "#{engine}.#{op}"

    # --- Hop 1: real OCEL event -----------------------------------
    ocel_events =
      BeamPM.Ingest.Bridge.events()
      |> Enum.filter(&(&1.event_type == expected_event_type))

    assert [%BeamPM.Types.OcelEvent{} = ocel_event | _] = ocel_events,
           "expected at least one real OcelEvent with event_type #{inspect(expected_event_type)}, " <>
             "got event_types: #{inspect(Enum.map(BeamPM.Ingest.Bridge.events(), & &1.event_type))}"

    assert is_binary(ocel_event.event_id) and ocel_event.event_id != ""
    assert ocel_event.attributes["engine"] == inspect(engine)
    assert ocel_event.attributes["op"] == inspect(op)

    # --- Hop 2: real OTel span, captured via the real pid exporter -
    expected_span_name = "beam4pm.engine.#{engine}.#{op}"
    # `:otel_tracer_provider.force_flush/0` casts (async) to the
    # `otel_batch_processor` gen_statem rather than blocking until the
    # export completes (confirmed by reading
    # `deps/opentelemetry/src/otel_tracer_server.erl`'s `force_flush`
    # handler and `otel_batch_processor.erl`'s own `force_flush/1`,
    # `gen_statem:cast/2`) -- so the real span can legitimately arrive
    # several seconds after this call returns. `receive_span/2`'s budget
    # is sized generously (10s) to absorb that real async gap.
    :ok = :otel_tracer_provider.force_flush()

    span = receive_span(expected_span_name)

    assert span != nil,
           "expected a real OTel span named #{inspect(expected_span_name)} to arrive via " <>
             "the pid exporter within the timeout"

    span_outcome = span_attribute(span, "ocel.outcome")

    expected_outcome_str = if expected_outcome == :ok, do: "ok", else: "error"
    assert span_outcome == expected_outcome_str

    if expected_outcome == :error do
      assert span_attribute(span, "ocel.refusal_reason") != nil
    end

    # --- Hop 3: real, independently-verified BRCE receipt chain ----
    chain_id = "#{engine}.#{op}"

    assert {:ok, %{length: length, chain_id: ^chain_id, receipt_paths: paths}} =
             ReceiptChain.verify(receipts_dir, chain_id)

    assert length >= 1
    assert length(paths) == length
    assert Enum.all?(paths, &File.exists?/1)

    call_result
  end

  # 40 * 250ms = 10s total budget -- generous because
  # `:otel_tracer_provider.force_flush/0` is a real async cast (see the
  # comment above its call site), not a synchronous flush.
  defp receive_span(expected_name, tries \\ 40)
  defp receive_span(_expected_name, 0), do: nil

  defp receive_span(expected_name, tries) do
    receive do
      {:span, span} ->
        if elem(span, 6) == expected_name do
          span
        else
          receive_span(expected_name, tries - 1)
        end
    after
      250 -> receive_span(expected_name, tries - 1)
    end
  end

  # `span` is the real `#span{}` record from
  # `deps/opentelemetry/include/otel_span.hrl`, decoded here as a plain
  # tuple (no compile-time record import needed). `elem/2` in Elixir is
  # 0-INDEXED (unlike Erlang's 1-based record field numbering) -- a real
  # bug caught during this test's own development: `Tuple.to_list(span)
  # |> Enum.with_index(1)` was used to print every field next to its real
  # `elem/2` index and confirm this empirically before trusting it, since
  # the record's own doc comments describe 1-based field *positions*.
  # Tuple element 0 is the `span` record tag; per that record's real
  # field order (trace_id, span_id, tracestate, parent_span_id,
  # parent_span_is_remote, name, kind, start_time, end_time,
  # attributes, ...), `name` is `elem(span, 6)` and `attributes` is
  # `elem(span, 10)` -- an `otel_attributes` record
  # (`deps/opentelemetry_api/src/otel_attributes.erl`: tag, count_limit,
  # value_length_limit, dropped, map) whose `elem/2` index 4 is the real
  # attribute map.
  defp span_attribute(span, key) do
    attributes_record = elem(span, 10)
    attribute_map = elem(attributes_record, 4)
    Map.get(attribute_map, key)
  end

  # ---------------------------------------------------------------------
  # Representative ops -- one per engine, real call, real assertions
  # ---------------------------------------------------------------------

  describe "petgraph.graph_new (PURE representative)" do
    if not Petgraph.wasm_built?() do
      @describetag skip: Petgraph.wasm_missing_reason()
    end

    test "a real graph_new call produces real OCEL + OTel + receipt evidence", %{receipts_dir: dir} do
      {:ok, _pid} = Petgraph.start()

      result =
        assert_full_evidence_chain!(:petgraph, :graph_new, fn -> Petgraph.graph_new() end,
          receipts_dir: dir
        )

      assert {:ok, %{"handle" => handle}} = result
      assert is_integer(handle)
    end
  end

  describe "tract.load_model_path (STATEFUL representative, real fixture)" do
    if not Tract.wasm_built?() do
      @describetag skip: Tract.wasm_missing_reason()
    end

    test "a real load_model_path call over the real linear-model fixture produces real evidence",
         %{receipts_dir: dir} do
      unless File.exists?(@linear_model) do
        raise "real ONNX fixture not found at #{@linear_model} -- mix test must run from the project root"
      end

      {:ok, _pid} = Tract.start()

      result =
        assert_full_evidence_chain!(:tract, :load_model_path, fn -> Tract.load_model_path(@linear_model) end,
          receipts_dir: dir
        )

      assert {:ok, %{"handle" => handle}} = result
      assert is_integer(handle)
    end
  end

  describe "rust4pm.ocel_new (STATEFUL representative, no fixture)" do
    if not Rust4PM.wasm_built?() do
      @describetag skip: Rust4PM.wasm_missing_reason()
    end

    test "a real ocel_new call produces real OCEL + OTel + receipt evidence", %{receipts_dir: dir} do
      {:ok, _pid} = Rust4PM.start()

      result =
        assert_full_evidence_chain!(:rust4pm, :ocel_new, fn -> Rust4PM.ocel_new() end, receipts_dir: dir)

      assert {:ok, %{"ocel_handle" => handle}} = result
      assert is_integer(handle)
    end
  end

  describe "ferroplan.readiness (PURE representative, no fixture)" do
    if not Ferroplan.wasm_built?() do
      @describetag skip: Ferroplan.wasm_missing_reason()
    end

    test "a real readiness call produces real OCEL + OTel + receipt evidence", %{receipts_dir: dir} do
      {:ok, _pid} = Ferroplan.start()

      result =
        assert_full_evidence_chain!(:ferroplan, :readiness, fn -> Ferroplan.readiness() end,
          receipts_dir: dir
        )

      assert {:ok, %{}} = result
    end
  end

  # ---------------------------------------------------------------------
  # Refusal path -- a typed engine refusal must ALSO be real, first-class
  # evidence (all three hops), not silently dropped.
  # ---------------------------------------------------------------------

  describe "rust4pm.import_xes refusal path" do
    if not Rust4PM.wasm_built?() do
      @describetag skip: Rust4PM.wasm_missing_reason()
    end

    test "a real parse failure ('not xml') is captured as a real refusal OCEL event, " <>
           "an error-status OTel span, and a receipted chain entry", %{receipts_dir: dir} do
      {:ok, _pid} = Rust4PM.start()

      result =
        assert_full_evidence_chain!(:rust4pm, :import_xes, fn -> Rust4PM.import_xes("not xml") end,
          receipts_dir: dir,
          expect: :error
        )

      assert {:error, {:engine, msg}} = result
      assert msg =~ "xes import failed"
    end
  end
end
