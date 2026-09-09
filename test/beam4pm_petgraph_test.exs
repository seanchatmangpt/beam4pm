defmodule BeamPM.PetgraphTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.Petgraph`: real petgraph
  algorithms (A*-as-Dijkstra, Tarjan SCC, topological sort, cycle
  detection) run inside the wasm32-wasip1 engine, exercised for real -- no
  mocks. Absence semantics mirror `BeamPM.Rust4PM`/`BeamPM.Ferroplan`: a
  missing wasm artifact is a NAMED SKIP.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Petgraph

  if not BeamPM.Petgraph.wasm_built?() do
    @moduletag skip: BeamPM.Petgraph.wasm_missing_reason()
  end

  setup do
    {:ok, _pid} = Petgraph.start()
    :ok
  end

  describe "shortest_path" do
    test "real weighted diamond: A->B->D (cost 3) beats A->C->D (cost 10)" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "A", "B", weight: 1.0)
      {:ok, _} = Petgraph.add_edge(h, "B", "D", weight: 2.0)
      {:ok, _} = Petgraph.add_edge(h, "A", "C", weight: 5.0)
      {:ok, _} = Petgraph.add_edge(h, "C", "D", weight: 5.0)

      assert {:ok, %{"path" => ["A", "B", "D"], "cost" => 3.0}} =
               Petgraph.shortest_path(h, "A", "D")
    end

    test "no path when the graph genuinely has none -- an answer, not an error" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_node(h, "island_a")
      {:ok, _} = Petgraph.add_node(h, "island_b")

      assert {:ok, %{"path" => nil, "cost" => nil}} =
               Petgraph.shortest_path(h, "island_a", "island_b")
    end

    test "unknown endpoint names return no-path, not a crash" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "X", "Y")

      assert {:ok, %{"path" => nil, "cost" => nil}} = Petgraph.shortest_path(h, "X", "nonexistent")
    end

    test "negative edge weights are refused, never silently mishandled" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "A", "B", weight: -1.0)

      assert {:error, {:engine, msg}} = Petgraph.shortest_path(h, "A", "B")
      assert msg =~ "non-negative"
    end
  end

  describe "strongly connected components" do
    test "a real 3-cycle plus an isolated node is exactly 2 components" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "P", "Q")
      {:ok, _} = Petgraph.add_edge(h, "Q", "R")
      {:ok, _} = Petgraph.add_edge(h, "R", "P")
      {:ok, _} = Petgraph.add_node(h, "S")

      assert {:ok, %{"components" => components}} = Petgraph.scc(h)
      assert length(components) == 2
      assert Enum.sort(["P", "Q", "R"]) in components
      assert ["S"] in components
    end
  end

  describe "toposort and cycle detection" do
    test "a real DAG topologically sorts with dependencies before dependents" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "compile", "link")
      {:ok, _} = Petgraph.add_edge(h, "link", "test")
      {:ok, _} = Petgraph.add_edge(h, "fetch_deps", "compile")

      assert {:ok, %{"acyclic" => true, "order" => order}} = Petgraph.toposort(h)
      assert index_of(order, "fetch_deps") < index_of(order, "compile")
      assert index_of(order, "compile") < index_of(order, "link")
      assert index_of(order, "link") < index_of(order, "test")

      assert {:ok, %{"cyclic" => false}} = Petgraph.is_cyclic?(h)
    end

    test "a real cycle is reported honestly, not silently broken" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "A", "B")
      {:ok, _} = Petgraph.add_edge(h, "B", "C")
      {:ok, _} = Petgraph.add_edge(h, "C", "A")

      assert {:ok, %{"acyclic" => false, "order" => nil}} = Petgraph.toposort(h)
      assert {:ok, %{"cyclic" => true}} = Petgraph.is_cyclic?(h)
    end
  end

  describe "counts and handle discipline" do
    test "node_count and edge_count report real sizes" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      {:ok, _} = Petgraph.add_edge(h, "A", "B")
      {:ok, _} = Petgraph.add_edge(h, "B", "C")

      assert {:ok, %{"count" => 3}} = Petgraph.node_count(h)
      assert {:ok, %{"count" => 2}} = Petgraph.edge_count(h)
    end

    test "an unknown graph handle is a named engine error, not a crash" do
      assert {:error, {:engine, msg}} = Petgraph.node_count(999_999)
      assert msg =~ "unknown graph handle"
    end

    test "a freed handle cannot be reused" do
      {:ok, %{"handle" => h}} = Petgraph.graph_new()
      assert {:ok, %{"freed" => true}} = Petgraph.free_graph(h)
      assert {:error, {:engine, msg}} = Petgraph.node_count(h)
      assert msg =~ "unknown graph handle"
    end
  end

  defp index_of(list, item), do: Enum.find_index(list, &(&1 == item))
end
