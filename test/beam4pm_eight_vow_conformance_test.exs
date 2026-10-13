defmodule BeamPM.EightVowConformanceTest do
  @moduledoc """
  Cross-conformance court (lane L61): feed insa's eight-vow bridge executions
  (insa-replaw `src/eight_vow_bridge.rs`, tests at L600-759) through beam4pm's
  process-mining machinery.

  Fixtures are pinned inline below with provenance comments — each trace is
  read directly from the insa Rust test bodies (`test_edge*` /
  `test_refused_at_edge*` / `test_all_8_edges_source_to_rest_sealed`).

  beam4pm surfaces under court:
    * `BeamPM.Art72Conformance` (token-replay fitness + typed drift decision)
      over a linear typestate Petri net of the eight vows;
    * `BeamPM.GallOcel` (beam4pm's admitted GALL lifecycle conformance court)
      on the semantically exact subset (edges 7-8 map to `receipt_sealed` /
      `checkpoint_promoted`); the full 8-edge forced mapping is NOT claimed —
      per the GallOcel moduledoc, a projected log observes, it never confers
      category, so unmapped vow edges stay vow-native and are REFUSED by the
      closed GALL vocabulary.
  """

  use ExUnit.Case, async: true

  alias BeamPM.Art72Conformance
  alias BeamPM.GallOcel

  # Art72Conformance exposes no default epsilon (drift_decision/2 takes it
  # explicitly), so this court pins its own: 0.05 separates a perfect trace
  # (fitness 1.0) from a single-skipped-edge trace (fitness 13/14 ≈ 0.9286).
  @epsilon 0.05

  # ── Fixtures (provenance-pinned) ──────────────────────────────────────────

  # Happy path: the full 8-edge sequence, edges 1-8 in order
  # (insa eight_vow_bridge.rs test_all_8_edges_source_to_rest_sealed):
  #   Source::begin -> edge1 -> edge2 -> edge3 -> edge4 -> edge5 -> edge6
  #   -> edge7 -> edge8 (seal at Rest)
  defp happy_trace do
    ~w(edge1_source_pattern edge2_pattern_field edge3_field_motion
       edge4_motion_receiver edge5_receiver_fruit edge6_fruit_receipt
       edge7_receipt_rest edge8_rest_seal)
  end

  # Edge-4 conservation refusal: edge4 (Motion -> Receiver) raises
  # BridgeError::EpochExecutionFailed when the FlowTransaction quantity
  # (10_000) exceeds the field balance (100) — insa
  # test_refused_at_edge4_when_quantity_exceeds_field_balance. The vow halts
  # at Motion; the observed trace continues at edge5.
  defp edge4_refusal_trace do
    ~w(edge1_source_pattern edge2_pattern_field edge3_field_motion
       edge5_receiver_fruit edge6_fruit_receipt edge7_receipt_rest
       edge8_rest_seal)
  end

  # Edge-5 balance refusal: edge5 (Receiver -> Fruit) raises
  # BridgeError::ReceiverObligationFailed when allocation (10_000) exceeds the
  # storehouse balance (10) — insa test_refused_at_edge5_when_allocation_
  # exceeds_balance. The vow halts at Receiver; the observed trace continues
  # at edge6.
  defp edge5_refusal_trace do
    ~w(edge1_source_pattern edge2_pattern_field edge3_field_motion
       edge4_motion_receiver edge6_fruit_receipt edge7_receipt_rest
       edge8_rest_seal)
  end

  # Sabotage: the happy trace with edge3 (Field -> Motion) silently dropped.
  defp sabotaged_trace, do: List.delete(happy_trace(), "edge3_field_motion")

  # Linear typestate net: one place per vow state
  # (Source Pattern Field Motion Receiver Fruit Receipt Rest), one transition
  # per edge, token = "the vow is in this state". Edge 8 consumes Rest
  # (seal = vow leaves the typestate).
  defp vow_net do
    Art72Conformance.net(
      %{
        "edge1_source_pattern" => %{input: %{"source" => 1}, output: %{"pattern" => 1}},
        "edge2_pattern_field" => %{input: %{"pattern" => 1}, output: %{"field" => 1}},
        "edge3_field_motion" => %{input: %{"field" => 1}, output: %{"motion" => 1}},
        "edge4_motion_receiver" => %{input: %{"motion" => 1}, output: %{"receiver" => 1}},
        "edge5_receiver_fruit" => %{input: %{"receiver" => 1}, output: %{"fruit" => 1}},
        "edge6_fruit_receipt" => %{input: %{"fruit" => 1}, output: %{"receipt" => 1}},
        "edge7_receipt_rest" => %{input: %{"receipt" => 1}, output: %{"rest" => 1}},
        "edge8_rest_seal" => %{input: %{"rest" => 1}, output: %{}}
      },
      %{"source" => 1},
      %{}
    )
  end

  # ── Art72 conformance ─────────────────────────────────────────────────────

  test "happy path scores fitness 1.0 and NO_DRIFT" do
    net = vow_net()
    {c, _stats} = Art72Conformance.log_fitness(net, [happy_trace()])
    assert c == 1.0
    assert Art72Conformance.drift_decision(c, @epsilon) == :NO_DRIFT
  end

  test "edge-4 conservation refusal trace scores < 1.0 and drifts" do
    net = vow_net()
    {c, stats} = Art72Conformance.log_fitness(net, [edge4_refusal_trace()])
    assert c < 1.0
    assert stats.missing > 0
    assert Art72Conformance.drift_decision(c, @epsilon) == :DRIFT
  end

  test "edge-5 balance refusal trace scores < 1.0 and drifts" do
    net = vow_net()
    {c, stats} = Art72Conformance.log_fitness(net, [edge5_refusal_trace()])
    assert c < 1.0
    assert stats.missing > 0
    assert Art72Conformance.drift_decision(c, @epsilon) == :DRIFT
  end

  test "sabotage: a mutated trace (edge skipped) scores < 1.0 / :DRIFT" do
    net = vow_net()
    {c, _stats} = Art72Conformance.log_fitness(net, [sabotaged_trace()])
    assert c < 1.0
    assert Art72Conformance.drift_decision(c, @epsilon) == :DRIFT
  end

  test "mixed log (1 happy + 3 deviant) stays below the drift gate" do
    net = vow_net()
    log = [happy_trace(), edge4_refusal_trace(), edge5_refusal_trace(), sabotaged_trace()]
    {c, _stats} = Art72Conformance.log_fitness(net, log)
    assert c < 1.0
    assert Art72Conformance.drift_decision(c, @epsilon) == :DRIFT
  end

  # ── GallOcel: exact-subset projection only ────────────────────────────────

  # Edges 7-8 are the only vow edges with a semantically exact GALL
  # counterpart: edge7 commits a LineageReceipt (receipt_sealed: receipt,
  # candidate) and edge8 seals the vow from that receipt
  # (checkpoint_promoted: checkpoint, receipt). Object bindings per the
  # GallOcel PRD §40 table.
  defp edge7_observation do
    %{
      name: :receipt_sealed,
      time: "2026-10-13T00:00:00Z",
      objects: %{receipt: "vow-replay-seq-1", candidate: "0xCC-receiver-edge-042"}
    }
  end

  defp edge8_observation do
    %{
      name: :checkpoint_promoted,
      time: "2026-10-13T00:00:01Z",
      objects: %{checkpoint: "vow-mal-3-10", receipt: "vow-replay-seq-1"}
    }
  end

  # Minimal conforming GALL carrier for the edge7 -> edge8 relation. The
  # bare [receipt_sealed, checkpoint_promoted] fragment is REFUSED (see next
  # test): GALL demands the verification closure chain first. The carrier
  # events below are lifecycle scaffolding required by PRD §27/§28 — they are
  # NOT claimed as projections of insa edges 1-6 (those stay vow-native).
  defp gall_carrier do
    base = %{
      checkpoint_admitted: %{checkpoint: "vow-mal-3-10"},
      run_created: %{checkpoint: "vow-mal-3-10", run: "vow-run-1"},
      epoch_created: %{run: "vow-run-1", epoch: "vow-epoch-1"},
      worktree_provisioned: %{epoch: "vow-epoch-1", worker: "vow-worker-1"},
      lease_claimed: %{epoch: "vow-epoch-1", lease: "vow-lease-1", worker: "vow-worker-1"},
      tool_admitted: %{lease: "vow-lease-1"},
      candidate_committed: %{lease: "vow-lease-1", candidate: "0xCC-receiver-edge-042"},
      lease_closed: %{lease: "vow-lease-1", candidate: "0xCC-receiver-edge-042"},
      verification_started: %{
        lease: "vow-lease-1",
        candidate: "0xCC-receiver-edge-042",
        verifier: "vow-verifier-1"
      },
      verification_finished: %{
        lease: "vow-lease-1",
        candidate: "0xCC-receiver-edge-042",
        verifier: "vow-verifier-1"
      }
    }

    for {name, objects} <- base do
      %{name: name, time: "2026-10-13T00:00:00Z", objects: objects}
    end
  end

  test "GallOcel check/1 passes the exact edge 7 -> edge 8 subset on a conforming carrier" do
    trace = gall_carrier() ++ [edge7_observation(), edge8_observation()]
    assert GallOcel.check(trace) == :ok
  end

  test "the bare edge 7 -> edge 8 fragment is refused (verification closure required)" do
    # insa's LineageReceipt commit has no GALL verification predecessor —
    # edges 1-6 are vow-native, not GALL events. The court must say so, never
    # silently admit the fragment.
    assert {:refused, "REFUSED_CONFORMANCE", "receipt_sealed", "verification_finished"} =
             GallOcel.check([edge7_observation(), edge8_observation()])
  end

  test "GallOcel projects the exact subset with authority=none provenance" do
    assert {:ok, %{events: events}} =
             GallOcel.project([edge7_observation(), edge8_observation()])

    for {event, _rels} <- events do
      assert event.attributes["authority"] == "none"
      assert event.attributes["provenance"] == "observation_only"
    end
  end

  test "unmapped vow edges stay vow-native: GallOcel refuses the vocabulary" do
    # Edges 1-6 have no GALL counterpart; forcing them into the GALL log is a
    # category error. The closed vocabulary must refuse them by name.
    for vow_native_name <- [
          "edge1_source_pattern",
          "edge2_pattern_field",
          "edge3_field_motion",
          "edge4_motion_receiver",
          "edge5_receiver_fruit",
          "edge6_fruit_receipt"
        ] do
      assert {:error, {:unknown_event, ^vow_native_name}} =
               GallOcel.check([%{name: vow_native_name, time: "2026-10-13T00:00:00Z"}])
    end

    # ...and the vocabulary is closed: no invented vow-lifecycle event exists.
    refute "vow_admitted" in GallOcel.event_names()
    assert length(GallOcel.event_names()) == 13
  end

  test "a fabricated mapping is refused (inapplicable object identity)" do
    # Fabricating a full-8-edge GALL projection requires inventing bindings
    # the PRD §40 table does not admit — e.g. an epoch identity on
    # receipt_sealed. project/1 must refuse, never silently project.
    fabricated = %{
      name: :receipt_sealed,
      time: "2026-10-13T00:00:00Z",
      objects: %{receipt: "r1", candidate: "c1", epoch: "fabricated-vow-epoch"}
    }

    assert {:error, {:inapplicable_object_identity, :receipt_sealed, :epoch}} =
             GallOcel.project([fabricated])
  end
end
