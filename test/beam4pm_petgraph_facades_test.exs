defmodule BeamPM.PetgraphFacadesTest do
  @moduledoc """
  Facade-parity qualification for the two thin BEAM facades over the ONE
  petgraph wasm engine (`src/beam4pm_petgraph.erl`,
  `gleam/src/beam4pm/petgraph.gleam`), same shape as
  `BeamPM.FerroplanFacadesTest`: every op called through Elixir, Erlang,
  and Gleam on the SAME shared graph handle, asserting exact `==` parity
  plus real content checks. Named skip when the wasm artifact or the
  gleam build output is absent.
  """

  use ExUnit.Case, async: false

  if not BeamPM.Petgraph.wasm_built?() do
    @moduletag skip: BeamPM.Petgraph.wasm_missing_reason()
  end

  @gleam_ebin Path.expand("gleam/build/dev/erlang/beam4pm/ebin")
  @gleam_mod :beam4pm@petgraph
  defp gleam(fun, args), do: apply(@gleam_mod, fun, args)

  setup_all do
    {:ok, engine_pid} = BeamPM.Petgraph.start()

    if File.exists?(@gleam_ebin) do
      true = Code.append_path(@gleam_ebin)
    end

    {:ok, %{"handle" => graph_h}} = BeamPM.Petgraph.graph_new()
    {:ok, _} = BeamPM.Petgraph.add_edge(graph_h, "A", "B", weight: 1.0)
    {:ok, _} = BeamPM.Petgraph.add_edge(graph_h, "B", "D", weight: 2.0)
    {:ok, _} = BeamPM.Petgraph.add_edge(graph_h, "A", "C", weight: 5.0)
    {:ok, _} = BeamPM.Petgraph.add_edge(graph_h, "C", "D", weight: 5.0)

    %{engine_pid: engine_pid, graph_h: graph_h}
  end

  describe "erlang facade (:beam4pm_petgraph, src/beam4pm_petgraph.erl)" do
    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = :beam4pm_petgraph.start()
      assert pid == ctx.engine_pid
    end

    test "shortest_path/3 matches the elixir wrapper's real answer", ctx do
      elixir_result = BeamPM.Petgraph.shortest_path(ctx.graph_h, "A", "D")
      erlang_result = :beam4pm_petgraph.shortest_path(ctx.graph_h, "A", "D")
      assert erlang_result == elixir_result
      assert {:ok, %{"path" => ["A", "B", "D"], "cost" => 3.0}} = erlang_result
    end

    test "scc/1 matches the elixir wrapper on a real 3-cycle" do
      {:ok, %{"handle" => h}} = BeamPM.Petgraph.graph_new()
      {:ok, _} = BeamPM.Petgraph.add_edge(h, "P", "Q")
      {:ok, _} = BeamPM.Petgraph.add_edge(h, "Q", "R")
      {:ok, _} = BeamPM.Petgraph.add_edge(h, "R", "P")

      elixir_result = BeamPM.Petgraph.scc(h)
      erlang_result = :beam4pm_petgraph.scc(h)
      assert erlang_result == elixir_result
      assert {:ok, %{"components" => [["P", "Q", "R"]]}} = erlang_result
    end

    test "toposort/1 and is_cyclic/1 match the elixir wrapper on a real cycle" do
      {:ok, %{"handle" => h}} = BeamPM.Petgraph.graph_new()
      {:ok, _} = BeamPM.Petgraph.add_edge(h, "A", "B")
      {:ok, _} = BeamPM.Petgraph.add_edge(h, "B", "A")

      assert :beam4pm_petgraph.toposort(h) == BeamPM.Petgraph.toposort(h)
      assert :beam4pm_petgraph.is_cyclic(h) == BeamPM.Petgraph.is_cyclic?(h)
      assert {:ok, %{"cyclic" => true}} = :beam4pm_petgraph.is_cyclic(h)
    end

    test "node_count/1, edge_count/1, and free_graph/1 parity" do
      {:ok, %{"handle" => h}} = BeamPM.Petgraph.graph_new()
      {:ok, _} = BeamPM.Petgraph.add_edge(h, "X", "Y")

      assert :beam4pm_petgraph.node_count(h) == BeamPM.Petgraph.node_count(h)
      assert :beam4pm_petgraph.edge_count(h) == BeamPM.Petgraph.edge_count(h)

      elixir_free = BeamPM.Petgraph.free_graph(h)
      assert {:ok, %{"freed" => true}} = elixir_free

      erlang_double_free = :beam4pm_petgraph.free_graph(h)
      elixir_double_free = BeamPM.Petgraph.free_graph(h)
      assert erlang_double_free == elixir_double_free
      assert {:error, {:engine, msg}} = erlang_double_free
      assert msg =~ "unknown graph handle"
    end
  end

  describe "gleam facade (:beam4pm@petgraph, gleam/src/beam4pm/petgraph.gleam)" do
    if not File.exists?(Path.expand("gleam/build/dev/erlang/beam4pm/ebin")) do
      @describetag skip: "gleam facade not built -- run (cd gleam && gleam build) first"
    end

    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = gleam(:start, [])
      assert pid == ctx.engine_pid
    end

    test "shortest_path/3 matches the elixir wrapper's real answer", ctx do
      elixir_result = BeamPM.Petgraph.shortest_path(ctx.graph_h, "A", "D")
      gleam_result = gleam(:shortest_path, [ctx.graph_h, "A", "D"])
      assert gleam_result == elixir_result
    end

    test "no-path is a real answer on both sides, not an error" do
      {:ok, %{"handle" => h}} = BeamPM.Petgraph.graph_new()
      {:ok, _} = BeamPM.Petgraph.add_node(h, "island_a")
      {:ok, _} = BeamPM.Petgraph.add_node(h, "island_b")

      elixir_result = BeamPM.Petgraph.shortest_path(h, "island_a", "island_b")
      gleam_result = gleam(:shortest_path, [h, "island_a", "island_b"])
      assert gleam_result == elixir_result
      assert {:ok, %{"path" => nil, "cost" => nil}} = gleam_result
    end

    test "toposort/1 matches the elixir wrapper on a real DAG", ctx do
      elixir_result = BeamPM.Petgraph.toposort(ctx.graph_h)
      gleam_result = gleam(:toposort, [ctx.graph_h])
      assert gleam_result == elixir_result
      assert {:ok, %{"acyclic" => true}} = gleam_result
    end

    test "free_graph/1 on a private handle, unknown-handle refusal parity" do
      {:ok, %{"handle" => h}} = BeamPM.Petgraph.graph_new()
      assert {:ok, %{"freed" => true}} = BeamPM.Petgraph.free_graph(h)

      elixir_result = BeamPM.Petgraph.node_count(h)
      gleam_result = gleam(:node_count, [h])
      assert gleam_result == elixir_result
      assert {:error, {:engine, _msg}} = gleam_result
    end
  end
end
