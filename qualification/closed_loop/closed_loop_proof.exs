# Exact executable qualification for the beam4pm closed loop.
#
# This is intentionally a qualification script rather than a product module:
# it composes already-admitted runtime surfaces without creating a second
# orchestration abstraction or a new authority boundary.

alias BeamPM.{
  Actuation,
  Ferroplan,
  PowlConformance,
  ProcessGovernor,
  ReceiptChain,
  Rust4PM
}

assert! = fn condition, label ->
  unless condition, do: raise("REFUSED[#{label}]")
end

sha256_file! = fn path ->
  path
  |> File.read!()
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16(case: :lower)
end

read_json! = fn path ->
  path |> File.read!() |> JSON.decode!()
end

root =
  System.get_env("CLOSED_LOOP_RECEIPTS_DIR") ||
    Path.join(System.tmp_dir!(), "beam4pm-closed-loop-proof")

proof_path =
  System.get_env("CLOSED_LOOP_PROOF_RECEIPT") ||
    Path.join(root, "closed-loop-proof.json")

subject_sha =
  System.get_env("CLOSED_LOOP_SUBJECT_SHA") ||
    System.get_env("GITHUB_SHA") ||
    "local-unbound"

File.rm_rf!(root)
File.mkdir_p!(root)

bridge = Path.expand("qualification/fixtures/toy_gym_bridge.py")
assert!.(File.exists?(bridge), "TOY_GYM_BRIDGE_MISSING")

start_engine! = fn module ->
  case module.start() do
    {:ok, _pid} -> :ok
    {:error, {:already_started, _pid}} -> :ok
    other -> raise "REFUSED[ENGINE_START]: #{inspect({module, other})}"
  end
end

start_engine!.(Rust4PM)
start_engine!.(Ferroplan)

process_id = "toy_counter_governed"
expected_trace = ["plan", "admit", "execute", "observe", "plan", "admit", "execute", "observe"]

reference_runs =
  for n <- 1..3 do
    receipts_dir = Path.join(root, "reference-#{n}")

    final =
      case ProcessGovernor.run(
             process_id,
             gym: "toy-counter",
             bridge: bridge,
             receipts_dir: receipts_dir,
             continuous: true
           ) do
        {:ok, final} ->
          final

        other ->
          raise "REFUSED[REFERENCE_PROCESS_RUN_#{n}]: #{inspect(other)}"
      end

    assert!.(final.state == "observed", "REFERENCE_FINAL_STATE_#{n}")

    replay =
      case ProcessGovernor.replay(process_id, Enum.reverse(final.receipts)) do
        {:ok, replay} -> replay
        other -> raise "REFUSED[REFERENCE_REPLAY_#{n}]: #{inspect(other)}"
      end

    trace = replay.mined_trace.activity_sequence
    assert!.(trace == expected_trace, "REFERENCE_TRACE_#{n}")

    %{
      ordinal: n,
      trace: trace,
      process_receipts: Enum.reverse(final.receipts)
    }
  end

# Produce a real runtime failure through the same governed DO path.  Its
# shorter replayed trace is the observation that the process-conformance
# layer must reject against the successful reference population.
failed_dir = Path.join(root, "deviant")

{failure_reason, failed_snapshot} =
  case ProcessGovernor.run(
         process_id,
         gym: "crashy",
         bridge: bridge,
         receipts_dir: failed_dir
       ) do
    {:error, {:execution_failed, reason}, partial} ->
      {reason, partial}

    other ->
      raise "REFUSED[DEVIANT_RUN_DID_NOT_FAIL]: #{inspect(other)}"
  end

failed_receipts = Enum.reverse(failed_snapshot.receipts)
assert!.(failed_receipts != [], "DEVIANT_PROCESS_RECEIPT_MISSING")

deviant_replay =
  case ProcessGovernor.replay(process_id, failed_receipts) do
    {:ok, replay} -> replay
    other -> raise "REFUSED[DEVIANT_REPLAY]: #{inspect(other)}"
  end

deviant_trace = deviant_replay.mined_trace.activity_sequence
assert!.(deviant_trace == ["plan", "admit", "execute"], "DEVIANT_TRACE_BOUNDARY")

failed_process_receipt = hd(failed_receipts)
assert!.(not is_nil(failed_process_receipt.actuation), "DEVIANT_BRCE_REFERENCE_MISSING")
failed_brce_path = failed_process_receipt.actuation.receipt_path
assert!.(File.exists?(failed_brce_path), "DEVIANT_BRCE_RECEIPT_MISSING")

failed_brce = read_json!.(failed_brce_path)
assert!.(failed_brce["receipt_schema"] == "beam4pm-brce/v1", "DEVIANT_BRCE_SCHEMA")
assert!.(failed_brce["admission"]["admitted"] == true, "DEVIANT_WAS_NOT_ADMITTED")
assert!.(failed_brce["execution"]["performed"] == false, "DEVIANT_WAS_PERFORMED")

