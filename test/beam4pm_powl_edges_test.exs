defmodule BeamPM.PowlEdgesTest do
  @moduledoc """
  Lane W4 tests: the POWL data edge (engine serde map <-> typed structs),
  the HDDL -> POWL and FOND -> POWL converters, and the OCEL accumulator's
  pure paths. Engine-backed tests (real wasm calls) live in
  `BeamPM.PowlEdgesEngineTest` at the bottom of this file.

  ANTI-VACUITY is structural here: the "roundtrip distinguishes a mutated
  model" test feeds a deliberately mutated model through the same pipeline
  and requires the comparator to SEE the mutation, so a parser that
  silently drops child order cannot pass this suite.
  """

  use ExUnit.Case, async: true

  alias BeamPM.Powl.Model
  alias BeamPM.Powl.FondPowl
  alias BeamPM.Powl.HddlPowl
  alias BeamPM.Types.PowlChoiceGraphEdge
  alias BeamPM.Types.PowlChoiceOperator
  alias BeamPM.Types.PowlFreq
  alias BeamPM.Types.PowlLeaf
  alias BeamPM.Types.PowlLoopOperator
  alias BeamPM.Types.PowlParallelOperator
  alias BeamPM.Types.PowlPartialOrderEdge
  alias BeamPM.Types.PowlPartialOrderPlan
  alias BeamPM.Types.PowlSequenceOperator

  # A golden model in the DISCOVERED engine serde shape exercising every
  # PowlNode variant: ChoiceGraph root with a Sequence operator child (with
  # a Tau leaf + PartialOrder child carrying order edges), a non-Tau leaf,
  # a self-loop edge (POWL 1.0-style loop), a null max_freq, and a bounded
  # freq.
  @golden %{
    "root" => %{
      "ChoiceGraph" => %{
        "children" => [
          %{
            "Operator" => %{
              "operator_type" => "Sequence",
              "children" => [
                %{"Leaf" => %{"leaf" => %{"activity_label" => "Tau"}, "freq" => %{"min_freq" => 0, "max_freq" => nil}}},
                %{
                  "PartialOrder" => %{
                    "children" => [
                      %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "approve"}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}}},
                      %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "pay"}}, "freq" => %{"min_freq" => 1, "max_freq" => 3}}}
                    ],
                    "order" => [[0, 1]],
                    "freq" => %{"min_freq" => 1, "max_freq" => 1}
                  }
                }
              ],
              "freq" => %{"min_freq" => 1, "max_freq" => 1}
            }
          },
          %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "file"}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}}}
        ],
        "edges" => [
          ["Start", %{"Child" => 0}],
          [%{"Child" => 0}, %{"Child" => 0}],
          [%{"Child" => 0}, %{"Child" => 1}],
          [%{"Child" => 1}, "End"]
        ],
        "freq" => %{"min_freq" => 1, "max_freq" => 1}
      }
    }
  }

  # ---------------------------------------------------------------------
  # Parser: from_engine_map produces the admitted typed structs
  # ---------------------------------------------------------------------

  test "from_engine_map parses every variant into typed Powl* structs" do
    {:ok, model} = Model.from_engine_map(@golden)
    root = model.root

    assert %Model.Node{variant: :choice_graph} = root
    assert %PowlFreq{min_freq: 1, max_freq: 1} = root.freq

    # edge endpoints flattened into the admitted PowlChoiceGraphEdge shape
    assert [
             %PowlChoiceGraphEdge{from_kind: :start, from_child_index: nil, to_kind: :child, to_child_index: 0},
             %PowlChoiceGraphEdge{from_kind: :child, from_child_index: 0, to_kind: :child, to_child_index: 0},
             %PowlChoiceGraphEdge{from_kind: :child, from_child_index: 0, to_kind: :child, to_child_index: 1},
             %PowlChoiceGraphEdge{from_kind: :child, from_child_index: 1, to_kind: :end, to_child_index: nil}
           ] = root.edges

    [seq_op, file_leaf] = root.children

    # Operator -> PowlSequenceOperator (typed producer for the digests-only struct)
    assert %Model.Node{variant: :operator} = seq_op
    assert %PowlSequenceOperator{operator_id: "powl-op-" <> _, step_digest: nil, predecessor_digest: nil} = seq_op.operator

    # Sequence children: Tau leaf + PartialOrder
    [tau_leaf, po] = seq_op.children
    assert %PowlLeaf{activity_label: nil, is_tau: true, min_freq: 0, max_freq: nil} = tau_leaf.leaf

    assert %Model.Node{variant: :partial_order} = po

    assert [%PowlPartialOrderEdge{from_index: 0, to_index: 1}] = po.order

    [approve, pay] = po.children
    assert %PowlLeaf{activity_label: "approve", is_tau: false, min_freq: 1, max_freq: 1} = approve.leaf
    assert %PowlLeaf{activity_label: "pay", is_tau: false, min_freq: 1, max_freq: 3} = pay.leaf

    assert %PowlLeaf{activity_label: "file", is_tau: false} = file_leaf.leaf
  end

  test "from_engine_map accepts the full engine result map (unwraps \"powl\") and atom keys" do
    assert {:ok, _} = Model.from_engine_map(%{"powl" => @golden})

    atom_golden = %{
      root: %{
        ChoiceGraph: %{
          children: [
            %{Leaf: %{leaf: %{activity_label: %{:Activity => "a"}}, freq: %{min_freq: 1, max_freq: 1}}}
          ],
          edges: [[:Start, %{Child: 0}], [%{:Child => 0}, :End]],
          freq: %{min_freq: 1, max_freq: 1}
        }
      }
    }

    assert {:ok, model} = Model.from_engine_map(atom_golden)
    assert %Model.Node{variant: :choice_graph} = model.root
  end

  test "Loop parses into PowlLoopOperator with a null max_freq carried through" do
    model = %{
      "root" => %{
        "Operator" => %{
          "operator_type" => "Loop",
          "children" => [
            %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "do"}}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}},
            %{"Leaf" => %{"leaf" => %{"activity_label" => "Tau"}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}}
          ],
          "freq" => %{"min_freq" => 1, "max_freq" => nil}
        }
      }
    }

    assert {:ok, %{root: root}} = Model.from_engine_map(model)
    assert %Model.Node{variant: :operator, operator: %PowlLoopOperator{}} = root
    assert %PowlFreq{max_freq: nil} = root.freq
  end

  test "Concurrency/ExclusiveChoice parse to PowlParallelOperator/PowlChoiceOperator" do
    for {type, expected} <- [
          {"Concurrency", PowlParallelOperator},
          {"ExclusiveChoice", PowlChoiceOperator}
        ] do
      model = %{
        "root" => %{
          "Operator" => %{
            "operator_type" => type,
            "children" => [
              %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "x"}}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}}
            ],
            "freq" => %{"min_freq" => 1, "max_freq" => 1}
          }
        }
      }

      {:ok, %{root: root}} = Model.from_engine_map(model)
      assert %Model.Node{operator: op_struct} = root
      assert op_struct.__struct__ == expected
    end
  end

  # ---------------------------------------------------------------------
  # Parser: lossless byte-identical roundtrip
  # ---------------------------------------------------------------------

  test "to_engine_map . from_engine_map is byte-identical (canonical key-sorted JSON)" do
    {:ok, model} = Model.from_engine_map(@golden)

    forward = Model.encode_canonical(Model.to_engine_map(model))

    # Byte-identical losslessness through the WIRE FORM: the emitted map
    # reparses and re-emits identically. (The emission shape itself is
    # pinned by the real engine serde -- see the engine-discovered
    # roundtrip test -- not by @golden's hand-authored layout.)
    {:ok, model_from_wire} = Model.from_engine_map(Model.to_engine_map(model))
    assert forward == Model.encode_canonical(Model.to_engine_map(model_from_wire))

    # roundtrip the ROUNDTRIP too: reparse the emitted map, re-emit, still identical
    {:ok, model2} = Model.from_engine_map(Model.to_engine_map(model))
    assert Model.encode_canonical(Model.to_engine_map(model2)) == forward
  end

  test "roundtrip preserves engine-emitted BTreeSet edge/order order verbatim" do
    # deliberately NOT engine-canonical edge order: the parser preserves
    # arrival order rather than re-sorting (the engine itself always emits
    # sorted BTreeSets; preserving arrival order makes the roundtrip an
    # identity over whatever the engine sent).
    # Shape matches the REAL engine serde (witnessed via ocel_discover_powl
    # 2026-09-27: bare Leaf structs, exactly-once freq omitted). Only the
    # edge ARRIVAL order is deliberately non-engine-canonical.
    shuffled = %{
      "root" => %{
        "ChoiceGraph" => %{
          "children" => [
            %{"Leaf" => %{"activity_label" => %{"Activity" => "a"}}},
            %{"Leaf" => %{"activity_label" => %{"Activity" => "b"}}}
          ],
          "edges" => [[%{"Child" => 1}, "End"], ["Start", %{"Child" => 1}], ["Start", %{"Child" => 0}], [%{"Child" => 0}, "End"]]
        }
      }
    }

    {:ok, model} = Model.from_engine_map(shuffled)
    assert Model.encode_canonical(Model.to_engine_map(model)) == Model.encode_canonical(shuffled)
  end

  test "ANTI-VACUITY: the comparator sees a mutated model (swapped sequence child order)" do
    # The permanent tripwire: run the SAME roundtrip pipeline over a
    # deliberately mutated model and require the canonical forms to
    # DIFFER. If the parser/serializer ever dropped or normalized child
    # order, this refutation would fail -- and so would the byte-identical
    # roundtrip assertion above.
    {:ok, golden_model} = Model.from_engine_map(@golden)

    mutated =
      put_in(
        @golden["root"]["ChoiceGraph"]["children"],
        Enum.reverse(@golden["root"]["ChoiceGraph"]["children"])
      )

    {:ok, mutated_model} = Model.from_engine_map(mutated)

    golden_canonical = Model.encode_canonical(Model.to_engine_map(golden_model))
    mutated_canonical = Model.encode_canonical(Model.to_engine_map(mutated_model))

    refute golden_canonical == mutated_canonical,
           "comparator is vacuous: a swapped-child mutation was not detected"

    # and the mutation is exactly at the swapped position (edge tail preserved)
    assert String.contains?(mutated_canonical, "file")
    assert String.contains?(golden_canonical, "file")
  end

  # ---------------------------------------------------------------------
  # validate/1: engine-parallel structural sanity
  # ---------------------------------------------------------------------

  test "validate/1 accepts the golden model" do
    {:ok, model} = Model.from_engine_map(@golden)
    assert Model.validate(model) == :ok
  end

  test "validate/1 refuses a Loop with fewer than two children (engine arity)" do
    assert {:error, {:loop_needs_two_children, 1}} = loop_model(1) |> Model.validate()
    assert :ok = loop_model(2) |> Model.validate()
  end

  test "validate/1 refuses out-of-range, reflexive and antisymmetric-violating order edges" do
    {:ok, out_of_range} = po_model([[0, 1], [1, 5]])
    assert {:error, {:order_index_out_of_range, _, 2}} = Model.validate(out_of_range)

    {:ok, reflexive} = po_model([[0, 0]])
    assert {:error, {:order_not_irreflexive, {0, 0}}} = Model.validate(reflexive)

    {:ok, both} = po_model([[0, 1], [1, 0]])
    assert {:error, {:order_not_antisymmetric, _}} = Model.validate(both)
  end

  test "validate/1 refuses freq max < min" do
    model = %{
      "root" => %{
        "Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "a"}}, "freq" => %{"min_freq" => 3, "max_freq" => 1}}
      }
    }

    {:ok, typed} = Model.from_engine_map(model)
    assert {:error, {:invalid_freq_bounds, {3, 1}}} = Model.validate(typed)
  end

  test "validate/1 refuses a child not on any Start->End path and a Start with incoming edge" do
    # child 1 has no path to End
    model = %{
      "root" => %{
        "ChoiceGraph" => %{
          "children" => [
            leaf_node("a"),
            leaf_node("b")
          ],
          "edges" => [["Start", %{"Child" => 0}], [%{"Child" => 0}, "End"], ["Start", %{"Child" => 1}]],
          "freq" => %{"min_freq" => 1, "max_freq" => 1}
        }
      }
    }

    {:ok, typed} = Model.from_engine_map(model)
    assert {:error, {:child_not_on_start_end_path, 1}} = Model.validate(typed)

    # Start with an incoming edge
    model2 =
      put_in(model["root"]["ChoiceGraph"]["edges"], [
        ["Start", %{"Child" => 0}],
        [%{"Child" => 0}, "End"],
        [%{"Child" => 1}, "Start"],
        [%{"Child" => 1}, "End"]
      ])

    {:ok, typed2} = Model.from_engine_map(model2)
    assert {:error, {:start_has_incoming_edge, :start}} = Model.validate(typed2)
  end

  test "from_engine_map refuses a missing root and an unknown variant with typed errors" do
    assert {:error, {:missing_field, :root}} = Model.from_engine_map(%{"nope" => %{}})
    assert {:error, {:unknown_node_variant, _}} = Model.from_engine_map(%{"root" => %{"Wedge" => %{}}})
    assert {:error, {:invalid_model, "x"}} = Model.from_engine_map("x")
    assert {:error, {:unknown_operator_type, "Xor"}} =
             Model.from_engine_map(%{
               "root" => %{
                 "Operator" => %{
                   "operator_type" => "Xor",
                   "children" => [],
                   "freq" => %{"min_freq" => 1, "max_freq" => 1}
                 }
               }
             })
             |> elem(1)
             |> elem(1)
  end

  # ---------------------------------------------------------------------
  # HDDL -> POWL
  # ---------------------------------------------------------------------

  test "from_network produces a PowlPartialOrderPlan with deterministic content digests" do
    network = %{tasks: ["open", "clean_house", "close"], ordering: [{0, 1}, {1, 2}]}

    {:ok, %PowlPartialOrderPlan{} = plan} = HddlPowl.from_network(network)

    assert plan.plan_id =~ ~r/^hddl-plan-[0-9a-f]{16}$/
    assert is_binary(plan.operator_digest) and is_binary(plan.order_digest)

    # determinism: same structure -> identical plan (byte-identical digest set)
    {:ok, plan_again} = HddlPowl.from_network(network)
    assert plan == plan_again

    # sensitivity: changed order -> changed order_digest (falsifier for a
    # constant-digest fake); changed tasks -> changed operator_digest
    {:ok, reordered} = HddlPowl.from_network(tasks: ["open", "clean_house", "close"], ordering: [{0, 2}, {1, 2}])
    assert reordered.order_digest != plan.order_digest

    {:ok, renamed} = HddlPowl.from_network(tasks: ["open", "scrub", "close"], ordering: [{0, 1}, {1, 2}])
    assert renamed.operator_digest != plan.operator_digest
    assert renamed.order_digest == plan.order_digest
  end

  test "from_network's order_digest is computed over the TRANSITIVE CLOSURE (engine-parallel)" do
    base = %{tasks: ["a", "b", "c"], ordering: [{0, 1}, {1, 2}]}
    explicit_closed = %{tasks: ["a", "b", "c"], ordering: [{0, 1}, {1, 2}, {0, 2}]}

    {:ok, p1} = HddlPowl.from_network(base)
    {:ok, p2} = HddlPowl.from_network(explicit_closed)

    # same closed relation -> same digest, even though the given edge sets differ
    assert p1.order_digest == p2.order_digest
  end

  test "build_partial_order builds validated typed POWL nodes" do
    {:ok, %{node: node, tasks: tasks}} =
      HddlPowl.build_partial_order(%{tasks: ["a", "b"], ordering: [{1, 0}]})

    assert tasks == ["a", "b"]
    # Children are the wrapped Node variants: Model.validate/1 and the
    # engine emitters operate on Model.Node.t(), not bare leaves.
    assert [
             %Model.Node{variant: :leaf, leaf: %PowlLeaf{activity_label: "a"}},
             %Model.Node{variant: :leaf, leaf: %PowlLeaf{activity_label: "b"}}
           ] = node.children
    assert [%PowlPartialOrderEdge{from_index: 1, to_index: 0}] = node.order
    assert Model.validate(node) == :ok

    # the built node round-trips through the engine serde shape
    engine = Model.to_engine_map(node)
    assert %{"PartialOrder" => %{"order" => [[1, 0]]}} = engine
    {:ok, reparsed} = Model.from_engine_map(%{"root" => engine})

    # like-for-like: reparsed (a %Model{}) emits the %{"root" => ...} form;
    # unwrap it before comparing against the bare node map `engine`.
    assert Model.encode_canonical(Map.fetch!(Model.to_engine_map(reparsed), "root")) ==
             Model.encode_canonical(engine)
  end

  test "from_network refuses antisymmetric, irreflexive and out-of-range orders with typed errors" do
    assert {:error, {:order_not_antisymmetric, {0, 1}}} =
             HddlPowl.from_network(%{tasks: ["a", "b"], ordering: [{0, 1}, {1, 0}]})

    assert {:error, {:order_not_irreflexive, {1, 1}}} =
             HddlPowl.from_network(%{tasks: ["a", "b"], ordering: [{1, 1}]})

    assert {:error, {:order_index_out_of_range, {0, 2}, 2}} =
             HddlPowl.from_network(%{tasks: ["a", "b"], ordering: [{0, 2}]})

    assert {:error, {:invalid_field, :empty_tasks}} = HddlPowl.from_network(%{tasks: [], ordering: []})
  end

  # ---------------------------------------------------------------------
  # FOND -> POWL
  # ---------------------------------------------------------------------

  test "from_policy_outcomes builds one choice graph per state, branches as edges" do
    {:ok, %{root: root, choices: choices}} =
      FondPowl.from_policy_outcomes(%{review: [:negative, :positive]})

    assert [%{key: "review", operator: op, node: node}] = choices

    assert %PowlChoiceOperator{operator_id: "fond-choice-" <> _, branch_digest: d, selection_rule: "fond_outcome_branches"} =
             op

    assert is_binary(d)

    assert %Model.Node{variant: :choice_graph, children: children, edges: edges} = node
    assert root == node

    # branch leaves named key/outcome, sorted deterministically
    assert [
             %Model.Node{variant: :leaf, leaf: %PowlLeaf{activity_label: "review/negative"}},
             %Model.Node{variant: :leaf, leaf: %PowlLeaf{activity_label: "review/positive"}}
           ] = children

    # exclusive-choice edge shape: Start->Child(i) and Child(i)->End, no child-child edges
    assert [
             %PowlChoiceGraphEdge{from_kind: :start, to_kind: :child, to_child_index: 0},
             %PowlChoiceGraphEdge{from_kind: :start, to_kind: :child, to_child_index: 1},
             %PowlChoiceGraphEdge{from_kind: :child, from_child_index: 0, to_kind: :end},
             %PowlChoiceGraphEdge{from_kind: :child, from_child_index: 1, to_kind: :end}
           ] = edges

    assert Model.validate(node) == :ok

    # round-trips through the engine serde shape
    engine = Model.to_engine_map(node)
    assert %{"ChoiceGraph" => %{}} = engine
    {:ok, reparsed} = Model.from_engine_map(%{"root" => engine})

    # like-for-like: reparsed (a %Model{}) emits the %{"root" => ...} form;
    # unwrap it before comparing against the bare node map `engine`.
    assert Model.encode_canonical(Map.fetch!(Model.to_engine_map(reparsed), "root")) ==
             Model.encode_canonical(engine)
  end

  test "multiple states compose under a Sequence in sorted-key order (deterministic)" do
    input_a = %{zebra: [:positive], alpha: [:negative, :inconclusive]}
    {:ok, %{root: root, choices: choices}} = FondPowl.from_policy_outcomes(input_a)

    assert Enum.map(choices, & &1.key) == ["alpha", "zebra"]
    assert %Model.Node{variant: :operator, operator: %PowlSequenceOperator{}} = root
    assert length(root.children) == 2
    assert Model.validate(root) == :ok

    # map insertion order must not matter
    input_b = %{alpha: [:negative, :inconclusive], zebra: [:positive]}
    {:ok, %{root: root2}} = FondPowl.from_policy_outcomes(input_b)
    assert Model.encode_canonical(Model.to_engine_map(root)) == Model.encode_canonical(Model.to_engine_map(root2))
  end

  test "from_policy_outcomes refuses unknown outcomes and empty branch sets (typed)" do
    # :weird is NOT in BeamPM.Dfcm.fond_outcomes/0 -> refused, not widened
    assert {:error, {:unknown_outcome, "review", :weird}} =
             FondPowl.from_policy_outcomes(%{review: [:positive, :weird]})

    assert {:error, {:empty_outcomes, "review"}} = FondPowl.from_policy_outcomes(%{review: []})
    assert {:error, {:invalid_policy_outcomes, %{}}} = FondPowl.from_policy_outcomes(%{})
    assert {:error, {:invalid_policy_outcomes, "x"}} = FondPowl.from_policy_outcomes("x")
  end

  test "branch_digest is deterministic and branch-set sensitive" do
    {:ok, %{choices: [c1]}} = FondPowl.from_policy_outcomes(%{s: [:positive, :negative]})
    {:ok, %{choices: [c2]}} = FondPowl.from_policy_outcomes(%{s: [:positive, :negative]})
    {:ok, %{choices: [c3]}} = FondPowl.from_policy_outcomes(%{s: [:positive, :negative, :inconclusive]})

    assert c1.operator.branch_digest == c2.operator.branch_digest
    assert c1.operator.branch_digest != c3.operator.branch_digest
  end

  # ---------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------

  defp leaf_node(label) do
    %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => label}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}}}
  end

  defp loop_model(n_children) do
    children =
      for i <- 1..n_children do
        %{"Leaf" => %{"leaf" => %{"activity_label" => %{"Activity" => "l#{i}"}}, "freq" => %{"min_freq" => 1, "max_freq" => 1}}}
      end

    %{
      "root" => %{
        "Operator" => %{
          "operator_type" => "Loop",
          "children" => children,
          "freq" => %{"min_freq" => 1, "max_freq" => 1}
        }
      }
    }
  end

  defp po_model(pairs) do
    Model.from_engine_map(%{
      "root" => %{
        "PartialOrder" => %{
          "children" => [leaf_node("a"), leaf_node("b")],
          "order" => pairs,
          "freq" => %{"min_freq" => 1, "max_freq" => 1}
        }
      }
    })
  end
