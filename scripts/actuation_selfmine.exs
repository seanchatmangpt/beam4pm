# actuation_selfmine.exs -- the actuation -> OCEL -> discovery dogfood loop
# (gates PI7/PI8, docs/jira/v26.8.29/11-release-gates-receipts.md).
#
# Run from the beam4pm repo root (after `bash scripts/actuation_sync.sh` has
# manufactured generated/elixir/lib/beam4pm_actuation.ex):
#
#     mix run scripts/actuation_selfmine.exs
#
# What it does, and hard-asserts (exits nonzero on any failure):
#
#   1. Performs N=3 ADMITTED actuations + 1 REFUSED actuation through the
#      REAL BeamPM.Actuation.run/2 against the real toy-counter gym bridge
#      (qualification/fixtures/toy_gym_bridge.py) -- every action is drawn
#      from BeamPM.Actuation.admitted_actuations/0's own graph-derived
#      allowlist (never hardcoded outside it), except the deliberately
#      out-of-allowlist refused action.
#   2. Re-reads all 4 consequence receipt FILES from disk (the file is the
#      artifact, not the in-memory return value), decodes every events[]
#      entry back through BeamPM.Codec.from_map(:ocel_event, ...).
#   3. Mines the actuation process itself:
#      BeamPM.Discovery.traces_from_events(events, "case_id") +
#      dfg_from_traces, and prints the mined DFG.
#   4. Asserts: (a) exactly 4 traces; (b) every admitted trace contains the
#      consecutive plan -> admit -> execute -> observe chain; (c) the
#      refused trace contains plan -> admit but NO execute edge -- refusal
#      is visible as process structure, not just as a boolean in a receipt.
#
# Environment knobs (all defaulted):
#
#   BEAM4PM_BRIDGE       path to the gym bridge python script
#                        (default: qualification/fixtures/toy_gym_bridge.py)
#   BEAM4PM_GYM          gym name passed as --gym (default: toy-counter)
#   BEAM4PM_RECEIPTS_DIR consequence receipt output dir
#                        (default: receipts/actuation-selfmine)

