defmodule BeamPM.StrataQualificationOcelTest do
  @moduledoc """
  L209-class court: strata-pack qualification verdicts as OCEL events.

  The REAL qualification report captured from ggen-marketplace's
  qualification court (``scripts/qualify_packs.py --report`` at ggen
  26.10.11) is pinned at `qualification/fixtures/strata-qualification.json`
  (sha256 `4b12771a...`). The real Python converter
  (`qualification/strata_pack_ocel.py`) is executed as a subprocess over it;
  its OCEL 2.0 envelope is decoded with the repo's own `BeamPM.Ocel.decode/1`
  and checked against the closed `BeamPM.CastleOcel` vocabulary and its
  per-event-type object binding.

  Assertions:

    * one event per pack verdict (count == report `pack_count`);
    * standing attribute maps 1:1 to the report's per-pack `status`;
    * REFUSED verdicts carry the report's `code` as `refusal_class`;
    * every event type is a `BeamPM.CastleOcel.event_names/0` member, with
      the vocabulary's required object identity present in the objects list;
    * two converter runs produce identical bytes (drift court).
  """

  use ExUnit.Case, async: true

  @report_path Path.join(__DIR__, "../qualification/fixtures/strata-qualification.json")
  @report_sha256 "4b12771ac8872070f90a9b49b5aa7eab265e218278a3295abd4ddc6a5732287c"
  @converter Path.join(__DIR__, "../qualification/strata_pack_ocel.py")
  @timestamp "2026-10-13T00:00:00Z"

  @castle_event_names Enum.map(BeamPM.CastleOcel.event_names(), & &1)
  @castle_required_objects BeamPM.CastleOcel.required_objects()

  defp report, do: @report_path |> File.read!() |> Jason.decode!()

  defp fixture_sha, do: Base.encode16(:crypto.hash(:sha256, File.read!(@report_path)), case: :lower)

  defp convert do
    {output, 0} =
      System.cmd("python3", [@converter, @report_path, "--timestamp", @timestamp],
        stderr_to_stdout: true
      )

    output
  end

  defp decoded do
    {:ok, %{events: events, objects: objects}} = convert() |> BeamPM.Ocel.decode()
    %{events: events, objects: objects}
  end

  test "pinned real report fixture" do
    assert fixture_sha() == @report_sha256
    report = report()
    assert report["schema"] == "https://ggen.dev/marketplace/qualification/v1"
    assert report["pack_count"] == 7
  end

  test "one event per pack verdict, standing 1:1, refusal class carried" do
    %{events: events} = decoded()
    packs = report()["packs"]

    assert length(events) == report()["pack_count"]

    by_pack =
      Map.new(events, fn event -> {event.attributes["pack"], event} end)

    Enum.each(packs, fn pack ->
      event = Map.fetch!(by_pack, pack["name"])
      assert event.attributes["standing"] == pack["status"]
      assert event.attributes["tool"] == "ggen qualification"
      assert event.attributes["authority"] == "none"

      if pack["status"] == "REFUSED" do
        assert event.attributes["refusal_class"] == pack["code"]
        assert String.starts_with?(event.attributes["refusal_class"], "REFUSED:")
      end
    end)
  end

  test "event types are CastleOcel vocabulary members with required object identities" do
    %{events: events, objects: objects} = decoded()

    Enum.each(events, fn event ->
      assert event.event_type in @castle_event_names

      required = Map.fetch!(@castle_required_objects, event.event_type)
      pack = event.attributes["pack"]

      Enum.each(required, fn object_type ->
        expected_id =
          case object_type do
            "system" -> "ggen-qualification"
            "container" -> "ggen-qualification:" <> pack
            "gym_act_episode" -> "pack:" <> pack
          end

        assert Enum.any?(objects, fn object ->
                 object.object_type == object_type and object.object_id == expected_id
               end),
               "missing #{object_type}:#{expected_id} for #{event.event_id}"
      end)
    end)
  end

  test "drift court: two runs convert to identical bytes" do
    assert convert() == convert()
  end
end
