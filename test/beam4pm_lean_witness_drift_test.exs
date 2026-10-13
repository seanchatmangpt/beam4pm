defmodule BeamPM.LeanWitnessDriftTest do
  @moduledoc """
  Lane L188: mfact's `lean.witness` OcelEvent batch as a new beam4pm event
  family with a proof order law (L181 rank-1 construction).

  Per module the proof process is a fixed order:

      import -> axiom_sweep -> gate -> emit

  where the `gate` node is where the axiom gate (witness axioms are a subset
  of {propext, Classical.choice, Quot.sound}) sits. The law is expressed as
  an Art72 Petri net and checked by token-replay fitness over traces
  constructed from the REAL batch mfact's `scripts/witness_receipt.py
  --ocel` emitted (`test/fixtures/lean_witness_ocel.json`), posted through
  the real `BeamPM.OcelIngest.Router` (in-VM plug pipeline, T9/L94 pattern).

  Mutation courts:

    * swapped axiom_sweep/gate order -> fitness 0.775 -> :DRIFT;
    * a line whose axioms_count implies an extra (non-admitted) axiom
      -> typed refusal at the gate, replayed fitness 2/3 < 1.0.

  Falsifier court (L181): the same well-formed `lean.witness` batch is
  silently admissible at fitness 1.0 on an order-free baseline net — the
  order law is what adds discrimination.
  """

  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias BeamPM.Art72Conformance
  alias BeamPM.OcelIngest.Router

  @trio MapSet.new(["propext", "Classical.choice", "Quot.sound"])
  @max_admitted_axioms MapSet.size(@trio)
  @fixture_path Path.join([__DIR__, "fixtures", "lean_witness_ocel.json"])

  # Proof order law net:
  # start --import--> imported --axiom_sweep--> swept --gate--> gated --emit--> end
  @law_net Art72Conformance.net(
             %{
               "import" => %{input: %{"start" => 1}, output: %{"imported" => 1}},
               "axiom_sweep" => %{input: %{"imported" => 1}, output: %{"swept" => 1}},
               "gate" => %{input: %{"swept" => 1}, output: %{"gated" => 1}},
               "emit" => %{input: %{"gated" => 1}, output: %{"end" => 1}}
             },
             %{"start" => 1},
             %{"end" => 1}
           )

  # Order-free baseline: every activity always enabled, no order constraint.
  # (Token game consumes nothing, so fitness is 1.0 by convention for any
  # ordering -- the honest "no law" model of the L181 falsifier.)
  @law_free_net Art72Conformance.net(
                  %{
                    "import" => %{input: %{}, output: %{}},
                    "axiom_sweep" => %{input: %{}, output: %{}},
                    "gate" => %{input: %{}, output: %{}},
                    "emit" => %{input: %{}, output: %{}}
                  },
                  %{},
                  %{}
                )

  # -- The proof order law ----------------------------------------------------

  defp axiom_gate(%{"axioms_count" => n}) when is_integer(n) and n >= 0 do
    if n <= @max_admitted_axioms, do: :pass, else: {:refuse, :axiom_gate_fail}
  end

  # Per-module proof trace under the law: gate pass -> emit fires; a gate
  # refusal is typed and stops the trace at axiom_sweep.
  defp proof_trace(event) do
    case axiom_gate(event["attributes"]) do
      :pass -> ["import", "axiom_sweep", "gate", "emit"]
      {:refuse, _} = refusal -> {refusal, ["import", "axiom_sweep"]}
    end
  end

  defp conforming?(event) do
    case proof_trace(event) do
      [_ | _] = trace -> {:conforming, trace}
      {refusal, _} -> {:refused, refusal}
    end
  end

  defp law_fitness(events) do
    traces =
      Enum.map(events, fn event ->
        case conforming?(event) do
          {:conforming, trace} -> trace
          {:refused, _} -> elem(proof_trace(event), 1)
        end
      end)

    Art72Conformance.log_fitness(@law_net, traces)
  end

  # -- Fixture -----------------------------------------------------------------

  defp fixture_batch do
    @fixture_path |> File.read!() |> JSON.decode!()
  end

  describe "real batch through the real ingest router" do
    test "the mfact lean.witness batch is admitted end to end and conforms at fitness 1.0" do
      batch = fixture_batch()
      assert length(batch["events"]) == 6

      conn =
        conn(:post, "/ocel/events", JSON.encode!(batch))
        |> put_req_header("content-type", "application/json")
        |> Router.call(Router.init([]))

      assert conn.status == 201
      resp = JSON.decode!(conn.resp_body)
      assert resp["ok"] == true
      assert length(resp["accepted"]) == 6

      # Real admitted records -> proof traces under the law.
      events = Enum.map(resp["accepted"], & &1)
      assert Enum.all?(events, &(&1["event_type"] == "lean.witness"))
      assert Enum.all?(events, fn e -> Enum.any?(e["relationships"], &(&1["qualifier"] == "module")) end)

      {fitness, stats} = law_fitness(events)
      assert fitness == 1.0
      assert stats == %{consumed: 24, produced: 24, missing: 0, remaining: 0}
      assert Art72Conformance.drift_decision(fitness, 0.1) == :NO_DRIFT
    end
  end

  describe "mutation courts" do
    test "swapped axiom_sweep/gate order -> :DRIFT (fitness 0.775, hand-derived)" do
      # import fires; gate underfed (swept missing) -> m+=1, c+=1; sweep and
      # emit fire; at trace end the excess swept token adds to r AND p
      # (replay convention). c=4, p=5, m=1, r=1
      # => C = (1 - 1/4 + 1 - 1/5)/2 = 0.775.
      {fitness, stats} = Art72Conformance.log_fitness(@law_net, [["import", "gate", "axiom_sweep", "emit"]])
      assert stats == %{consumed: 4, produced: 5, missing: 1, remaining: 1}
      assert_in_delta fitness, 0.775, 1.0e-12
      assert Art72Conformance.drift_decision(fitness, 0.1) == :DRIFT
    end

    test "a line whose axioms_count implies failure is refused at the gate (below 1.0 even if replayed)" do
      batch = fixture_batch()

      mutated =
        put_in(batch["events"], [
          hd(batch["events"])
          |> put_in(["attributes", "axioms_count"], @max_admitted_axioms + 1)
        ])

      [event] = mutated["events"]
      assert {:refused, {:refuse, :axiom_gate_fail}} = conforming?(event)

      # Replayed anyway, the refused trace (gate/emit never fire) scores 2/3:
      # c=3, p=3, m=1, r=1 => C = (1 - 1/3 + 1 - 1/3)/2 = 2/3.
      {fitness, stats} = law_fitness(mutated["events"])
      assert stats == %{consumed: 3, produced: 3, missing: 1, remaining: 1}
      assert_in_delta fitness, 2 / 3, 1.0e-12
      assert fitness < 1.0
      assert Art72Conformance.drift_decision(fitness, 0.0) == :DRIFT
    end
  end

  describe "L181 falsifier: the law adds discrimination" do
    test "the same well-formed batch is silently admissible on an order-free net without the law" do
      events = fixture_batch()["events"]
      {lawless_fitness, _} = Art72Conformance.log_fitness(@law_free_net, Enum.map(events, fn _ -> ["import", "gate", "axiom_sweep", "emit"] end))

      # Without the order law, the swapped proof order fits at 1.0: the
      # well-formed lean.witness batch carries NO proof-order bits of its own.
      assert lawless_fitness == 1.0

      # Under the law, the same swap is 0.775 -> DRIFT: the law is the sole
      # source of the discrimination.
      {law_fitness, _} = Art72Conformance.log_fitness(@law_net, [["import", "gate", "axiom_sweep", "emit"]])
      assert_in_delta law_fitness, 0.775, 1.0e-12
      assert Art72Conformance.drift_decision(law_fitness, 0.1) == :DRIFT
    end
  end
end
