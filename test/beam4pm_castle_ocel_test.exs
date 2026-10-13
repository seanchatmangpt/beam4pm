defmodule BeamPM.CastleOcelTest do
  use ExUnit.Case, async: true

  alias BeamPM.CastleOcel
  alias BeamPM.GallOcel

  @ids %{system: "sys-1", pod: "pod-1", container: "ctr-1", gym_act_episode: "ep-1"}

  defp obs(name) when is_atom(name) do
    required =
      CastleOcel.required_objects()
      |> Map.fetch!(Atom.to_string(name))
      |> Enum.map(&String.to_existing_atom/1)

    %{
      name: name,
      time: "2026-10-13T00:00:00Z",
      objects: Map.take(@ids, required)
    }
  end

  defp obs(name) when is_binary(name), do: %{name: name, time: "2026-10-13T00:00:00Z"}

  defp happy_trace do
    [
      obs(:system_bootstrapped),
      obs(:pod_provisioned),
      obs(:container_started),
      obs(:ggen_sync_observed),
      obs(:activity_started),
      obs(:activity_finished),
      obs(:episode_recorded),
      obs(:evidence_admitted),
      obs(:episode_receipt_sealed)
    ]
  end

  describe "project/1" do
    test "conformant happy path projects into the repo's OCEL shapes" do
      assert {:ok, %{events: events, objects: objects}} = CastleOcel.project(happy_trace())

      assert length(events) == 9
      assert {event, rels} = hd(events)
      assert event.event_id == "castle-0001-system_bootstrapped"
      assert event.event_type == "system_bootstrapped"
      assert event.attributes == %{"authority" => "none", "provenance" => "observation_only"}
      assert Enum.any?(rels, &(&1.qualifier == "system" and &1.object_id == "sys-1"))

      assert Enum.any?(objects, fn {object, _} ->
               object.object_type == "gym_act_episode" and object.object_id == "ep-1"
             end)

      # determinism
      assert {:ok, projection_a} = CastleOcel.project(happy_trace())
      assert {:ok, projection_b} = CastleOcel.project(happy_trace())
      assert projection_a == projection_b
    end

    test "unknown event is a typed refusal, not a crash" do
      assert {:error, {:unknown_event, "teleport"}} =
               CastleOcel.project([obs(:system_bootstrapped), obs("teleport")])
    end

    test "missing object identity is a typed refusal" do
      bad = %{name: :pod_provisioned, time: "t", objects: %{system: "sys-1"}}

      assert {:error, {:missing_object_identity, :pod_provisioned, :pod}} =
               CastleOcel.project([bad])
    end
  end

  describe "check/1" do
    test "conformant happy path returns :ok" do
      assert :ok = CastleOcel.check(happy_trace())
    end

    test "out-of-order trace is REFUSED_CONFORMANCE with exact name strings" do
      trace = [
        obs(:system_bootstrapped),
        obs(:pod_provisioned),
        # container_started requires pod_provisioned; here pod is skipped:
        obs(:ggen_sync_observed)
      ]

      assert {:refused, "REFUSED_CONFORMANCE", "ggen_sync_observed", "container_started"} =
               CastleOcel.check(trace)
    end

    test "evidence admission requires its observation; sealing requires admission" do
      # drop episode_recorded: evidence_admitted then appears unobserved
      no_observation =
        happy_trace()
        |> Enum.reject(&(&1.name == :episode_recorded))

      assert {:refused, "REFUSED_CONFORMANCE", "evidence_admitted", "episode_recorded"} =
               CastleOcel.check(no_observation)

      # keep the observation, drop the admission: sealing then appears unadmitted
      no_admission =
        happy_trace()
        |> Enum.reject(&(&1.name == :evidence_admitted))

      assert {:refused, "REFUSED_CONFORMANCE", "episode_receipt_sealed", "evidence_admitted"} =
               CastleOcel.check(no_admission)
    end

    test "refused_observation has no prerequisites and may appear anywhere" do
      assert :ok = CastleOcel.check([obs(:refused_observation)])

      assert :ok =
               CastleOcel.check([
                 obs(:refused_observation) | happy_trace()
               ])

      assert :ok =
               CastleOcel.check(
                 happy_trace() ++ [obs(:refused_observation)]
               )
    end

    test "unknown event is a typed unknown_event refusal" do
      # an existing atom outside the closed vocabulary comes back as the atom
      assert {:error, {:unknown_event, :lease_claimed}} =
               CastleOcel.check([%{name: :lease_claimed, time: "t"}])

      # an existing atom reachable via its string comes back as the atom too
      assert {:error, {:unknown_event, :lease_claimed}} =
               CastleOcel.check([%{name: "lease_claimed", time: "t"}])

      # a string with no existing atom stays the binary
      assert {:error, {:unknown_event, "teleport"}} = CastleOcel.check([obs("teleport")])
    end
  end

  describe "encode/1" do
    test "delegates to the repo's OCEL envelope exporter" do
      assert {:ok, %{events: events, objects: objects}} = CastleOcel.project(happy_trace())
      assert {:ok, json} = CastleOcel.encode(%{events: events, objects: objects})
      assert is_binary(json)
      assert json =~ ~s("event_type":"system_bootstrapped")
    end
  end

  describe "boundary court: GALL stays closed, CASTLE is a necessary extension" do
    test "the vocabularies are disjoint" do
      refute Enum.empty?(CastleOcel.event_names())
      refute Enum.empty?(GallOcel.event_names())
      assert MapSet.disjoint?(
               MapSet.new(CastleOcel.event_names()),
               MapSet.new(GallOcel.event_names())
             )
    end

    test "a full conformant CASTLE trace refuses in the CLOSED GALL module with unknown_event" do
      for name <- CastleOcel.event_names() do
        atom = String.to_existing_atom(name)

        assert {:error, {:unknown_event, ^atom}} = GallOcel.check([%{name: name}])

        assert {:error, {:unknown_event, ^atom}} =
                 GallOcel.project([%{name: name, time: "t", objects: %{}}])
      end
    end

    test "the same trace passes CastleOcel while GALL's own happy trace passes only in GALL" do
      assert :ok = CastleOcel.check(happy_trace())

      assert {:error, {:unknown_event, :checkpoint_admitted}} =
               CastleOcel.check([obs("checkpoint_admitted")])
    end
  end
end
