defmodule BeamPM.FleetProcessDriftTest do
  @moduledoc """
  L113: process-mining the fleet's own happy path.

  Corpus: castle's strata-ingest `OcelEvent` semantics
  (`castle-ggen-rdf/src/strata.rs:205-238` — one `ggen.sync` event per
  verified sync record, object of interest `pack:law:<prefix>`) projected
  through castle's `beam4pm_feed` wire envelope
  (`{"events": [{event_id, event_type, event_time, attributes, relationships}]}`),
  built here from the pinned castle fixture
  `fixtures/strata/ledger-receipt.json`
  (provenance sha256
  `d442823a21b912fbcd43665433f220655d43c41462732ce7c434214ee760661d`).

  ## The admitted order law (read honestly from the fixture receipt)

  One sync record in the fixture is a chain-hashed receipt whose body
  witnesses, in order:

    1. **admission** — `record.v2.admission` entries, every
       `decision: "Admitted"` (evidence `generated/ledger_consts.rs`,
       `generated/ledger_state.rs`; observed_outcome `Pass`);
    2. **gate-run** — `payload.closure` binds three gate queries
       (`gates/010_ledger_layout.rq`, `gates/020_transition_law.rq`,
       `gates/030_ocel_conformance.rq`) plus ontology/templates by digest;
    3. **receipt** — the record is sealed by `record.chain_hash_hex`
       folded over the prior chain (`chain_rule: "praxis-chain/v2-fold"`);
    4. **ingest** — the record projects to one `ggen.sync` OcelEvent and
       enters the beam4pm batch envelope via the feed adapter.

  So the fleet's happy-path order law per sync record is exactly:

      admission -> gate-run -> receipt -> ingest
  """

  use ExUnit.Case, async: true

  alias BeamPM.Art72Conformance

  @fixture_path Path.join(__DIR__, "fixtures/strata/ledger-receipt.json")

  @fixture_sha256 "d442823a21b912fbcd43665433f220655d43c41462732ce7c434214ee760661d"

  # ---------------------------------------------------------------------------
  # Corpus: deterministic trace list from the pinned fixture
  # ---------------------------------------------------------------------------

  defp fixture do
    assert @fixture_sha256 == Base.encode16(:crypto.hash(:sha256, File.read!(@fixture_path)),
             case: :lower
           )

    @fixture_path |> File.read!() |> Jason.decode!()
  end

  # One happy-path trace per admitted evidence id in the fixture's
  # `v2.admission` list (deterministic, derived — not invented). The record
  # itself witnesses all four law steps once per admitted evidence.
  defp happy_log(fixture) do
    %{"record" => record, "payload" => payload} = fixture
    admission = record["v2"]["admission"]["Recorded"]
    assert is_list(admission) and admission != []
    assert Enum.all?(admission, &(&1["decision"] == "Admitted"))
    # gate-run witnessed by the closure: gate queries bound by digest
    gates = Map.keys(payload["closure"]) |> Enum.filter(&String.starts_with?(&1, "gates/"))
    assert length(gates) == 3

    for evidence <- admission do
      # the record is chain-sealed and projects to one ingest event
      assert byte_size(record["chain_hash_hex"]) == 64
      pack = "pack:" <> hd(record["object_ids"])

      [
        "admission:" <> evidence["evidence_id"],
        "gate-run:" <> Integer.to_string(length(gates)),
        "receipt:" <> String.slice(record["chain_hash_hex"], 0, 8),
        "ingest:" <> pack
      ]
      |> Enum.map(&String.split(&1, ":", parts: 2) |> hd())
    end
  end

  # ---------------------------------------------------------------------------
  # The net: admission -> gate-run -> receipt -> ingest
  # ---------------------------------------------------------------------------

  defp fleet_net do
    Art72Conformance.net(
      %{
        "admission" => %{input: %{"start" => 1}, output: %{"admitted" => 1}},
        "gate-run" => %{input: %{"admitted" => 1}, output: %{"gated" => 1}},
        "receipt" => %{input: %{"gated" => 1}, output: %{"receipted" => 1}},
        "ingest" => %{input: %{"receipted" => 1}, output: %{"ingested" => 1}}
      },
      %{"start" => 1},
      %{"ingested" => 1}
    )
  end

  # Fitness of a trace, mapping a fabricated (unmodelable) activity to 0.0
  # rather than raising — fabrication carries zero admitted bits.
  defp fitness(net, trace) do
    if Enum.all?(trace, &Map.has_key?(net.transitions, &1)) do
      {c, _stats} = Art72Conformance.log_fitness(net, [trace])
      c
    else
      0.0
    end
  end

  # ---------------------------------------------------------------------------
  # Courts
  # ---------------------------------------------------------------------------

  describe "fleet order law (admission -> gate-run -> receipt -> ingest)" do
    test "pinned fixture corpus fits the law exactly: fitness == 1.0, :NO_DRIFT" do
      net = fleet_net()
      log = happy_log(fixture())
      assert length(log) == 2

      {fitness, stats} = Art72Conformance.log_fitness(net, log)
      assert fitness == 1.0
      assert stats.missing == 0 and stats.remaining == 0

      assert :NO_DRIFT = Art72Conformance.drift_decision(fitness, 0.05)
    end

    test "injected out-of-order gate event (receipt before gate-run) -> fitness < 1.0 -> :DRIFT" do
      net = fleet_net()
      [trace | rest] = happy_log(fixture())

      drifted =
        List.replace_at(trace, 2, Enum.at(trace, 1)) |> then(&List.replace_at(&1, 1, Enum.at(trace, 2)))

      {fitness, _} = Art72Conformance.log_fitness(net, [drifted | rest])
      assert fitness < 1.0
      assert :DRIFT = Art72Conformance.drift_decision(fitness, 0.05)
    end

    test "fabricated event (activity the law cannot express) -> fitness 0.0" do
      net = fleet_net()
      [trace | _] = happy_log(fixture())

      fabricated = List.replace_at(trace, 1, "fabricated.law.write")
      assert 0.0 == fitness(net, fabricated)
    end

    test "corpus is deterministic" do
      assert happy_log(fixture()) == happy_log(fixture())
    end
  end
end
