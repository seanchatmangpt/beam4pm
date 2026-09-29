defmodule BeamPM.OcelSessionFactsTest do
  @moduledoc """
  Pure (engine-free) tests for `BeamPM.OcelSessionFacts`: per-dialect
  `normalize/1` against the three golden fixtures (exact event lists),
  the pinned deviation-fact name policy, golden sight projections
  (exact lists, over canned `BeamPM.PowlConformance` result maps), the
  deterministic ordering law, and the redaction law (structural-only
  error details; no raw attribute values in outputs; no logging in the
  source -- a source-level gate, so the no-logging obligation survives
  prompt loss).

  Real-engine conformance legs live in
  `BeamPM.OcelSessionFactsEngineTest` (same file), named-skipped when
  the rust4pm wasm artifact is absent -- the same NAMED skip convention
  as `BeamPM.FerroplanTest`/`BeamPM.Rust4PM.CiTest`, never a silent
  pass.
  """

  use ExUnit.Case, async: true

  alias BeamPM.OcelSessionFacts

  @fixtures Path.expand("fixtures/ocel_session_facts", __DIR__)
  @zcode_path Path.join(@fixtures, "zcode_plain_key.jsonocel")
  @xaas_path Path.join(@fixtures, "xaas_ocel_prefixed.ndjson")
  @ingest_path Path.join(@fixtures, "beam4pm_ingest.json")
  @lib_path Path.expand("../lib/beam4pm_ocel_session_facts.ex", __DIR__)

  # -----------------------------------------------------------------
  # Golden fixtures -> normalize/1 -> EXACT pinned event lists
  # -----------------------------------------------------------------

  test "golden zcode_plain_key.jsonocel normalizes to the exact pinned event list" do
    doc = @zcode_path |> File.read!() |> JSON.decode!()

    assert {:ok, events} = OcelSessionFacts.normalize(doc)

    assert events == [
             %{
               "event_id" => "zc-e1",
               "event_type" => "open",
               "event_time" => "2026-01-01T10:00:00+00:00",
               "attributes" => %{"authorized" => "true"},
               "relationships" => [%{"object_id" => "m1", "qualifier" => "meeting"}]
             },
             %{
               "event_id" => "zc-e2",
               "event_type" => "plan",
               "event_time" => "2026-01-01T10:05:00+00:00",
               "attributes" => %{},
               "relationships" => [%{"object_id" => "m1", "qualifier" => "meeting"}]
             },
             %{
               "event_id" => "zc-e3",
               "event_type" => "review",
               "event_time" => "2026-01-01T10:10:00+00:00",
               "attributes" => %{"duration_ms" => "4200"},
               "relationships" => [%{"object_id" => "m1", "qualifier" => "meeting"}]
             },
             %{
               "event_id" => "zc-e4",
               "event_type" => "close",
               "event_time" => "2026-01-01T10:15:00+00:00",
               "attributes" => %{},
               "relationships" => [%{"object_id" => "m1", "qualifier" => "meeting"}]
             }
           ]
  end

  test "golden xaas_ocel_prefixed.ndjson normalizes to the exact pinned event list" do
    lines =
      @xaas_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert {:ok, events} = OcelSessionFacts.normalize(lines)

    assert events == [
             %{
               "event_id" => "0197xaas-0000-7000-8000-000000000001",
               "event_type" => "book.create",
               "event_time" => "2026-01-02T10:00:00Z",
               "attributes" => %{"outcome" => "valid", "authorize?" => true},
               "relationships" => [%{"object_id" => "book:1", "qualifier" => "book"}]
             },
             %{
               "event_id" => "0197xaas-0000-7000-8000-000000000002",
               "event_type" => "book.publish",
               "event_time" => "2026-01-02T10:05:00Z",
               "attributes" => %{"outcome" => "valid"},
               "relationships" => [%{"object_id" => "book:1", "qualifier" => "book"}]
             }
           ]
  end

  test "golden beam4pm_ingest.json normalizes to the exact pinned event list" do
    doc = @ingest_path |> File.read!() |> JSON.decode!()

    assert {:ok, events} = OcelSessionFacts.normalize(doc)

    assert events == [
             %{
               "event_id" => "ing-e1",
               "event_type" => "open",
               "event_time" => "2026-01-03T10:00:00+00:00",
               "attributes" => %{"authorized" => true},
               "relationships" => [%{"qualifier" => "meeting", "object_id" => "m1"}]
             },
             %{
               "event_id" => "ing-e2",
               "event_type" => "plan",
               "event_time" => "2026-01-03T10:05:00+00:00",
               "attributes" => %{},
               "relationships" => [%{"qualifier" => "meeting", "object_id" => "m1"}]
             },
             %{
               "event_id" => "ing-e3",
               "event_type" => "review",
               "event_time" => "2026-01-03T10:10:00+00:00",
               "attributes" => %{"duration_ms" => 42},
               "relationships" => [%{"qualifier" => "meeting", "object_id" => "m1"}]
             },
             %{
               "event_id" => "ing-e4",
               "event_type" => "close",
               "event_time" => "2026-01-03T10:15:00+00:00",
               "attributes" => %{},
               "relationships" => [%{"qualifier" => "meeting", "object_id" => "m1"}]
             }
           ]
  end

  # -----------------------------------------------------------------
  # Dialect detection (inline, structural)
  # -----------------------------------------------------------------

  test "normalize detects the zcode plain-key dialect structurally (attributes pairs -> map)" do
    doc = %{
      "objectTypes" => [],
      "eventTypes" => [],
      "objects" => [],
      "events" => [
        %{
          "id" => "e2",
          "type" => "b",
          "time" => "2026-01-01T00:05:00+00:00",
          "attributes" => [%{"name" => "ok", "value" => "false"}],
          "relationships" => [%{"objectId" => "o1", "qualifier" => "role"}]
        },
        %{
          "id" => "e1",
          "type" => "a",
          "time" => "2026-01-01T00:00:00+00:00",
          "attributes" => [],
          "relationships" => []
        }
      ]
    }

    assert {:ok, [first, second]} = OcelSessionFacts.normalize(doc)
    # Sorted by {event_time, event_id}, not input order.
    assert first["event_id"] == "e1"
    assert second["attributes"] == %{"ok" => "false"}
    assert second["relationships"] == [%{"object_id" => "o1", "qualifier" => "role"}]
  end

  test "normalize detects xaas ocel:-prefixed ndjson lines from a list" do
    line = %{
      "ocel:objectTypes" => [%{"name" => "turn"}],
      "ocel:eventTypes" => [%{"name" => "turn.start"}],
      "ocel:events" => [
        %{
          "id" => "t1",
          "type" => "turn.start",
          "time" => "2026-01-02T00:00:00Z",
          "attributes" => %{"k" => "v"},
          "relationships" => [%{"objectId" => "turn:1", "qualifier" => "turn"}]
        }
      ],
      "ocel:objects" => [%{"id" => "turn:1", "type" => "turn", "attributes" => {}, "relationships" => []}]
    }

    assert {:ok, [event]} = OcelSessionFacts.normalize([line])
    assert event == %{
             "event_id" => "t1",
             "event_type" => "turn.start",
             "event_time" => "2026-01-02T00:00:00Z",
             "attributes" => %{"k" => "v"},
             "relationships" => [%{"object_id" => "turn:1", "qualifier" => "turn"}]
           }
  end

  test "normalize is idempotent on internal-shape event lists" do
    internal = [
      %{
        "event_id" => "x2",
        "event_type" => "b",
        "event_time" => "2026-01-04T00:05:00+00:00",
        "attributes" => %{},
        "relationships" => []
      },
      %{
        "event_id" => "x1",
        "event_type" => "a",
        "event_time" => "2026-01-04T00:00:00+00:00",
        "attributes" => %{},
        "relationships" => []
      }
    ]

    assert {:ok, sorted} = OcelSessionFacts.normalize(internal)
    assert Enum.map(sorted, & &1["event_id"]) == ["x1", "x2"]
  end

  test "the legacy flat ocel:eid/ocel:activity line shape is refused as an unknown dialect" do
    legacy = [%{"ocel:eid" => "e1", "ocel:activity" => "x", "ocel:timestamp" => "T"}]

    assert {:error, {:ocel_dialect_unknown, detail}} = OcelSessionFacts.normalize(legacy)
    assert is_map(detail)
  end

  test "a totally unrecognized input is refused with a structural detail" do
    assert {:error, {:ocel_dialect_unknown, detail}} = OcelSessionFacts.normalize(%{"nope" => 1})
    assert detail["input_kind"] == :map

    assert {:error, {:ocel_dialect_unknown, _}} = OcelSessionFacts.normalize("not an ocel")
  end

  test "a malformed event inside a recognized dialect refuses the WHOLE input, naming the index" do
    doc = %{
      "events" => [
        %{"id" => "ok1", "type" => "a", "time" => "2026-01-01T00:00:00+00:00",
          "attributes" => [], "relationships" => []},
        # Missing "name" in the attribute pair -- structurally malformed.
        %{"id" => "bad2", "type" => "b", "time" => "2026-01-01T00:01:00+00:00",
          "attributes" => [%{"value" => 1}], "relationships" => []}
      ],
      "objects" => []
    }

    assert {:error, {:ocel_dialect_unknown, detail}} = OcelSessionFacts.normalize(doc)
    assert detail["dialect"] == :zcode_plain_key
    assert detail["event_index"] == 1
  end

  # -----------------------------------------------------------------
  # deviation_facts/2 -- the pinned fact-name policy
  # -----------------------------------------------------------------

  test "a conforming result with no deviations projects to exactly the conforms umbrella" do
    result = %{conforms: true, deviations: []}

    assert OcelSessionFacts.deviation_facts(result) == [{"conforms", true}]
  end

  test "a model-only move ([log >>, model activity]) -> dev_<model activity>" do
    result = %{conforms: false, deviations: [[">>", "clean_house"]]}

    assert OcelSessionFacts.deviation_facts(result) == [
             {"conforms", false},
             {"dev_clean_house", true}
           ]
  end

  test "a log-only move ([log activity, model >>]) -> dev_<log activity>" do
    result = %{conforms: false, deviations: [["extra_step", ">>"]]}

    assert OcelSessionFacts.deviation_facts(result) == [
             {"conforms", false},
             {"dev_extra_step", true}
           ]
  end

  test "a both-real-activities move -> one dev_log_/dev_model_ fact per side" do
    result = %{conforms: false, deviations: [["book.create", "book.archive"]]}

    assert OcelSessionFacts.deviation_facts(result) == [
             {"conforms", false},
             {"dev_log_book.create", true},
             {"dev_model_book.archive", true}
           ]
  end

  test "a degenerate [>>, >>] move and a malformed move contribute no facts" do
    result = %{conforms: true, deviations: [[">>", ">>"], [">>"]]}

    assert OcelSessionFacts.deviation_facts(result) == [{"conforms", true}]
  end

  test "duplicate moves deduplicate; the list is always sorted by fact name" do
    result = %{
      conforms: false,
      deviations: [[">>", "review"], ["extra", ">>"], [">>", "review"]]
    }

    facts = OcelSessionFacts.deviation_facts(result)

    assert facts == [
             {"conforms", false},
             {"dev_extra", true},
             {"dev_review", true}
           ]

    assert facts == Enum.sort(facts)
    # Deterministic: same input, same output, byte for byte.
    assert facts == OcelSessionFacts.deviation_facts(result)
  end

  test "a missing :conforms key counts as false (never nil, never raised)" do
    result = %{deviations: []}

    assert OcelSessionFacts.deviation_facts(result) == [{"conforms", false}]
  end

  # -----------------------------------------------------------------
  # Attribute discretization
  # -----------------------------------------------------------------

  test "only boolean-valued attributes become facts; everything else is skipped and counted" do
    result = %{conforms: true, deviations: []}

    attrs = %{
      "authorized" => true,
      "flag" => "false",
      "duration_ms" => 42,
      "note" => "free text",
      "empty" => nil
    }

    summary = OcelSessionFacts.fact_summary(result, attributes: attrs)

    assert summary.facts == [
             {"authorized_true", true},
             {"conforms", true},
             {"flag_false", true}
           ]

    assert summary.skipped_attributes == 3
  end

  test "non-string attribute keys are skipped and counted, never raised" do
    result = %{conforms: true, deviations: []}
    summary = OcelSessionFacts.fact_summary(result, attributes: %{42 => true})

    assert summary.facts == [{"conforms", true}]
    assert summary.skipped_attributes == 1
  end

  # -----------------------------------------------------------------
  # Golden sight: fixture -> canned conformance -> EXACT sight list
  # -----------------------------------------------------------------

  test "golden zcode fixture -> exact deviant sight list" do
    doc = @zcode_path |> File.read!() |> JSON.decode!()
    {:ok, events} = OcelSessionFacts.normalize(doc)

    canned = %{conforms: false, deviations: [[">>", "review"]]}

    attrs =
      events
      |> Enum.map(& &1["attributes"])
      |> Enum.reduce(&Map.merge/2)

    assert OcelSessionFacts.deviation_facts(canned, attributes: attrs) == [
             {"authorized_true", true},
             {"conforms", false},
             {"dev_review", true}
           ]
  end

  test "golden xaas fixture -> exact both-sides-deviant sight list" do
    lines =
      @xaas_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    {:ok, events} = OcelSessionFacts.normalize(lines)
    assert length(events) == 2

    canned = %{conforms: false, deviations: [["book.create", "book.archive"]]}
    attrs = %{"authorize?" => true, "outcome" => "valid"}

    assert OcelSessionFacts.deviation_facts(canned, attributes: attrs) == [
             {"authorize?_true", true},
             {"conforms", false},
             {"dev_log_book.create", true},
             {"dev_model_book.archive", true}
           ]
  end

  test "golden ingest fixture -> exact sight list + skipped-attribute summary" do
    doc = @ingest_path |> File.read!() |> JSON.decode!()
    {:ok, events} = OcelSessionFacts.normalize(doc)

    canned = %{conforms: false, deviations: [[">>", "review"]]}

    attrs =
      events
      |> Enum.map(& &1["attributes"])
      |> Enum.reduce(&Map.merge/2)

    summary = OcelSessionFacts.fact_summary(canned, attributes: attrs)

    assert summary.facts == [
             {"authorized_true", true},
             {"conforms", false},
             {"dev_review", true}
           ]

    assert summary.conforms == false
    assert summary.deviation_count == 1
    assert summary.skipped_attributes == 1
  end

  test "golden ingest fixture, conforming trace -> exactly the conforms umbrella" do
    doc = @ingest_path |> File.read!() |> JSON.decode!()
    {:ok, _events} = OcelSessionFacts.normalize(doc)

    assert OcelSessionFacts.deviation_facts(%{conforms: true, deviations: []}) == [
             {"conforms", true}
           ]
  end

  # -----------------------------------------------------------------
  # Redaction law
  # -----------------------------------------------------------------

  test "error details never carry raw attribute values (structural only)" do
    raw_secret = "SEKRIT-TOKEN-9f3"

    doc = %{
      "events" => [
        %{"id" => "e1", "type" => "a", "time" => "2026-01-01T00:00:00+00:00",
          "attributes" => [%{"value" => raw_secret}], "relationships" => []}
      ],
      "objects" => []
    }

    assert {:error, {:ocel_dialect_unknown, detail}} = OcelSessionFacts.normalize(doc)
    refute inspect(detail) =~ raw_secret
  end

  test "non-boolean attribute values never leak into the sight batch" do
    raw_secret = "SEKRIT-TOKEN-9f3"
    result = %{conforms: true, deviations: []}

    facts = OcelSessionFacts.deviation_facts(result, attributes: %{"note" => raw_secret})

    refute inspect(facts) =~ raw_secret
    assert facts == [{"conforms", true}]
  end

  test "the module source performs no logging at all (permanent source-level gate)" do
    source = File.read!(@lib_path)

    refute source =~ "Logger"
    refute source =~ "IO.puts"
    refute source =~ "IO.inspect"
  end

  # -----------------------------------------------------------------
  # Typed BLOCKED refusals (artifact-absent environment only; at
  # integration, with the wasm built, these refusals cannot occur and
  # the assertions would be vacuous -- so they only run when absent).
  # -----------------------------------------------------------------

  if not BeamPM.Rust4PM.wasm_built?() do
    test "sight_for_trace events path refuses typed when the engine artifact is absent" do
      doc = @ingest_path |> File.read!() |> JSON.decode!()
      {:ok, events} = OcelSessionFacts.normalize(doc)

      assert {:error, {:ocel_build, {:wasmex, {:engine_not_started, _}}}} =
               OcelSessionFacts.sight_for_trace(events, "meeting", ["open"])
    end

    test "sight_for_trace handle path propagates the engine's typed refusal when absent" do
      assert {:error, {:wasmex, {:engine_not_started, _}}} =
               OcelSessionFacts.sight_for_trace(99_999, "meeting", ["open"])
    end
  end