# Turn the three real successful traces into a real object-centric Rust4PM
# reference log.  Nothing below uses a fixture trace or an in-memory fake.
{:ok, %{"ocel_handle" => reference_ocel}} = Rust4PM.ocel_new()

expected_trace
|> Enum.uniq()
|> Enum.each(fn activity ->
  {:ok, _} = Rust4PM.ocel_add_event_type(reference_ocel, activity)
end)

{:ok, _} = Rust4PM.ocel_add_object_type(reference_ocel, "process_run")
epoch = ~U[2026-09-27 00:00:00Z]

Enum.each(reference_runs, fn %{ordinal: run_n, trace: trace} ->
  object_id = "reference-run-#{run_n}"
  {:ok, _} = Rust4PM.ocel_add_object(reference_ocel, object_id, "process_run")

  trace
  |> Enum.with_index()
  |> Enum.each(fn {activity, event_n} ->
    timestamp =
      epoch
      |> DateTime.add(run_n * 100 + event_n, :second)
      |> DateTime.to_iso8601()

    {:ok, _} =
      Rust4PM.ocel_add_event(
        reference_ocel,
        "reference-#{run_n}-#{event_n}-#{activity}",
        activity,
        timestamp,
        [[object_id, "process_run"]]
      )
  end)
end)

# A tiny real planning world whose single lawful plan action has the SAME
# identity as a graph-admitted BRCE actuation.  This lets the qualification
# prove Plan' -> explicit re-admission -> DO rather than merely proving that
# the planner and actuator work independently.
domain = """
(define (domain closed-loop-counter)
  (:requirements :strips)
  (:predicates (counter_ready) (counter_incremented))
  (:action increment_counter
    :parameters ()
    :precondition (counter_ready)
    :effect (counter_incremented)))
"""

problem = """
(define (problem closed-loop-counter-problem)
  (:domain closed-loop-counter)
  (:init (counter_ready))
  (:goal (counter_incremented)))
"""

{:ok, %{"handle" => session}} = Ferroplan.session_new(domain, problem)