end

defmodule BeamPM.PowlEdgesEngineTest do
  @moduledoc """
  Real-engine tests (real rust4pm wasm calls, no mocks): the accumulator's
  ingest -> handle -> ocel_variants_of_object_type smoke, and parsing a
  REAL engine-discovered POWL (ocel_discover_powl) through
  `BeamPM.Powl.Model` -- the exact edge this lane exists for. async: false
  because the wasm engine is one named process shared by the whole suite.
  """

  use ExUnit.Case, async: false

  alias BeamPM.OcelAccumulator
  alias BeamPM.Powl.Model
  alias BeamPM.Rust4PM
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  @moduletag :wasm_engine

  setup_all do
    if Rust4PM.wasm_built?() do
      case Rust4PM.start() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        other -> {:skip, "engine start failed: #{inspect(other)}"}
      end
    else
      {:skip, Rust4PM.wasm_missing_reason()}
    end
  end

  defp rel(object_id, qualifier), do: %OcelRelationship{object_id: object_id, qualifier: qualifier}

  defp event(id, type, time, rels), do: {%OcelEvent{event_id: id, event_type: type, event_time: time, attributes: nil}, rels}

  defp object(id, type, rels), do: {%OcelObject{object_id: id, object_type: type, attributes: nil}, rels}

  defp ts(minute), do: "2026-01-01T10:00:" <> String.pad_leading(Integer.to_string(minute), 2, "0") <> "+00:00"

  test "accumulator: ingest -> handle -> real ocel_variants_of_object_type" do
    start_supervised!(OcelAccumulator)
    :ok = OcelAccumulator.reset()

    objects = [
      object("o-1", "meeting", []),
      object("o-2", "meeting", [])
    ]

    events = [
      event("e-1", "open", ts(0), [rel("o-1", "participates")]),
      event("e-2", "close", ts(2), [rel("o-1", "participates")]),
      event("e-3", "open", ts(3), [rel("o-2", "participates")]),
      event("e-4", "close", ts(5), [rel("o-2", "participates")])
    ]

    assert {:ok, %{events: 4, objects: 2}} = OcelAccumulator.ingest(events, objects)
    assert %{events: 4, objects: 2} = OcelAccumulator.counts()

    # events() sorted by event_id, real OcelEvent structs with rels
    assert [%OcelEvent{event_id: "e-1"} | _] = Enum.map(OcelAccumulator.events(), fn {e, _} -> e end)

    # duplicate id -> whole call refused, nothing written
    assert {:error, {:duplicate_record, {:event, "e-1"}}} =
             OcelAccumulator.ingest([event("e-1", "open", ts(9), [])], [])

    assert %{events: 4, objects: 2} = OcelAccumulator.counts()

    # build a REAL engine handle (never cached -- a fresh one per call)
    assert {:ok, handle1} = OcelAccumulator.to_engine_handle()
    assert {:ok, handle2} = OcelAccumulator.to_engine_handle()

    assert {:ok, %{"variants" => variants, "num_variants" => 1}} =
             Rust4PM.ocel_variants_of_object_type(handle1, "meeting")

    # both objects followed the same open->close variant
    assert [%{"activities" => ["open", "close"], "count" => 2}] = variants

    for h <- [handle1, handle2], do: {:ok, _} = Rust4PM.free_ocel(h)

    # dangling e2o -> typed refusal at build time, engine never called
    :ok = OcelAccumulator.reset()

    assert {:ok, _} =
             OcelAccumulator.ingest(
               [event("e-9", "open", ts(0), [rel("o-missing", "participates")])],
               []
             )

    assert {:error, {:dangling_relationships, [{{:event, "e-9"}, "o-missing"}]}} =
             OcelAccumulator.to_engine_handle()
  end

  test "REAL engine-discovered POWL parses into typed structs and round-trips" do
    {:ok, %{"ocel_handle" => h}} = Rust4PM.ocel_new()

    phases = ["open", "trust_god", "close"]
    {:ok, _} = Rust4PM.ocel_add_object_type(h, "meeting")

    for phase <- phases, do: {:ok, _} = Rust4PM.ocel_add_event_type(h, phase)

    for {id, base} <- [{"g1", 10}, {"g2", 11}] do
      {:ok, _} = Rust4PM.ocel_add_object(h, id, "meeting")

      phases
      |> Enum.with_index()
      |> Enum.each(fn {phase, idx} ->
        time = "2026-01-01T" <> String.pad_leading(Integer.to_string(base), 2, "0") <> ":0" <> Integer.to_string(idx) <> ":00+00:00"
        {:ok, _} = Rust4PM.ocel_add_event(h, "e_#{id}_#{phase}", phase, time, [[id, "meeting"]])
      end)
    end

    assert {:ok, %{"powl" => powl}} = Rust4PM.ocel_discover_powl(h, "meeting")
    assert %{"root" => _} = powl

    # the actual edge: opaque engine map -> typed structs -> validate -> roundtrip
    assert {:ok, model} = Model.from_engine_map(powl)
    assert Model.validate(model) == :ok

    emitted = Model.to_engine_map(model)
    assert Model.encode_canonical(emitted) == Model.encode_canonical(powl)

    {:ok, _} = Rust4PM.free_ocel(h)
  end
end
