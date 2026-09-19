defmodule BeamPM.Dfcm.Sa2aValidateCardTest do
  @moduledoc """
  Parity qualification for `BeamPM.Dfcm.sa2a_validate_card/1` (ticket
  b4p-p3-sa2a-card-validate-parity, wave v26.9.18): the bridge must run the
  REAL standalone AutoFDE-Lab `sa2a validate` court (RFC-SA2A-001 v26.9.16
  profile admission, §10/§76) against (a) beam4pm's REAL served agent card
  -- captured verbatim from `GET /a2a/.well-known/agent-card.json` on a live
  beam4pm boot -- and (b) an SA2A-shaped card the court admits.

  The recorded real-card verdict IS the parity finding: the lab court reads
  only the SA2A extension fields `supported_profiles`/`agent_id`
  (autofde-lab src/autofde_lab/sa2a/cli.py:65-73), which the A2A v0.3 wire
  card emitted by `A2A.JSON.encode_agent_card/2` (deps/a2a
  lib/a2a/json.ex:272-287) structurally cannot carry -- so a conformant
  A2A v0.3 card is refused with `UNSUPPORTED_PROFILE`. Asserting that
  refusal here is the permanent tripwire for this finding: if the upstream
  validator ever learns A2A v0.3 shapes, this test fails and forces the
  parity ledger to be re-triaged (never silently absorbed).
  """

  use ExUnit.Case, async: true

  alias BeamPM.Dfcm

  @real_card Path.expand("../qualification/fixtures/a2a/agent-card.json", __DIR__)

  test "validates beam4pm's REAL served agent card via the standalone lab court" do
    assert File.exists?(@real_card), "real agent-card fixture missing at #{inspect(@real_card)}"

    card = @real_card |> File.read!() |> JSON.decode!()
    # The fixture is the real capture (observed 2026-09-18, worktree boot on
    # :4311, ash_a2a hex 26.9.17): A2A v0.3 wire shape, 1194 skills.
    assert length(card["skills"]) == 1194
    assert card["name"] == "beam4pm_a2a_agent"
    # Finding B1 (parity ledger): top-level protocolVersion is ABSENT from the
    # served card -- deps/a2a json.ex:287 emits it only when the plug opts
    # carry :protocol_version, and BeamPM.A2ARouter passes none. If this
    # assertion flips, the B1 fix landed: re-triage the parity table.
    refute Map.has_key?(card, "protocolVersion")
    # Finding B2: the interface version served is "2.0" (the JSON-RPC layer),
    # not the builder's declared "0.3.0" -- deps/ash_a2a
    # agent_card_builder.ex:39 is dropped by deps/a2a json.ex:253-255.
    assert card["supportedInterfaces"] == [
             %{"protocolBinding" => "jsonrpc", "protocolVersion" => "2.0",
               "url" => "http://localhost:4311/a2a"}
           ]

    assert {:error, {:invalid_card, verdict}} = Dfcm.sa2a_validate_card(@real_card)
    # Verdict payload exactly as the lab emits it (sa2a/cli.py:67-71 -- the
    # UNSUPPORTED_PROFILE emit carries no "profile" key; only the §76 guard
    # refusal at cli.py:56 does).
    assert verdict == %{
             "ok" => false,
             "code" => "UNSUPPORTED_PROFILE",
             "error" =>
               "Agent card does not declare support for profile SA2A-PROFILE-v26.9.16"
           }
  end

  test "admits an SA2A-shaped card with status VALID (real CLI execution)" do
    sa2a_card = %{
      "agent_id" => "beam4pm-parity-probe",
      "supported_profiles" => ["SA2A-PROFILE-v26.9.16"]
    }

    assert {:ok, verdict} = Dfcm.sa2a_validate_card(sa2a_card)
    assert verdict["ok"] == true
    assert verdict["agent_id"] == "beam4pm-parity-probe"
    assert verdict["profile"] == "SA2A-PROFILE-v26.9.16"
    assert verdict["status"] == "VALID"
  end

  test "accepts a decoded card map and a file path symmetrically" do
    sa2a_card = %{
      "agent_id" => "beam4pm-parity-map",
      "supported_profiles" => ["SA2A-PROFILE-v26.9.16"]
    }

    assert {:ok, map_verdict} = Dfcm.sa2a_validate_card(sa2a_card)
    assert map_verdict["status"] == "VALID"

    path = Path.join(System.tmp_dir!(), "beam4pm-parity-card-#{:erlang.unique_integer()}.json")
    File.write!(path, JSON.encode!(sa2a_card))

    try do
      assert {:ok, path_verdict} = Dfcm.sa2a_validate_card(path)
      assert path_verdict == map_verdict
    after
      File.rm(path)
    end
  end

  test "refuses a missing card path without invoking the lab" do
    assert {:error, {:card_not_found, path}} =
             Dfcm.sa2a_validate_card("/nonexistent/agent-card.json")

    assert path == "/nonexistent/agent-card.json"
  end
end
