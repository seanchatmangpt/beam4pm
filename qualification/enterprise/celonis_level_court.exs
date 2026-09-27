# Enterprise process-intelligence court.
#
# This is intentionally outside test/ and lib/: it is a qualification harness,
# not product source. CI builds both real WASM engines, then runs this file with
# `mix run --no-start`. Nothing here mocks process mining, planning, BRCE, the
# gym subprocess, receipt persistence, or replay.
defmodule BeamPM.Qualification.EnterpriseCelonisCourt do
  alias BeamPM.Actuation
  alias BeamPM.Actuation.Session
  alias BeamPM.Ferroplan
  alias BeamPM.PowlConformance
  alias BeamPM.ReceiptChain
  alias BeamPM.Rust4PM

  @contract_path "qualification/enterprise/celonis_capability_contract.json"
  @receipt_path "_build/enterprise/celonis_level_court.json"
  @run_dir "_build/enterprise/celonis_level_court"
  @bridge "qualification/fixtures/toy_gym_bridge.py"

  @reference_actions ["increment_counter", "observe_counter"]

  @planning_domain """
  (define (domain counter-process)
    (:requirements :strips)
    (:predicates
      (counter-ready)
      (counter-incremented)
      (counter-observed))

    (:action increment-counter
      :parameters ()
      :precondition (counter-ready)
      :effect (counter-incremented))

    (:action observe-counter
      :parameters ()
      :precondition (counter-incremented)
      :effect (counter-observed)))
  """

  @planning_problem """
  (define (problem counter-process-p1)
    (:domain counter-process)
    (:init (counter-ready))
    (:goal (and (counter-observed))))
  """

  def run! do
    prepare!()
    contract = @contract_path |> File.read!() |> JSON.decode!()

    ensure!(contract["schema"] == "beam4pm-enterprise-capability-court/v1", "bad capability contract schema")
    ensure!(contract["claim_policy"]["current_standing"] == "PARTIAL_ALIVE", "court must not pre-claim CELONIS_LEVEL")

    {:ok, _} = Application.ensure_all_started(:wasmex)
    {:ok, _} = Application.ensure_all_started(:reactor)

    ensure!(Rust4PM.wasm_built?(), "rust4pm wasm missing: run scripts/rust4pm_wasm_build.sh")
    ensure!(Ferroplan.wasm_built?(), "ferroplan wasm missing: run scripts/ferroplan_wasm_build.sh")

    start_engine!(Rust4PM)
    start_engine!(Ferroplan)

    reference_traces =
      for n <- 1..3 do
        chain = "enterprise-reference-#{n}"
        run_healthy_episode!(chain, @reference_actions)
        trace_from_chain!(chain)
      end

    ensure!(Enum.all?(reference_traces, &(&1 == @reference_actions)), "reference BRCE traces diverged")

    # A real observed deviation: the environment performs the second business
    # activity first. This is not a fabricated list; it is reconstructed from
    # the verified durable BRCE receipt written by the real gym subprocess.
    deviant_chain = "enterprise-deviant"
    run_healthy_episode!(deviant_chain, ["observe_counter"])
    deviant_trace = trace_from_chain!(deviant_chain)
    ensure!(deviant_trace == ["observe_counter"], "deviant BRCE trace was not reconstructed exactly")

    reference_ocel = build_reference_ocel!(reference_traces)

    try do
      {:ok, before} =
        PowlConformance.check_conformance(reference_ocel, "process_instance", deviant_trace)

      ensure!(before.conforms == false, "real deviant trace unexpectedly conformed")
      ensure!(before.alignment["cost"] > 0, "real deviant trace had zero alignment cost")
      ensure!(before.deviations != [], "real deviant trace produced no deviations")

      {:ok, %{"handle" => planner}} =
        Ferroplan.session_new(@planning_domain, @planning_problem)

      try do
        {:ok, initial_plan} = Ferroplan.session_think(planner, 10_000, 64)
        ensure!(initial_plan["solved"] == true, "Ferroplan could not solve the admitted process")

        # The conformance verdict is consumed as repair evidence. :refuse_reuse
        # means a process deviation may not silently preserve the previously
        # valid candidate; DfCM must run a bounded full repair.
        {:ok, repair} =
          PowlConformance.conform_observe_replan(
            reference_ocel,
            "process_instance",
            deviant_trace,
            planner,
            [{"(counter-ready)", true}],
            on_deviation: :refuse_reuse,
            event_id: "enterprise-deviation-observed",
            evals: 10_000,
            mem_mb: 64
          )

        ensure!(repair.conformance.conforms == false, "repair lost the conformance verdict")
        ensure!(repair.conformance_gate == :deviation_refused_reuse, "deviation did not gate reuse")
        ensure!(repair.decision == :replanned_full, "deviation did not produce a bounded full replan")
        ensure!(repair.trigger == :evidence_refused_reuse, "wrong replan trigger")
        ensure!(repair.authority_ceiling == :select, "planning crossed the SELECT/DO boundary")
        ensure!(repair.plan["solved"] == true, "replanned candidate is unsolved")
        ensure!(repair.dynamic_replan_trigger != nil, "replan emitted no trigger evidence")
        ensure!(repair.plan_memory != nil, "replan emitted no plan memory evidence")

        repaired_chain = "enterprise-repaired"
        execute_planner_through_brce!(planner, repaired_chain, @reference_actions)

        {:ok, %{"goal_met" => true}} = Ferroplan.session_goal_met?(planner)

        # Fresh disk reconstruction after all execution state is closed.
        repaired_trace = trace_from_chain!(repaired_chain)
        ensure!(repaired_trace == @reference_actions, "repaired BRCE trace does not equal the planned process")

        {:ok, after_repair} =
          PowlConformance.check_conformance(
            reference_ocel,
            "process_instance",
            repaired_trace
          )

        ensure!(after_repair.conforms == true, "repaired execution still violates the process model")
        ensure!(after_repair.alignment["cost"] == 0, "repaired execution has nonzero alignment cost")
        ensure!(after_repair.deviations == [], "repaired execution still has deviations")

        repaired_chain_receipt = verify_chain!(repaired_chain)
        deviant_chain_receipt = verify_chain!(deviant_chain)

        core_proofs = %{
          "real_brce_reference_trace" => true,
          "durable_receipt_reconstruction" => true,
          "real_object_centric_reference_model" => true,
          "real_conformance_deviation_detected" => true,
          "conformance_evidence_consumed_by_dfcm" => true,
          "bounded_ferroplan_replan" => true,
          "planner_candidate_crossed_brce" => true,
          "post_repair_conformance_zero_cost" => true,
          "receipt_chain_replay" => true,
          "plan_identity_evidence_emitted" => true
        }

        gaps =
          contract["capabilities"]
          |> Enum.filter(&(&1["standing"] != "ALIVE"))
          |> Enum.map(&Map.take(&1, ["id", "standing", "required_proof", "implementation_target"]))

        # The court PASS means the closed-loop core is observed AND the
        # external parity claim is correctly refused until every required gap
        # is closed. It does not redefine PARTIAL_ALIVE as equivalent to Celonis.
        receipt = %{
          "schema" => "beam4pm-enterprise-court-receipt/v1",
          "candidate_sha" => git_sha(),
          "comparison_target" => contract["comparison_target"]["name"],
          "subject" => "toy_counter_governed",
          "core_loop" => %{
            "reference_trace" => @reference_actions,
            "deviant_trace" => deviant_trace,
            "deviant_alignment_cost" => before.alignment["cost"],
            "deviant_deviations" => before.deviations,
            "replan_decision" => Atom.to_string(repair.decision),
            "replan_trigger" => Atom.to_string(repair.trigger),
            "conformance_evidence_digest" => repair.evidence_digest,
            "replan_trigger_hash" => repair.dynamic_replan_trigger.trigger_hash,
            "plan_lineage_hash" => get_in(repair, [:plan_lineage, :lineage_hash]),
            "plan_memory_hash" => repair.plan_memory.memory_hash,
            "repaired_trace" => repaired_trace,
            "repaired_alignment_cost" => after_repair.alignment["cost"],
            "deviant_receipt_chain" => deviant_chain_receipt,
            "repaired_receipt_chain" => repaired_chain_receipt
          },
          "core_proofs" => core_proofs,
          "celonis_level" => false,
          "standing" => contract["claim_policy"]["current_standing"],
          "claim_refusal_is_success" => true,
          "open_required_capabilities" => gaps
        }

        persist_receipt!(receipt)
        receipt
      after
        _ = Ferroplan.session_free(planner)
      end
    after
      _ = Rust4PM.free_ocel(reference_ocel)
    end
  end

  defp prepare! do
    File.rm_rf!(@run_dir)
    File.mkdir_p!(@run_dir)
    File.mkdir_p!(Path.dirname(@receipt_path))

    ensure!(File.exists?(@bridge), "real gym bridge missing at #{@bridge}")
    ensure!(File.exists?(@contract_path), "capability contract missing at #{@contract_path}")
  end

  defp start_engine!(module) do
    case module.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      other -> raise "#{inspect(module)} failed to start: #{inspect(other)}"
    end
  end

  defp run_healthy_episode!(chain_id, actions) do
    {:ok, session0} = Session.open(@bridge, "toy-counter")

    try do
      {_, _session} =
        Enum.with_index(actions, 1)
        |> Enum.map_reduce(session0, fn {action_name, ordinal}, session ->
          action = planning_action(action_name)

          {:ok, result} =
            Actuation.run(
              action,
              gym: "toy-counter",
              bridge: @bridge,
              receipts_dir: @run_dir,
              run_id: "#{chain_id}-#{ordinal}",
              chain_id: chain_id,
              session: session
            )

          ensure!(result.performed == true, "BRCE did not perform #{action_name}")
          next_session = Session.update_observation(session, result.observation_after)
          {result, next_session}
        end)

      :ok
    after
      :ok = Session.close(session0)
    end
  end

  defp execute_planner_through_brce!(planner, chain_id, expected_actions) do
    {:ok, session0} = Session.open(@bridge, "toy-counter")

    try do
      {_, _session} =
        Enum.with_index(expected_actions, 1)
        |> Enum.map_reduce(session0, fn {expected_action, ordinal}, session ->
          {:ok, step} = Ferroplan.session_step(planner)
          ensure!(is_map(step), "Ferroplan returned no candidate step at ordinal #{ordinal}")

          selected_action =
            step
            |> Map.fetch!("action")
            |> String.downcase()
            |> String.replace("-", "_")

          ensure!(
            selected_action == expected_action,
            "planner selected #{inspect(selected_action)}; expected #{inspect(expected_action)}"
          )

          {:ok, result} =
            Actuation.run(
              planning_action(selected_action),
              gym: "toy-counter",
              bridge: @bridge,
              receipts_dir: @run_dir,
              run_id: "#{chain_id}-#{ordinal}",
              chain_id: chain_id,
              session: session
            )

          ensure!(result.performed == true, "BRCE did not perform planner action #{selected_action}")
          {:ok, %{"ok" => true}} = Ferroplan.session_advance(planner)

          next_session = Session.update_observation(session, result.observation_after)
          {result, next_session}
        end)

      :ok
    after
      :ok = Session.close(session0)
    end
  end

  defp planning_action("increment_counter") do
    %{
      action_name: "increment_counter",
      preconditions: ["counter_ready"],
      effects: ["counter_incremented"]
    }
  end

  defp planning_action("observe_counter") do
    %{
      action_name: "observe_counter",
      preconditions: [],
      effects: ["counter_observed"]
    }
  end

  defp planning_action(other), do: raise("planner produced unmapped actuation #{inspect(other)}")

  defp trace_from_chain!(chain_id) do
    verified = verify_chain!(chain_id)

    verified["receipt_paths"]
    |> Enum.map(&(&1 |> File.read!() |> JSON.decode!()))
    |> Enum.filter(&(get_in(&1, ["execution", "performed"]) == true))
    |> Enum.map(&get_in(&1, ["action", "action_name"]))
  end

  defp verify_chain!(chain_id) do
    {:ok, verified} = ReceiptChain.verify(@run_dir, chain_id)

    paths = verified.receipt_paths
    ensure!(paths != [], "receipt chain #{chain_id} is empty")

    %{
      "chain_id" => chain_id,
      "length" => verified.length,
      "receipt_paths" => paths,
      "head_sha256" => sha256_file!(List.last(paths))
    }
  end

  defp build_reference_ocel!(traces) do
    {:ok, %{"ocel_handle" => handle}} = Rust4PM.ocel_new()

    Enum.each(@reference_actions, fn activity ->
      {:ok, _} = Rust4PM.ocel_add_event_type(handle, activity)
    end)

    {:ok, _} = Rust4PM.ocel_add_object_type(handle, "process_instance")

    Enum.with_index(traces, 1)
    |> Enum.each(fn {trace, case_no} ->
      object_id = "reference-#{case_no}"
      {:ok, _} = Rust4PM.ocel_add_object(handle, object_id, "process_instance")

      Enum.with_index(trace, 1)
      |> Enum.each(fn {activity, ordinal} ->
        timestamp =
          "2026-09-27T#{String.pad_leading(Integer.to_string(9 + case_no), 2, "0")}:" <>
            "#{String.pad_leading(Integer.to_string(ordinal), 2, "0")}:00+00:00"

        {:ok, _} =
          Rust4PM.ocel_add_event(
            handle,
            "#{object_id}-#{ordinal}-#{activity}",
            activity,
            timestamp,
            [[object_id, "process_instance"]]
          )
      end)
    end)

    handle
  end

  defp sha256_file!(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp git_sha do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "UNKNOWN"
    end
  end

  defp persist_receipt!(receipt) do
    File.write!(@receipt_path, JSON.encode!(receipt) <> "\n")
    IO.puts("ENTERPRISE_COURT=PASS")
    IO.puts("ENTERPRISE_COURT_RECEIPT=#{@receipt_path}")
    IO.puts(JSON.encode!(receipt))
  end

  defp ensure!(true, _message), do: :ok
  defp ensure!(false, message), do: raise(message)
end

try do
  BeamPM.Qualification.EnterpriseCelonisCourt.run!()
rescue
  error ->
    File.mkdir_p!("_build/enterprise")

    failure = %{
      "schema" => "beam4pm-enterprise-court-receipt/v1",
      "candidate_sha" =>
        case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
          {sha, 0} -> String.trim(sha)
          _ -> "UNKNOWN"
        end,
      "standing" => "BUILD_BROKEN",
      "celonis_level" => false,
      "court" => "FAIL",
      "error" => Exception.format(:error, error, __STACKTRACE__)
    }

    File.write!("_build/enterprise/celonis_level_court.json", JSON.encode!(failure) <> "\n")
    IO.puts(:stderr, "ENTERPRISE_COURT=FAIL")
    IO.puts(:stderr, failure["error"])
    reraise(error, __STACKTRACE__)
end