try do
  case Ferroplan.session_think(session, 10_000, 64) do
    {:ok, %{"solved" => true}} -> :ok
    other -> raise "REFUSED[INITIAL_PLAN_UNSOLVED]: #{inspect(other)}"
  end

  repair =
    case PowlConformance.conform_observe_replan(
           reference_ocel,
           "process_run",
           deviant_trace,
           session,
           [{"(counter_ready)", true}],
           on_deviation: :refuse_reuse,
           event_id: "closed-loop-deviation",
           evals: 10_000,
           mem_mb: 64
         ) do
      {:ok, result} ->
        result

      other ->
        raise "REFUSED[CONFORM_REPLAN]: #{inspect(other)}"
    end

  assert!.(repair.conformance.conforms == false, "DEVIATION_NOT_DETECTED")
  assert!.(repair.conformance.alignment["cost"] > 0, "DEVIATION_COST_ZERO")
  assert!.(repair.conformance.deviations != [], "DEVIATION_SET_EMPTY")
  assert!.(repair.conformance_gate == :deviation_refused_reuse, "DEVIATION_GATE")
  assert!.(repair.decision == :replanned_full, "REPLAN_DECISION")
  assert!.(repair.trigger == :evidence_refused_reuse, "REPLAN_TRIGGER")
  assert!.(repair.plan["solved"] == true, "REPLAN_UNSOLVED")
  assert!.(is_list(repair.suffix) and repair.suffix != [], "REPLAN_SUFFIX_EMPTY")
  assert!.(not is_nil(repair.dynamic_replan_trigger), "REPLAN_TRIGGER_RECEIPT_MISSING")
  assert!.(is_binary(repair.evidence_digest), "CONFORMANCE_EVIDENCE_DIGEST_MISSING")
  assert!.(repair.authority_ceiling == :select, "REPLAN_AUTHORITY_CEILING")

  [step | _] = repair.suffix
  planned_action = step |> Map.fetch!("action") |> String.downcase()
  assert!.(planned_action == "increment_counter", "PLAN_ACTION_IDENTITY")

  admitted_actuation = Map.fetch!(Actuation.admitted_actuations(), planned_action)
  assert!.(admitted_actuation.requires == ["counter_ready"], "BRCE_REQUIREMENT_IDENTITY")

  plan_do_dir = Path.join(root, "plan-to-brce")
  digest = String.replace_prefix(repair.evidence_digest, "evidence:", "")
  chain_id = "closed-loop-" <> String.slice(digest, 0, 16)

  # A SELECT/CONSTRUCT result is not authority.  The exact planned action
  # first attempts to cross BRCE without its graph-required fact and MUST be
  # refused, with a real consequence receipt.
  bypass_id = "planned-action-without-readmission"

  bypass_result =
    Actuation.run(
      %{
        action_name: planned_action,
        preconditions: [],
        effects: ["counter_incremented"]
      },
      gym: "toy-counter",
      bridge: bridge,
      receipts_dir: plan_do_dir,
      run_id: bypass_id,
      chain_id: chain_id
    )

  assert!.(match?({:error, {:refused, _}}, bypass_result), "BRCE_BYPASS_NOT_REFUSED")

  bypass_path = Path.join(plan_do_dir, bypass_id <> ".json")
  assert!.(File.exists?(bypass_path), "BRCE_BYPASS_RECEIPT_MISSING")
  bypass_receipt = read_json!.(bypass_path)
  assert!.(bypass_receipt["admission"]["admitted"] == false, "BRCE_BYPASS_ADMITTED")
  assert!.(bypass_receipt["execution"]["performed"] == false, "BRCE_BYPASS_PERFORMED")

  # Now cross the SAME boundary with the requirements sourced from the
  # graph-derived admission map.  This is explicit re-admission, not a plan
  # being silently promoted to DO authority.
  admitted_id = "planned-action-readmitted"

  {:ok, consequence} =
    Actuation.run(
      %{
        action_name: planned_action,
        preconditions: admitted_actuation.requires,
        effects: ["counter_incremented"]
      },
      gym: "toy-counter",
      bridge: bridge,
      receipts_dir: plan_do_dir,
      run_id: admitted_id,
      chain_id: chain_id
    )

  assert!.(consequence.performed == true, "READMITTED_ACTION_NOT_PERFORMED")
  assert!.(File.exists?(consequence.receipt_path), "READMITTED_BRCE_RECEIPT_MISSING")

  consequence_receipt = read_json!.(consequence.receipt_path)
  assert!.(consequence_receipt["admission"]["admitted"] == true, "READMISSION_FAILED")
  assert!.(consequence_receipt["execution"]["performed"] == true, "READMITTED_DO_MISSING")
  assert!.(consequence_receipt["action"]["action_name"] == planned_action, "PLAN_DO_IDENTITY_DRIFT")

  chain =
    case ReceiptChain.verify(plan_do_dir, chain_id) do
      {:ok, verified} -> verified
      other -> raise "REFUSED[BRCE_CHAIN_REPLAY]: #{inspect(other)}"
    end

  assert!.(chain.length == 2, "BRCE_CHAIN_LENGTH")
  assert!.(chain.receipt_paths == [bypass_path, consequence.receipt_path], "BRCE_CHAIN_ORDER")

  proof_receipt = %{
    "schema" => "beam4pm-closed-loop-proof/v1",
    "subject_sha" => subject_sha,
    "reference_runs" => length(reference_runs),
    "reference_trace" => expected_trace,
    "deviant_trace" => deviant_trace,
    "deviant_failure" => inspect(failure_reason),
    "deviant_brce_receipt" => failed_brce_path,
    "deviant_brce_sha256" => sha256_file!.(failed_brce_path),
    "conformance_cost" => repair.conformance.alignment["cost"],
    "conformance_deviations" => repair.conformance.deviations,
    "conformance_evidence_digest" => repair.evidence_digest,
    "repair_decision" => Atom.to_string(repair.decision),
    "repair_trigger" => Atom.to_string(repair.trigger),
    "repair_event_id" => repair.event_id,
    "repair_trigger_hash" => repair.dynamic_replan_trigger.trigger_hash,
    "repair_authority_ceiling" => Atom.to_string(repair.authority_ceiling),
    "planned_action" => planned_action,
    "bypass_refused" => true,
    "bypass_receipt" => bypass_path,
    "bypass_receipt_sha256" => sha256_file!.(bypass_path),
    "readmitted_brce_receipt" => consequence.receipt_path,
    "readmitted_brce_sha256" => sha256_file!.(consequence.receipt_path),
    "receipt_chain_id" => chain_id,
    "receipt_chain_length" => chain.length
  }

  File.mkdir_p!(Path.dirname(proof_path))
  File.write!(proof_path, JSON.encode!(proof_receipt))

  IO.puts("ALIVE[CLOSED_LOOP_BRCE_OCEL_CONFORMANCE_DFCM_FERROPLAN_BRCE]")
  IO.puts("SUBJECT_SHA=#{subject_sha}")
  IO.puts("PROOF_RECEIPT=#{proof_path}")
after
  _ = Ferroplan.session_free(session)
  _ = Rust4PM.free_ocel(reference_ocel)
end
