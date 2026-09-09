defmodule BeamPM.Ws3DfcmSelfHealingQualificationTest do
  @moduledoc """
  Exact execution witness for the WS3 DfCM failure -> repair -> replay vertical slice.

  The DfCM kernel is SELECT-only here. It preserves and ranks reversible repair
  candidates, but its selection and hook intent carry no execution authority.
  Every real environment consequence still crosses the existing
  `BeamPM.Actuation.run/2` BRCE admission boundary and emits the existing
  `beam4pm-brce/v1` consequence receipt. This test intentionally does not mint an
  `AutonomicSelfHealingCompletionReceipt`: that projection's
  `authority_receipt_sha` must not be populated with a merely named or surrogate
  receipt.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Actuation
  alias BeamPM.Autonomy.Kernel
  alias BeamPM.ReceiptChain

  @moduletag :tmp_dir

  defp bridge_path do
    path = Path.expand("qualification/fixtures/toy_gym_bridge.py")
    assert File.exists?(path), "fixture gym bridge not found at #{path}"
    path
  end

  defp action do
    %{
      action_name: "increment_counter",
      preconditions: ["counter_ready"],
      effects: ["counter_incremented"]
    }
  end

  defp read_receipt!(path), do: path |> File.read!() |> JSON.decode!()

  defp sha256_hex!(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  if Code.ensure_loaded?(BeamPM.Actuation) and Code.ensure_loaded?(BeamPM.Autonomy.Kernel) do
  test "observed crash preserves DfCM repair options; fresh BRCE re-admission heals and replay verifies",
       %{tmp_dir: tmp_dir} do
    chain_id = "ws3-dfcm-self-healing"
    failed_run_id = "ws3-dfcm-failed"
    repaired_run_id = "ws3-dfcm-repaired"

    # First real DO: an admitted action crosses the existing BRCE boundary and
    # the real subprocess crashes during execution. The failed consequence is
    # still receipted; this observed failure is the evidence DfCM may reason over.
    assert {:error, {:execution_failed, {:bridge_exited, 3}}} =
             Actuation.run(action(),
               gym: "crashy",
               bridge: bridge_path(),
               receipts_dir: tmp_dir,
               run_id: failed_run_id,
               chain_id: chain_id
             )

    failed_path = Path.join(tmp_dir, failed_run_id <> ".json")
    assert File.exists?(failed_path)
    failed_receipt = read_receipt!(failed_path)
    assert failed_receipt["receipt_schema"] == "beam4pm-brce/v1"
    assert failed_receipt["admission"]["admitted"] == true
    assert failed_receipt["execution"]["performed"] == false
    assert failed_receipt["execution"]["error"] =~ "bridge_exited"

    observation = %{
      failure_class: :dependency,
      consequence_receipt_hash: sha256_hex!(failed_path)
    }

    # DfCM preserves more than one reversible repair before selection. Neither
    # candidate contains an executable gym operation or an authority grant.
    candidates = [
      %{
        id: "retry-same-dependency",
        utility: 0.5,
        risk: 0.8,
        reversibility: 0.95,
        evidence: 0.4,
        strategy: :retry
      },
      %{
        id: "rebind-healthy-dependency",
        utility: 0.9,
        risk: 0.1,
        reversibility: 1.0,
        evidence: 0.95,
        strategy: :rebind
      }
    ]

    frontier = Kernel.frontier(candidates, observation)
    assert length(frontier.candidates) == 2
    assert frontier.selected == nil
    assert frontier.authority == nil

    assert {:ok, counterfactual} =
             Kernel.simulate(frontier, "retry-same-dependency", %{expected: :same_failure})

    refute counterfactual.executed?

    assert {:ok, selection} =
             Kernel.select(frontier, %{
               max_risk: 0.2,
               min_evidence: 0.9,
               min_reversibility: 0.9
             })

    assert selection.candidate.id == "rebind-healthy-dependency"
    refute selection.authorized?

    assert {:ok, intent} = Kernel.intent(selection, "ws3-dfcm-repair-hook")
    refute intent.authorized?
    refute intent.executed?

    # A SELECT/hook object cannot manufacture DO authority. This refusal happens
    # before the repaired environment attempt below.
    assert {:refused, :do_not_authorized} =
             Kernel.grant(intent, %{
               authority_id: "qualification-non-authority",
               intent_hash: Kernel.digest(intent),
               candidate_id: intent.candidate_id,
               do: false
             })

    # Second real DO: the test harness applies the selected repair strategy by
    # binding a healthy deterministic fixture, but it does not reuse or promote
    # the DfCM intent as authority. The action crosses BeamPM.Actuation.run/2
    # again and therefore receives a fresh graph-derived BRCE admission.
    assert {:ok, repaired} =
             Actuation.run(action(),
               gym: "toy-counter",
               bridge: bridge_path(),
               receipts_dir: tmp_dir,
               run_id: repaired_run_id,
               chain_id: chain_id
             )

    repaired_receipt = read_receipt!(repaired.receipt_path)
    assert repaired_receipt["receipt_schema"] == "beam4pm-brce/v1"
    assert repaired_receipt["admission"]["admitted"] == true
    assert repaired_receipt["execution"]["performed"] == true
    assert repaired_receipt["execution"]["observation_before"] == %{"counter" => 0, "steps" => 0}
    assert repaired_receipt["execution"]["observation_after"] == %{"counter" => 1, "steps" => 1}

    # Receipt/replay closure: the repaired receipt is cryptographically linked
    # to the observed failed attempt, and independent replay verification walks
    # the on-disk chain without repeating either consequence.
    assert repaired_receipt["chain_seq"] == 2
    assert repaired_receipt["prev_receipt_hash"] == sha256_hex!(failed_path)

    assert {:ok,
            %{
              chain_id: ^chain_id,
              length: 2,
              receipt_paths: [^failed_path, repaired_path]
            }} = ReceiptChain.verify(tmp_dir, chain_id)

    assert repaired_path == repaired.receipt_path
    end
  end
end