end

defmodule BeamPM.OcelSessionFactsEngineTest do
  @moduledoc """
  Real-engine legs: end-to-end golden-fixture -> real OCEL handle ->
  real `BeamPM.PowlConformance.check_conformance/3` -> sight batch.

  NAMED SKIP (repo convention, `BeamPM.FerroplanTest`): when the rust4pm
  wasm artifact is absent the whole module skips with
  `BeamPM.Rust4PM.wasm_missing_reason/0` as the printed reason -- the
  diagnostic IS the skip message, never a silent pass and never a fake
  green.
  """

  use ExUnit.Case, async: false

  alias BeamPM.OcelSessionFacts
  alias BeamPM.Rust4PM

  if not Rust4PM.wasm_built?() do
    @moduletag skip: Rust4PM.wasm_missing_reason()
  end

  @ingest_path Path.expand("fixtures/ocel_session_facts/beam4pm_ingest.json", __DIR__)

  setup_all do
    case Rust4PM.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  # The ingest golden fixture's 4 activities (open -> plan -> review ->
  # close on meeting m1), replicated over 3 meetings at distinct base
  # hours -- the exact 3-trace reference shape proven in
  # test/beam4pm_deviation_admission_test.exs, built FROM fixture events.
  defp reference_events do
    {:ok, events} =
      @ingest_path |> File.read!() |> JSON.decode!() |> OcelSessionFacts.normalize()

    for {mid, base_hour} <- [{"m1", 10}, {"m2", 14}, {"m3", 18}],
        {event, idx} <- Enum.with_index(events) do
      %{
        "event_id" => "e_#{mid}_#{idx}",
        "event_type" => event["event_type"],
        "event_time" => phase_time(base_hour, idx),
        "attributes" => event["attributes"],
        "relationships" => [%{"object_id" => mid, "qualifier" => "meeting"}]
      }
    end
  end

  defp phase_time(base_hour, idx) do
    "2026-01-05T" <> pad(base_hour) <> ":" <> pad(idx * 5) <> ":00+00:00"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  @conformant_trace ["open", "plan", "review", "close"]
  @deviant_trace ["open", "plan", "close"]

  test "events path end-to-end: conformant trace -> exactly [{\"conforms\", true}] + summary" do
    assert {:ok, sight, summary} =
             OcelSessionFacts.sight_for_trace(reference_events(), "meeting", @conformant_trace,
               attributes: %{"authorized" => true, "duration_ms" => 42}
             )

    assert sight == [{"authorized_true", true}, {"conforms", true}]

    assert summary == %{
             conforms: true,
             deviation_count: 0,
             skipped_attributes: 1,
             dialect: :internal
           }
  end

  test "events path end-to-end: deviant trace (review skipped) -> conforms false + dev_review fact" do
    assert {:ok, sight, summary} =
             OcelSessionFacts.sight_for_trace(reference_events(), "meeting", @deviant_trace)

    assert summary.conforms == false
    assert summary.deviation_count > 0
    assert summary.dialect == :internal

    assert {"conforms", false} in sight
    assert Enum.any?(sight, &match?({"dev_review", true}, &1))
  end

  test "handle path end-to-end: caller-owned OCEL handle -> conformant sight, dialect :handle" do
    {:ok, events} =
      @ingest_path |> File.read!() |> JSON.decode!() |> OcelSessionFacts.normalize()

    # The exact proven recipe (beam4pm_deviation_admission_test.exs).
    {:ok, %{"ocel_handle" => handle}} = Rust4PM.ocel_new()

    for t <- Enum.uniq(Enum.map(events, & &1["event_type"])), do: {:ok, _} = Rust4PM.ocel_add_event_type(handle, t)

    {:ok, _} = Rust4PM.ocel_add_object_type(handle, "meeting")

    for {mid, base_hour} <- [{"m1", 10}, {"m2", 14}, {"m3", 18}] do
      {:ok, _} = Rust4PM.ocel_add_object(handle, mid, "meeting")

      events
      |> Enum.with_index()
      |> Enum.each(fn {event, idx} ->
        {:ok, _} =
          Rust4PM.ocel_add_event(
            handle,
            "e_#{mid}_#{idx}",
            event["event_type"],
            phase_time(base_hour, idx),
            [[mid, "meeting"]]
          )
      end)
    end

    assert {:ok, sight, summary} =
             OcelSessionFacts.sight_for_trace(handle, "meeting", @conformant_trace)

    assert sight == [{"conforms", true}]
    assert summary.dialect == :handle
    assert summary.conforms == true

    {:ok, %{"freed" => true}} = Rust4PM.free_ocel(handle)
  end
end