defmodule Beam4PM.Script.ActuationSelfmine do
  alias BeamPM.Codec
  alias BeamPM.Discovery
  alias BeamPM.Types.DfgEdge
  alias BeamPM.Types.LogTrace

  @admitted_chain ["plan", "admit", "execute", "observe"]
  @refused_chain ["plan", "admit"]

  def main do
    bridge = System.get_env("BEAM4PM_BRIDGE", "qualification/fixtures/toy_gym_bridge.py")
    gym = System.get_env("BEAM4PM_GYM", "toy-counter")
    receipts_dir = System.get_env("BEAM4PM_RECEIPTS_DIR", "receipts/actuation-selfmine")

    unless File.exists?(bridge) do
      fail("gym bridge not found at #{inspect(bridge)} (set BEAM4PM_BRIDGE)")
    end

    run_tag = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%S")

    # -- 1. Plan lawful candidates (SELECT), then actuate each (ADMIT/DO). --
    # The admitted names/preconditions are read from the module's own
    # graph-derived allowlist -- never hardcoded outside it. The one
    # deliberately-refused action is drawn from OUTSIDE that allowlist. A
    # candidate carries no execution authority either way; only run/2's
    # internal admission step decides.
    allow = BeamPM.Actuation.admitted_actuations()

    unless map_size(allow) >= 2 do
      fail("BeamPM.Actuation.admitted_actuations/0 returned fewer than 2 names: #{inspect(allow)}")
    end

    [a1, a2 | _] = Map.keys(allow) |> Enum.sort()
    refused_name = "erase_world"

    if Map.has_key?(allow, refused_name) do
      fail("fixture assumption broken: #{inspect(refused_name)} is on the allowlist")
    end

    specs = [
      {"#{run_tag}-act1", a1},
      {"#{run_tag}-act2", a2},
      {"#{run_tag}-act3", a1},
      {"#{run_tag}-act4-refused", refused_name}
    ]

    receipts =
      for {run_id, action_name} <- specs do
        preconditions = Map.get(allow, action_name, %{requires: []}) |> Map.get(:requires, [])

        action_input = %{
          action_name: action_name,
          preconditions: preconditions,
          effects: ["gym_state_advanced"]
        }

        case BeamPM.Actuation.run(action_input,
               gym: gym,
               bridge: bridge,
               run_id: run_id,
               receipts_dir: receipts_dir
             ) do
          {:ok, %{receipt_path: path}} ->
            receipt = JSON.decode!(File.read!(path))
            IO.puts("actuated #{run_id} (#{action_name}) -> #{path}")
            {run_id, receipt}

          {:error, _reason} ->
            # A refused/failed run still guarantees exactly one receipt on
            # disk at <receipts_dir>/<run_id>.json -- re-read it from there
            # (the file is the artifact, not the in-memory error tuple).
            path = Path.join(receipts_dir, run_id <> ".json")

            unless File.exists?(path) do
              fail("#{run_id} (#{action_name}) errored with no receipt written at #{path}")
            end

            receipt = JSON.decode!(File.read!(path))
            IO.puts("actuated #{run_id} (#{action_name}) -> #{path} (refused/failed, receipted)")
            {run_id, receipt}
        end
      end

    # -- 2. Sanity-check the receipts against the fixed brce/v1 shape. ------
    for {run_id, receipt} <- receipts do
      assert(
        receipt["receipt_schema"] == "beam4pm-brce/v1",
        "#{run_id}: receipt_schema is #{inspect(receipt["receipt_schema"])}"
      )
    end

    {refused, admitted} =
      Enum.split_with(receipts, fn {_run_id, r} -> r["admission"]["admitted"] == false end)

    assert(length(admitted) == 3, "expected 3 admitted receipts, got #{length(admitted)}")
    assert(length(refused) == 1, "expected 1 refused receipt, got #{length(refused)}")

    for {run_id, r} <- admitted do
      assert(r["execution"]["performed"] == true, "#{run_id}: admitted but not performed")
      assert(is_number(r["execution"]["reward"]), "#{run_id}: no real reward recorded")
    end

    [{refused_case, refused_receipt}] = refused

    assert(
      refused_receipt["execution"]["performed"] == false,
      "#{refused_case}: refused action was performed - authority boundary breached"
    )

    assert(
      refused_receipt["admission"]["policy_decision"]["verdict"] == "refused",
      "#{refused_case}: policy_decision.verdict is #{inspect(refused_receipt["admission"]["policy_decision"]["verdict"])}"
    )

    # -- 3. Dogfood: mine the actuation process from its own receipts. ------
    events =
      for {run_id, receipt} <- receipts, event_map <- receipt["events"] do
        case Codec.from_map(:ocel_event, event_map) do
          {:ok, event} -> event
          {:error, reason} -> fail("#{run_id}: undecodable ocel_event #{inspect(reason)}")
        end
      end

    traces = Discovery.traces_from_events(events, "case_id")
    dfg = Discovery.dfg_from_traces(traces)

    IO.puts("\nmined actuation-process DFG (#{length(events)} events, #{length(traces)} traces):")

    for %DfgEdge{} = edge <- dfg do
      IO.puts(
        "  #{String.pad_trailing(edge.source_activity, 8)} -> " <>
          "#{String.pad_trailing(edge.target_activity, 8)} x#{edge.frequency}"
      )
    end

    # -- 4. Hard assertions over the mined process structure. ---------------
    assert(length(traces) == 4, "(a) expected 4 mined traces, got #{length(traces)}")

    admitted_run_ids = MapSet.new(admitted, fn {run_id, _r} -> run_id end)

    for %LogTrace{} = trace <- traces do
      cond do
        MapSet.member?(admitted_run_ids, trace.case_id) ->
          assert(
            contains_chain?(trace.activity_sequence, @admitted_chain),
            "(b) admitted trace #{trace.case_id} lacks the plan->admit->execute->observe " <>
              "chain: #{inspect(trace.activity_sequence)}"
          )

        trace.case_id == refused_case ->
          assert(
            contains_chain?(trace.activity_sequence, @refused_chain),
            "(c) refused trace #{trace.case_id} lacks the plan->admit chain: " <>
              inspect(trace.activity_sequence)
          )

          assert(
            "execute" not in trace.activity_sequence,
            "(c) refused trace #{trace.case_id} contains an execute activity: " <>
              inspect(trace.activity_sequence)
          )

        true ->
          fail("mined a trace for an unknown case: #{inspect(trace.case_id)}")
      end
    end

    # The same fact at DFG level: refusal shows up as frequency loss across
    # the admit -> execute edge, and as the absence of any refused-side
    # execute edge.
    assert(edge_freq(dfg, "plan", "admit") == 4, "DFG: plan->admit frequency != 4")
    assert(edge_freq(dfg, "admit", "execute") == 3, "DFG: admit->execute frequency != 3")
    assert(edge_freq(dfg, "execute", "observe") == 3, "DFG: execute->observe frequency != 3")

    IO.puts("""

    all assertions passed:
      (a) 4 traces mined from 4 real BeamPM.Actuation.run/2 consequence receipts
      (b) 3 admitted traces each carry plan->admit->execute->observe
      (c) 1 refused trace stops at plan->admit (no execute edge) -
          the refusal is visible as process structure
    receipts: #{receipts_dir}
    """)
  end

  # True when `chain` occurs as a consecutive subsequence of `sequence`.
  defp contains_chain?(sequence, chain) when is_list(sequence) do
    n = length(chain)

    sequence
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.any?(&(&1 == chain))
  end

  defp edge_freq(dfg, source, target) do
    case Enum.find(dfg, &(&1.source_activity == source and &1.target_activity == target)) do
      %DfgEdge{frequency: f} -> f
      nil -> 0
    end
  end

  defp assert(true, _msg), do: :ok
  defp assert(false, msg), do: fail(msg)

  defp fail(msg) do
    IO.puts(:stderr, "actuation_selfmine: FAIL: #{msg}")
    System.halt(1)
  end
end

Beam4PM.Script.ActuationSelfmine.main()
