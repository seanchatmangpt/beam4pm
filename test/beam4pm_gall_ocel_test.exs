defmodule BeamPM.GallOcelTest do
  @moduledoc """
  Chicago-style tests for `BeamPM.GallOcel` (v26.9.18 PRD §43.6): the
  OCEL projection of the GALL semantic work lifecycle and its pure
  conformance checker. No mocks: real `BeamPM.Types.OcelEvent` /
  `OcelObject` / `OcelRelationship` constructors, real `BeamPM.Ocel`
  encode/decode/validate machinery, real JSON on the wire, assertions on
  the actual returned data. Includes a static purity test (the compiled
  module's abstract code contains no `File`/`System`/`IO`/`Port`/`Mix`
  remote calls) guarding "observation, never subject success".
  """

  use ExUnit.Case, async: true

  alias BeamPM.GallOcel
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  @commit_sha "e90928dfe1c0ff1a2b3c4d5e6f708192a3b4c5d6"

  defp t(n), do: "2026-09-18T00:00:#{String.pad_leading(Integer.to_string(n), 2, "0")}Z"

  defp happy_trace do
    [
      %{name: :checkpoint_admitted, time: t(1), objects: %{checkpoint: "cp-aaa111"}},
      %{name: :run_created, time: t(2), objects: %{checkpoint: "cp-aaa111", run: "run-1"}},
      %{name: :epoch_created, time: t(3), objects: %{run: "run-1", epoch: "epoch-1"}},
      %{name: :worktree_provisioned, time: t(4), objects: %{epoch: "epoch-1", worker: "worker-1"}},
      %{
        name: :lease_claimed,
        time: t(5),
        objects: %{epoch: "epoch-1", lease: "lease-1", worker: "worker-1"}
      },
      %{name: :tool_admitted, time: t(6), objects: %{lease: "lease-1"}},
      %{name: :candidate_committed, time: t(7), objects: %{lease: "lease-1", candidate: @commit_sha}},
      %{name: :lease_closed, time: t(8), objects: %{lease: "lease-1", candidate: @commit_sha}},
      %{
        name: :verification_started,
        time: t(9),
        objects: %{lease: "lease-1", candidate: @commit_sha, verifier: "verifier-1"}
      },
      %{
        name: :verification_finished,
        time: t(10),
        objects: %{lease: "lease-1", candidate: @commit_sha, verifier: "verifier-1"}
      },
      %{name: :receipt_sealed, time: t(11), objects: %{receipt: "receipt-1", candidate: @commit_sha}},
      %{name: :checkpoint_promoted, time: t(12), objects: %{checkpoint: "cp-aaa111", receipt: "receipt-1"}}
    ]
  end

  defp event_names_of({:ok, %{events: events_with_rels}}), do: Enum.map(events_with_rels, &elem(&1, 0).event_type)

  describe "event vocabulary" do
    test "exposes the exact PRD §43.6 event names in lifecycle order" do
      assert GallOcel.event_names() == [
               "checkpoint_admitted",
               "run_created",
               "epoch_created",
               "worktree_provisioned",
               "lease_claimed",
               "tool_admitted",
               "candidate_committed",
               "lease_closed",
               "verification_started",
               "verification_finished",
               "receipt_sealed",
               "repair_created",
               "checkpoint_promoted"
             ]
    end

    test "exposes the exact PRD §40 object types" do
      assert GallOcel.object_types() == ~w(checkpoint run epoch lease worker candidate verifier receipt)
    end

    test "declares the admitted per-event object-identity binding with exact name strings" do
      required = GallOcel.required_objects()

      assert required["checkpoint_promoted"] == ["checkpoint", "receipt"]
      assert required["lease_claimed"] == ["epoch", "lease", "worker"]
      assert required["verification_finished"] == ["lease", "candidate", "verifier"]
      assert MapSet.new(Map.keys(required)) == MapSet.new(GallOcel.event_names())
    end
  end

  describe "check/1 happy path" do
    test "the full 12-event lifecycle conforms" do
      assert GallOcel.check(happy_trace()) == :ok
    end

    test "accepts event names given as exact strings and bare atoms" do
      assert GallOcel.check([
               :checkpoint_admitted,
               "run_created",
               :epoch_created,
               "worktree_provisioned",
               :lease_claimed,
               "tool_admitted",
               :candidate_committed,
               "lease_closed",
               :verification_started,
               "verification_finished",
               :receipt_sealed,
               :checkpoint_promoted
             ]) == :ok
    end

    test "the repair loop conforms: verification_finished -> repair_created -> subsequent lease_claimed -> re-verify -> receipt_sealed -> promote" do
      # full happy path through the first verification_finished, then the
      # repair loop, then a fresh lease/verification cycle ending in receipt
      # + promotion.
      prefix = Enum.take(happy_trace(), 10)

      repair_cycle = [
        %{name: :repair_created, time: t(91), objects: %{lease: "lease-1", worker: "worker-1"}},
        %{
          name: :lease_claimed,
          time: t(92),
          objects: %{epoch: "epoch-1", lease: "lease-2", worker: "worker-1"}
        },
        %{
          name: :candidate_committed,
          time: t(93),
          objects: %{lease: "lease-2", candidate: @commit_sha}
        },
        %{name: :lease_closed, time: t(94), objects: %{lease: "lease-2", candidate: @commit_sha}},
        %{
          name: :verification_started,
          time: t(95),
          objects: %{lease: "lease-2", candidate: @commit_sha, verifier: "verifier-1"}
        },
        %{
          name: :verification_finished,
          time: t(96),
          objects: %{lease: "lease-2", candidate: @commit_sha, verifier: "verifier-1"}
        },
        %{name: :receipt_sealed, time: t(97), objects: %{receipt: "receipt-1", candidate: @commit_sha}},
        %{name: :checkpoint_promoted, time: t(98), objects: %{checkpoint: "cp-aaa111", receipt: "receipt-1"}}
      ]

      assert GallOcel.check(prefix ++ repair_cycle) == :ok
    end
  end

  describe "check/1 falsifiers (out-of-order traces are refused, never silent)" do

    test "checkpoint_promoted before receipt_sealed is refused" do
      # receipt_sealed simply never observed
      without_receipt = Enum.reject(happy_trace(), &(&1.name == :receipt_sealed))

      assert GallOcel.check(without_receipt) ==
               {:refused, "REFUSED_CONFORMANCE", "checkpoint_promoted", "receipt_sealed"}

      # receipt_sealed observed, but only after the promotion attempt
      promoted_first =
        happy_trace()
        |> List.replace_at(10, List.last(happy_trace()))
        |> List.replace_at(11, Enum.at(happy_trace(), 10))

      assert GallOcel.check(promoted_first) ==
               {:refused, "REFUSED_CONFORMANCE", "checkpoint_promoted", "receipt_sealed"}
    end

    test "candidate_committed before lease_claimed is refused" do
      trace = [
        %{name: :checkpoint_admitted, time: t(1), objects: %{checkpoint: "cp-aaa111"}},
        %{name: :run_created, time: t(2), objects: %{checkpoint: "cp-aaa111", run: "run-1"}},
        %{name: :epoch_created, time: t(3), objects: %{run: "run-1", epoch: "epoch-1"}},
        %{name: :worktree_provisioned, time: t(4), objects: %{epoch: "epoch-1", worker: "worker-1"}},
        %{name: :candidate_committed, time: t(5), objects: %{lease: "lease-1", candidate: @commit_sha}}
      ]

      assert GallOcel.check(trace) ==
               {:refused, "REFUSED_CONFORMANCE", "candidate_committed", "lease_claimed"}
    end

    test "verification_finished before verification_started is refused" do
      swapped =
        happy_trace()
        |> List.replace_at(8, Enum.at(happy_trace(), 9))
        |> List.replace_at(9, Enum.at(happy_trace(), 8))

      assert GallOcel.check(swapped) ==
               {:refused, "REFUSED_CONFORMANCE", "verification_finished", "verification_started"}
    end

    test "missing worktree_provisioned is refused at lease_claimed" do
      trace = [
        %{name: :checkpoint_admitted, time: t(1), objects: %{checkpoint: "cp-aaa111"}},
        %{name: :run_created, time: t(2), objects: %{checkpoint: "cp-aaa111", run: "run-1"}},
        %{name: :epoch_created, time: t(3), objects: %{run: "run-1", epoch: "epoch-1"}},
        %{
          name: :lease_claimed,
          time: t(4),
          objects: %{epoch: "epoch-1", lease: "lease-1", worker: "worker-1"}
        }
      ]

      assert GallOcel.check(trace) ==
               {:refused, "REFUSED_CONFORMANCE", "lease_claimed", "worktree_provisioned"}

      # on the full happy path minus the provisioning, the first violation is
      # still typed and named (the lease-gated event reached first)
      full_minus_worktree = Enum.reject(happy_trace(), &(&1.name == :worktree_provisioned))

      assert {:refused, "REFUSED_CONFORMANCE", _, "worktree_provisioned"} =
               GallOcel.check(full_minus_worktree)
    end

    test "repair_created before any verification_finished is refused" do
      trace = [
        %{name: :checkpoint_admitted, time: t(1), objects: %{checkpoint: "cp-1"}},
        %{name: :repair_created, time: t(2), objects: %{lease: "lease-1", worker: "worker-1"}}
      ]

      assert GallOcel.check(trace) ==
               {:refused, "REFUSED_CONFORMANCE", "repair_created", "verification_finished"}
    end

    test "repair_created after a subsequent lease_claimed (window closed) is refused" do
      trace = [
        :checkpoint_admitted,
        :run_created,
        :epoch_created,
        :worktree_provisioned,
        :lease_claimed,
        :candidate_committed,
        :lease_closed,
        :verification_started,
        :verification_finished,
        :lease_claimed,
        :repair_created
      ]

      assert GallOcel.check(trace) ==
               {:refused, "REFUSED_CONFORMANCE", "repair_created", "verification_finished"}
    end

    test "run_created before checkpoint_admitted is refused" do
      assert GallOcel.check([:run_created]) ==
               {:refused, "REFUSED_CONFORMANCE", "run_created", "checkpoint_admitted"}
    end

    test "an unknown event name is a typed error, not a refusal and not silence" do
      assert GallOcel.check([%{name: :launch_missiles}]) == {:error, {:unknown_event, :launch_missiles}}
      assert GallOcel.check(["not-a-gall-event"]) == {:error, {:unknown_event, "not-a-gall-event"}}
      assert GallOcel.check([42]) == {:error, {:unknown_event, 42}}
    end
  end

  describe "project/1 lifecycle event projection" do
    test "projects the happy path into the repo's OCEL event/object pair shapes with exact names" do
      {:ok, %{events: events_with_rels, objects: objects_with_rels}} = GallOcel.project(happy_trace())

      assert length(events_with_rels) == 12
      assert event_names_of({:ok, %{events: events_with_rels}}) ==
               List.delete(GallOcel.event_names(), "repair_created")

      for {%OcelEvent{} = event, rels} <- events_with_rels do
        assert %OcelEvent{} = event
        assert is_binary(event.event_time)
        assert Enum.all?(rels, &match?(%OcelRelationship{}, &1))
      end

      # the candidate object IS the commit SHA (PRD §40)
      candidate_objects =
        for {%OcelObject{object_type: "candidate"} = o, _} <- objects_with_rels, do: o.object_id

      assert candidate_objects == [@commit_sha]
    end

    test "event ids are position-derived and event attributes carry no authority" do
      {:ok, %{events: events_with_rels}} = GallOcel.project(happy_trace())

      {first, _} = Enum.at(events_with_rels, 0)
      {last, _} = Enum.at(events_with_rels, -1)

      assert first.event_id == "gall-0001-checkpoint_admitted"
      assert last.event_id == "gall-0012-checkpoint_promoted"

      for {%OcelEvent{} = event, _} <- events_with_rels do
        assert event.attributes == %{"authority" => "none", "provenance" => "observation_only"}
      end
    end

    test "each event's E2O relationships bind the applicable PRD §40 object identities by type qualifier" do
      {:ok, %{events: events_with_rels}} = GallOcel.project(happy_trace())

      rels_by_name =
        Map.new(events_with_rels, fn {%OcelEvent{event_type: name}, rels} ->
          {name, Map.new(rels, fn %OcelRelationship{qualifier: q, object_id: id} -> {q, id} end)}
        end)

      assert rels_by_name["checkpoint_admitted"] == %{"checkpoint" => "cp-aaa111"}
      assert rels_by_name["epoch_created"] == %{"run" => "run-1", "epoch" => "epoch-1"}
      assert rels_by_name["lease_claimed"] == %{"epoch" => "epoch-1", "lease" => "lease-1", "worker" => "worker-1"}
      assert rels_by_name["tool_admitted"] == %{"lease" => "lease-1"}
      assert rels_by_name["candidate_committed"] == %{"lease" => "lease-1", "candidate" => @commit_sha}
      assert rels_by_name["verification_started"] == %{
               "lease" => "lease-1",
               "candidate" => @commit_sha,
               "verifier" => "verifier-1"
             }

      assert rels_by_name["receipt_sealed"] == %{"receipt" => "receipt-1", "candidate" => @commit_sha}
      assert rels_by_name["checkpoint_promoted"] == %{"checkpoint" => "cp-aaa111", "receipt" => "receipt-1"}
    end

    test "projects one deduplicated object per observed identity in canonical type order" do
      {:ok, %{objects: objects_with_rels}} = GallOcel.project(happy_trace())

      assert Enum.map(objects_with_rels, fn {%OcelObject{} = o, _} -> {o.object_type, o.object_id} end) == [
               {"checkpoint", "cp-aaa111"},
               {"run", "run-1"},
               {"epoch", "epoch-1"},
               {"lease", "lease-1"},
               {"worker", "worker-1"},
               {"candidate", @commit_sha},
               {"verifier", "verifier-1"},
               {"receipt", "receipt-1"}
             ]
    end

    test "deterministic: same trace in, structurally identical projection out, twice" do
      first = GallOcel.project(happy_trace())
      second = GallOcel.project(happy_trace())
      assert first == second

      {:ok, %{events: first_events, objects: first_objects}} = first
      {:ok, first_json} = GallOcel.encode(%{events: first_events, objects: first_objects})
      {:ok, second_json} = GallOcel.encode(%{events: first_events, objects: first_objects})
      assert first_json == second_json
    end

    test "refuses a missing required object identity, typed" do
      trace = [
        %{name: :checkpoint_admitted, time: t(1), objects: %{}}
      ]

      assert GallOcel.project(trace) == {:error, {:missing_object_identity, :checkpoint_admitted, :checkpoint}}
    end

    test "refuses an inapplicable object identity for the event type, typed" do
      trace = [
        %{name: :tool_admitted, time: t(1), objects: %{lease: "lease-1", verifier: "verifier-1"}}
      ]

      assert GallOcel.project(trace) ==
               {:error, {:inapplicable_object_identity, :tool_admitted, :verifier}}
    end

    test "refuses unknown event names, missing time, and non-map objects, typed" do
      assert GallOcel.project([%{name: :not_real, time: t(1), objects: %{}}]) ==
               {:error, {:unknown_event, :not_real}}

      assert GallOcel.project([%{name: :checkpoint_admitted, objects: %{checkpoint: "cp-1"}}]) ==
               {:error, {:missing_time, :checkpoint_admitted}}

      assert GallOcel.project([%{name: :checkpoint_admitted, time: 17, objects: %{checkpoint: "cp-1"}}]) ==
               {:error, {:time_not_binary, :checkpoint_admitted, 17}}

      assert GallOcel.project([%{name: :checkpoint_admitted, time: t(1), objects: "nope"}]) ==
               {:error, {:objects_not_map, :checkpoint_admitted, "nope"}}

      assert GallOcel.project(["garbage"]) == {:error, {:invalid_trace_element, "garbage"}}
    end
  end

  describe "encode/1 + JSON round-trip" do
    test "delegates to the repo's OCEL 2.0 envelope and round-trips through Jason and BeamPM.Ocel.decode/1" do
      assert Code.ensure_loaded?(Jason), "jason expected in the dependency closure (mix.lock)"

      {:ok, projected} = GallOcel.project(happy_trace())
      {:ok, json} = GallOcel.encode(projected)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert Map.has_key?(decoded, "events")
      assert Map.has_key?(decoded, "objects")
      assert length(decoded["events"]) == 12
      assert length(decoded["objects"]) == 8
      assert %{"event_type" => "checkpoint_admitted"} = List.first(decoded["events"])

      {:ok, %{events: events, objects: objects}} = BeamPM.Ocel.decode(json)
      assert Enum.map(events, & &1.event_type) == List.delete(GallOcel.event_names(), "repair_created")
      assert Enum.at(events, 0).event_time == t(1)
      assert length(objects) == 8
      assert %OcelObject{object_type: "candidate", object_id: @commit_sha} =
               Enum.find(objects, &(&1.object_type == "candidate"))
    end
  end

  describe "integration with BeamPM.Ocel (the projection composes with existing machinery)" do
    test "projected pairs pass BeamPM.Ocel.validate_envelope/2 with no dangling relationships" do
      {:ok, %{events: events_with_rels, objects: objects_with_rels}} = GallOcel.project(happy_trace())

      assert BeamPM.Ocel.validate_envelope(events_with_rels, objects_with_rels) == :ok
    end

    test "BeamPM.Ocel.object_trace/2 reads the candidate's milestone history in observed order" do
      {:ok, %{events: events_with_rels}} = GallOcel.project(happy_trace())

      trace = BeamPM.Ocel.object_trace(events_with_rels, @commit_sha)

      assert Enum.map(trace, & &1.event_type) == [
               "candidate_committed",
               "lease_closed",
               "verification_started",
               "verification_finished",
               "receipt_sealed"
             ]
    end

    test "reusable objects predicate: every projected object carries an admitted §40 type" do
      {:ok, %{objects: objects_with_rels}} = GallOcel.project(happy_trace())
      admitted = MapSet.new(GallOcel.object_types())

      for {%OcelObject{} = object, _rels} <- objects_with_rels do
        assert MapSet.member?(admitted, object.object_type)
      end
    end
  end

  describe "observation ≠ authority (PRD §43.6 central requirement)" do
    test "public API has no side-effect path: compiled module contains no File/System/IO/Port/Mix remote calls" do
      path = :code.which(GallOcel)
      assert is_list(path), "GallOcel.beam must be loadable"

      {:ok, {_module, chunks}} = :beam_lib.chunks(path, [:abstract_code])
      {:raw_abstract_v1, forms} = Keyword.fetch!(chunks, :abstract_code)

      forbidden = MapSet.new([File, System, IO, Port, Mix, File.Stream, IO.Stream, StringIO])
      called = remote_call_modules(forms) |> MapSet.new()

      assert MapSet.disjoint?(called, forbidden),
             "side-effect modules leaked into GallOcel: #{inspect(MapSet.intersection(called, forbidden) |> MapSet.to_list())}"
    end

    test "every projected event carries authority: none and provenance-only markers" do
      {:ok, %{events: events_with_rels}} = GallOcel.project(happy_trace())

      for {%OcelEvent{attributes: attributes}, _rels} <- events_with_rels do
        assert attributes["authority"] == "none"
        assert attributes["provenance"] == "observation_only"
      end
    end

    test "projection is a pure function of its input: no clock or ambient state leaks between calls" do
      # determinism re-asserted from a different observation set, proving no
      # hidden accumulation: a shorter trace projects identically whether or
      # not a longer trace was projected before it in this test process.
      short = Enum.take(happy_trace(), 5)
      _ = GallOcel.project(happy_trace())
      assert GallOcel.project(short) == GallOcel.project(short)
      assert event_names_of(GallOcel.project(short)) == Enum.take(GallOcel.event_names(), 5)
    end
  end

  # Walk Erlang abstract format recursively collecting remote-call target modules.
  defp remote_call_modules(forms) when is_list(forms), do: Enum.flat_map(forms, &remote_call_modules/1)

  defp remote_call_modules({:remote, _anno, mod, fun}) do
    case {mod, fun} do
      {{:atom, _, module}, {:atom, _, _fun}} -> [module]
      _ -> []
    end
  end

  defp remote_call_modules(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.flat_map(&remote_call_modules/1)
  end

  defp remote_call_modules(list) when is_list(list) do
    case :unicode.characters_to_binary(list) do
      # charlist (string literal in abstract code) -- not structure to walk
      binary when is_binary(binary) -> []
      _ -> Enum.flat_map(list, &remote_call_modules/1)
    end
  end

  defp remote_call_modules(_), do: []
end
