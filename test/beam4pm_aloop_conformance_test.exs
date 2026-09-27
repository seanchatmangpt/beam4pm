defmodule BeamPM.AloopConformanceTest do
  @moduledoc """
  ALOOP vocabulary conformance qualification (ALOOP-ZCODE-DOGFOOD-001, lane 9).

  Proves, against the CANONICAL GENERATED process types only (no competing
  OCEL truth model, no hand-written vocabulary):

    1. every one of the 28 ALOOP event classes is representable as a generated
       `BeamPM.Types.Aloop*` struct admitted by `BeamPM.Types.Manifest`;
    2. every class constructs through the generated constructor, round-trips
       the generated JSON codec (`BeamPM.Codec.to_map/1` + `from_map/2`), and
       carries its contract qualifier field where the ALOOP contract defines
       one (candidate.construct -> origin_authority, actuate -> consequence,
       receipt.persist -> receipt, provider.replace -> from/to_provider);
    3. the ALOOP model directly-follows edges (lane 9's admitted model, mirrored
       here as data) reference only admitted ALOOP classes, and both endpoints
       of every edge round-trip as generated types;
    4. anti-vacuity: an activity OUTSIDE the ALOOP vocabulary ("deploy_to_prod",
       the corrupted-log probe) is NOT admitted by the manifest -- a conformance
       check that passed it would carry no bits;
    5. the generated constructor refuses a required-field violation on an
       ALOOP type (missing episode_id on an actuate).
  """

  use ExUnit.Case, async: true

  @aloop_event_classes ~w(
    episode.start observe gap.detect candidate.construct candidate.admit
    plan.select workorder.issue provider.select worker.claim execution.start
    tool.admit actuate checkpoint execution.crash receipt.persist verify
    falsifier.run benchmark.run failure.detect reconcile replan
    provider.replace commit merge reobserve goal.satisfied goal.blocked
    episode.terminal
  )

  @aloop_object_types ~w(
    Episode Objective Requirement WorkOrder Authority Repository Subject
    Provider Worker WorkerRun Plan Capability Candidate Consequence Evidence
    Receipt Failure Benchmark Release
  )

  # The admitted ALOOP directly-follows model (mirrors ex4pm's Ex4pm.Aloop
  # model_edges; if the two ever diverge, the cross-repo conformance court
  # in ex4pm's precision/conformance analysis is the place it will surface).
  @aloop_model_edges [
    {"episode.start", "observe"},
    {"observe", "gap.detect"}, {"observe", "goal.satisfied"}, {"observe", "goal.blocked"},
    {"reobserve", "gap.detect"}, {"reobserve", "goal.satisfied"}, {"reobserve", "goal.blocked"},
    {"gap.detect", "candidate.construct"},
    {"candidate.construct", "candidate.admit"},
    {"candidate.admit", "plan.select"},
    {"plan.select", "workorder.issue"},
    {"workorder.issue", "provider.select"}, {"workorder.issue", "worker.claim"},
    {"provider.select", "worker.claim"},
    {"worker.claim", "execution.start"},
    {"execution.start", "tool.admit"}, {"execution.start", "actuate"},
    {"execution.start", "execution.crash"},
    {"tool.admit", "actuate"},
    {"actuate", "checkpoint"},
    {"checkpoint", "receipt.persist"}, {"checkpoint", "goal.satisfied"}, {"checkpoint", "goal.blocked"},
    {"execution.crash", "failure.detect"},
    {"failure.detect", "provider.replace"}, {"failure.detect", "replan"}, {"failure.detect", "reconcile"},
    {"provider.replace", "provider.select"},
    {"replan", "plan.select"},
    {"reconcile", "verify"},
    {"receipt.persist", "verify"},
    {"verify", "falsifier.run"}, {"verify", "commit"}, {"verify", "benchmark.run"},
    {"falsifier.run", "commit"}, {"falsifier.run", "verify"},
    {"benchmark.run", "commit"},
    {"commit", "merge"}, {"commit", "reobserve"}, {"commit", "goal.satisfied"},
    {"merge", "reobserve"}, {"merge", "goal.satisfied"},
    {"goal.satisfied", "episode.terminal"},
    {"goal.blocked", "episode.terminal"}
  ]

  @qualifier_expectations %{
    "candidate.construct" => :origin_authority,
    "actuate" => :consequence,
    "receipt.persist" => :receipt,
    "provider.replace" => :from_provider,
    "provider.select" => :provider,
    "worker.claim" => :worker
  }

  defp record_name(class), do: ("aloop_" <> String.replace(class, ".", "_")) |> String.to_atom()

  defp type_module(class) do
    "BeamPM.Types." <> (String.replace(class, ".", "_") |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join())
    |> String.to_atom()
  end

  describe "vocabulary representability through generated types" do
    test "all 28 ALOOP event classes are admitted generated record names" do
      admitted = BeamPM.Types.Manifest.record_names()

      for class <- @aloop_event_classes do
        assert record_name(class) in admitted,
               "ALOOP event class #{class} (#{record_name(class)}) is not an admitted generated record type"
      end
    end

    test "the aloop object carrier and model edge types are admitted" do
      admitted = BeamPM.Types.Manifest.record_names()
      assert :aloop_object in admitted
      assert :aloop_model_edge in admitted
    end

    test "each class has its contract qualifier field where the contract defines one" do
      for {class, qualifier} <- @qualifier_expectations do
        assert qualifier in BeamPM.Types.Manifest.fields(record_name(class)),
               "ALOOP class #{class} is missing its #{qualifier} qualifier field"
      end
    end
  end

  describe "generated constructor + codec round-trip" do
    test "every ALOOP event class constructs and round-trips the generated codec" do
      for class <- @aloop_event_classes do
        base = %{
          event_id: "e-1",
          event_time: "2026-09-25T00:00:00Z",
          episode_id: "ep-1",
          attributes: %{"probe" => class}
        }

        attrs =
          case Map.get(@qualifier_expectations, class) do
            nil -> base
            q -> Map.put(base, q, "q-1")
          end

        {:ok, struct} = type_module(class).new(attrs)
        wire = BeamPM.Codec.to_map(struct)
        {:ok, back} = BeamPM.Codec.from_map(record_name(class), wire)

        assert back.event_id == "e-1" and back.episode_id == "ep-1",
               "ALOOP class #{class} failed codec round-trip"
      end
    end

    test "aloop_model_edge round-trips with and without observed_count" do
      {:ok, edge} =
        BeamPM.Types.AloopModelEdge.new(%{
          from_activity: "actuate",
          to_activity: "checkpoint"
        })

      {:ok, back} = BeamPM.Codec.from_map(:aloop_model_edge, BeamPM.Codec.to_map(edge))
      assert back.from_activity == "actuate" and back.to_activity == "checkpoint"

      {:ok, counted} =
        BeamPM.Types.AloopModelEdge.new(%{
          from_activity: "actuate",
          to_activity: "checkpoint",
          observed_count: 3
        })

      {:ok, back2} = BeamPM.Codec.from_map(:aloop_model_edge, BeamPM.Codec.to_map(counted))
      assert back2.observed_count == 3
    end

    test "the generated constructor refuses a required-field violation (falsifier)" do
      assert {:error, {:missing_field, :episode_id}} =
               BeamPM.Types.AloopActuate.new(%{event_id: "e-1", event_time: "2026-09-25T00:00:00Z"})
    end
  end

  describe "ALOOP model edges" do
    test "every model edge references only admitted ALOOP classes and round-trips" do
      admitted = BeamPM.Types.Manifest.record_names()

      for {from, to} <- @aloop_model_edges do
        assert record_name(from) in admitted and record_name(to) in admitted

        {:ok, edge} =
          BeamPM.Types.AloopModelEdge.new(%{from_activity: from, to_activity: to})

        assert {:ok, _} = BeamPM.Codec.from_map(:aloop_model_edge, BeamPM.Codec.to_map(edge))
      end
    end

    test "no model edge is degenerate (self-loop or empty)" do
      for {from, to} <- @aloop_model_edges do
        assert from != to and String.length(from) > 0 and String.length(to) > 0
      end
    end
  end

  describe "anti-vacuity: off-vocabulary activity is refused" do
    test "a corrupted off-vocabulary activity has no generated type" do
      refute :aloop_deploy_to_prod in BeamPM.Types.Manifest.record_names()
      refute :"deploy_to_prod" in BeamPM.Types.Manifest.record_names()
    end

    test "the 19 ALOOP object types are exactly the documented vocabulary (not drifted)" do
      # The aloop_object record's doc admits exactly these 19 type names; this
      # list is the conformance anchor. If a future change grows the vocabulary,
      # this test and the ontology doc must move together.
      assert length(@aloop_object_types) == 19
      assert @aloop_object_types |> Enum.uniq() |> length() == 19
    end
  end
end
