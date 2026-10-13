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

  Fixture freshness law lives in
  `qualification/fixtures/strata-qualification.HEADER.md` and is enforced by
  the "freshness court" test below: refresh is required when the marketplace
  HEAD moved past the as-of HEAD (`fb123a452...`) AND a `packs/strata-*` pack
  changed since as-of. Regeneration on 2026-10-13 produced one standing delta
  (strata-protocol-pack REFUSED -> ALIVE, allowlisted in the HEADER), so the
  pinned fixture is intentionally retained at sha256 `4b12771a...`.

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

  @marketplace_path System.get_env("GGEN_MARKETPLACE_PATH") || "/Users/sac/ggen-marketplace"
  @as_of_head "fb123a452b52b64976185d1ad53937b2c52e7281"
  @as_of_date "2026-10-13"
  @refresh_command """
  cd /Users/sac/ggen-marketplace && python3 scripts/qualify_packs.py \
    --report /tmp/strata-qualification-current.json --workers 7 \
    --pack strata-cas-pack --pack strata-pn64-pack --pack strata-protocol-pack \
    --pack strata-signer-pack --pack strata-stratus-pack \
    --pack strata-temprun-pack --pack strata-valve-pack
  """
  @standing_delta_allowlist %{
    "strata-protocol-pack" => %{
      fixture: "REFUSED",
      regenerated: "ALIVE",
      note:
        "FM-GRAPH-013 BIND re-bind graph error (REFUSED:GGEN_PACK_SYNC_FAILED) no longer fires"
    }
  }

  test "freshness court: pinned fixture is stale when marketplace HEAD moved AND a strata pack changed since as-of #{@as_of_date}" do
    marketplace = Path.expand(@marketplace_path, __DIR__)
    assert File.dir?(marketplace), """
    ggen-marketplace checkout not reachable at #{inspect(marketplace)}.
    Set GGEN_MARKETPLACE_PATH to the canonical checkout; the freshness court
    refuses to pass vacuously when its subject is unobservable.
    """

    {head, 0} = System.cmd("git", ["-C", marketplace, "rev-parse", "HEAD"])
    head = String.trim(head)

    {log, 0} =
      System.cmd("git", ["-C", marketplace, "log", "--format=%H", "#{@as_of_head}..HEAD", "--"] ++
                   Enum.map(strata_packs(), &"packs/#{&1}"))

    changed_since_as_of = String.trim(log) != ""

    if head != @as_of_head and changed_since_as_of do
      flunk("""
      Pinned strata qualification fixture is STALE: marketplace HEAD moved past
      #{@as_of_head} (as-of #{@as_of_date}, now #{head}) AND strata packs changed
      since as-of. Regenerate and re-pin:

      #{@refresh_command}

      Known standing deltas vs the pinned fixture (allowlist, see
      qualification/fixtures/strata-qualification.HEADER.md):
      #{Enum.map(@standing_delta_allowlist, fn {pack, d} -> "\n  #{pack}: #{d.fixture} -> #{d.regenerated} (#{d.note})" end)}
      """)
    end
  end

  defp strata_packs do
    marketplace = Path.expand(@marketplace_path, __DIR__)

    case File.ls(Path.join(marketplace, "packs")) do
      {:ok, entries} ->
        Enum.filter(Enum.sort(entries), &String.starts_with?(&1, "strata-"))

      {:error, reason} ->
        flunk("cannot list #{marketplace}/packs: #{inspect(reason)}")
    end
  end
end
