# revenue_suite_demo.exs -- end-to-end demo of the beam4pm-pro-revenue-suite.
#
# Run from the beam4pm repo root:
#
#     mix run scripts/revenue_suite_demo.exs
#
# Five stages, every collaborator real (Chicago discipline -- no stubs, no
# canned data; the only inputs are committed fixtures and the shipped
# generated modules):
#
#   1. Rework-cost ledger: BeamPM.Revenue.Xes.parse_file/1 over all three
#      committed BPI-2020 fixtures (qualification/fixtures/bpi2020/*.xes),
#      BeamPM.Discovery.traces_from_events/2, then
#      BeamPM.Revenue.Economics.rework_cost/2 -- prints loop-bearing cases and
#      the amount-weighted total.
#   2. Cycle-to-cash: BeamPM.Revenue.Economics.cycle_to_cash/2 -- per-log
#      stats over the SUBMITTED -> "Payment Handled" span, plus the
#      open-obligation cases that never reached payment (no fabricated
#      durations for those).
#   3. Conformance leakage: DFG model mined from the paid_clean stratum
#      (has "Payment Handled", zero " REJECTED by " activities) via the
#      existing BeamPM.Discovery.dfg_from_traces/1, remaining traces scored
#      with BeamPM.Revenue.Economics.conformance_leakage/3; prints findings
#      with amount-at-risk. Vocabulary: DFG adjacent-pair fitness + ETC
#      escaping-edge precision -- NOT alignment-based conformance.
#   4. Metering pipeline: BeamPM.Revenue.Metering.emit_usage_events/4 ->
#      admit_entitled_usage/2 against a REAL folded entitlement pair (an
#      ACTIVE fold and a CANCELLED fold built through
#      BeamPM.Entitlement.reconcile_entitlement/2, never hand-built states)
#      -> BeamPM.Billing.reconcile/4. Prints total_quantity, refusal counts
#      by reason, and the dedup proof: a double emission reconciles to the
#      identical receipt.
#   5. Claude workflow receipt: the BeamPM.ClaudeWorkflowReactor DAG run on
#      qualification/fixtures/claude-workflows/journal.jsonl (this repo's own
#      real 19-agent manufacturing journal). Spans are journal-line ordinal
#      distances, never wall-clock time (the journal carries no timestamps).
#
# Honesty labels: every printed money figure carries
# "(rescaled units — BPI-2020 anonymized amounts, not EUR)" -- the public
# BPI-2020 logs anonymize amounts by rescaling, so figures demonstrate the
# computation, not real currency. No prices/rates exist anywhere in the
# suite (docs/jira/v26.8.29/05-pricing-packaging-unit-economics.md line 93:
# price levels are UNKNOWN by doctrine); metering manufactures denominators
# only.
#
# Exit behavior: the script halts with a nonzero exit the moment any
# pipeline stage returns an error tuple (or a required module/fixture is
# absent). No stage failure is ever swallowed into a partial report.

defmodule Beam4PM.RevenueSuiteDemo do
  @moduledoc false

  @money_label "(rescaled units — BPI-2020 anonymized amounts, not EUR)"
  @fixture_dir "qualification/fixtures/bpi2020"
  @journal_path "qualification/fixtures/claude-workflows/journal.jsonl"
  @fixtures [
    international: "international_50.xes",
    domestic: "domestic_50.xes",
    rfp: "rfp_50.xes"
  ]
  # Half-open reconciliation window bracketing every fixture event
  # (fixture timestamps span 2016-10-05 .. 2018-04-13; comparison is the
  # billing module's raw-binary ISO8601 ordering, so year digits decide).
  @period {"2015-01-01T00:00:00Z", "2020-01-01T00:00:00Z"}
  @metric "beam4pm.estate.governed_cases"

  @required_modules [
    BeamPM.Revenue.Xes,
    BeamPM.Revenue.Economics,
    BeamPM.Revenue.Metering,
    BeamPM.ClaudeWorkflowReactor,
    BeamPM.Discovery,
    BeamPM.Billing,
    BeamPM.Billing.UsageEvent,
    BeamPM.Entitlement,
    BeamPM.Entitlement.EntitlementEvent
  ]

  def main do
    preflight()
    parsed = parse_all_fixtures()
    stage1_rework_cost(parsed)
    stage2_cycle_to_cash(parsed)
    stage3_conformance_leakage(parsed[:international])
    stage4_metering(parsed)
    stage5_workflow_receipt()
    IO.puts("\nAll five pipeline stages completed without an error tuple.")
  end

  # -- preflight ------------------------------------------------------------

  defp preflight do
    for mod <- @required_modules do
      case Code.ensure_loaded(mod) do
        {:module, ^mod} ->
          :ok

        {:error, reason} ->
          die(
            "required module #{inspect(mod)} is not loadable (#{inspect(reason)}). " <>
              "Generate the revenue suite first: scripts/revenue_economics_sync.sh, " <>
              "scripts/revenue_metering_sync.sh, scripts/claude_workflow_reactor_sync.sh."
          )
      end
    end

    for {_key, file} <- @fixtures do
      path = Path.join(@fixture_dir, file)
      File.exists?(path) || die("missing committed fixture #{path}")
    end

    File.exists?(@journal_path) ||
      die("missing committed fixture #{@journal_path} (the 19-agent workflow journal)")
  end

  # -- fixture parsing ------------------------------------------------------

  defp parse_all_fixtures do
    for {key, file} <- @fixtures do
      path = Path.join(@fixture_dir, file)

      %{events: events, trace_attrs: trace_attrs} =
        ok!(BeamPM.Revenue.Xes.parse_file(path), "Xes.parse_file(#{path})")

      traces = BeamPM.Discovery.traces_from_events(events, "case")

      IO.puts(
        "parsed #{file}: #{length(events)} events, #{length(traces)} traces, " <>
          "#{map_size(trace_attrs)} trace-attribute rows"
      )

      {key, %{path: path, events: events, trace_attrs: trace_attrs, traces: traces}}
    end
  end

  # -- stage 1: rework-cost ledger ------------------------------------------

  defp stage1_rework_cost(parsed) do
    banner("STAGE 1 -- rework-cost ledger (REJECTED-then-resubmitted loops)")

    for {key, %{traces: traces, trace_attrs: trace_attrs}} <- parsed do
      %{per_case: per_case, loop_case_ids: loop_case_ids, total_weighted_cost: total} =
        ok!(
          BeamPM.Revenue.Economics.rework_cost(traces, trace_attrs),
          "Economics.rework_cost (#{key})"
        )

      IO.puts(
        "  #{key}: #{length(loop_case_ids)} loop-bearing cases of #{length(traces)}; " <>
          "total weighted rework cost #{money(total)}"
      )

      if key == :international do
        per_case
        |> Enum.filter(&(&1.loop_count > 0))
        |> Enum.sort_by(& &1.weighted_cost, :desc)
        |> Enum.take(10)
        |> Enum.each(fn row ->
          IO.puts(
            "    #{row.case_id}: #{row.loop_count} loop(s), " <>
              "weighted cost #{money(row.weighted_cost)}"
          )
        end)
      end
    end
  end

  # -- stage 2: cycle-to-cash -----------------------------------------------

  defp stage2_cycle_to_cash(parsed) do
    banner("STAGE 2 -- cycle-to-cash (first SUBMITTED -> Payment Handled)")

    for {key, %{traces: traces, events: events}} <- parsed do
      %{
        case_stats: case_stats,
        sojourns: sojourns,
        cycle_to_cash: cycle_to_cash,
        open_obligations: open_obligations
      } =
        ok!(
          BeamPM.Revenue.Economics.cycle_to_cash(traces, events),
          "Economics.cycle_to_cash (#{key})"
        )

      durations = Map.values(cycle_to_cash)

      stats_line =
        case durations do
          [] ->
            "no case reached payment"

          _ ->
            mean = Enum.sum(durations) / length(durations)

            "min #{days(Enum.min(durations))}d / mean #{days(mean)}d / " <>
              "max #{days(Enum.max(durations))}d"
        end

      IO.puts(
        "  #{key}: #{map_size(cycle_to_cash)} paid cases (#{stats_line}); " <>
          "#{length(open_obligations)} open obligations (no Payment Handled, no " <>
          "fabricated duration); #{length(case_stats)} CaseStats + " <>
          "#{length(sojourns)} SojournTime records emitted via validating new/1"
      )

      if open_obligations != [] do
        IO.puts("    open: #{Enum.join(Enum.sort(open_obligations), ", ")}")
      end
    end
  end

  # -- stage 3: conformance leakage -----------------------------------------

  defp stage3_conformance_leakage(%{traces: traces, trace_attrs: trace_attrs}) do
    banner("STAGE 3 -- conformance leakage vs the paid_clean model (international)")

    {model_traces, scored_traces} =
      Enum.split_with(traces, fn t ->
        "Payment Handled" in t.activity_sequence and
          not Enum.any?(t.activity_sequence, &String.contains?(&1, " REJECTED by "))
      end)

    model_edges = BeamPM.Discovery.dfg_from_traces(model_traces)

    IO.puts(
      "  model: #{length(model_traces)} paid_clean traces -> #{length(model_edges)} DFG edges; " <>
        "scoring the other #{length(scored_traces)} traces"
    )

    findings =
      BeamPM.Revenue.Economics.conformance_leakage(model_edges, scored_traces, trace_attrs)
      |> ok!("Economics.conformance_leakage")
      |> extract_findings()

    # Sorted-ascending canonical summation (the reconcile_billing
    # float-determinism discipline); nil-amount findings stay unweighted.
    amounts =
      findings |> Enum.map(& &1.amount_at_risk) |> Enum.reject(&is_nil/1) |> Enum.sort()

    total_at_risk = Enum.reduce(amounts, 0.0, &(&1 + &2))
    unweighted = Enum.count(findings, &is_nil(&1.amount_at_risk))

    IO.puts(
      "  #{length(findings)} leakage findings (fitness < 1.0); " <>
        "amount at risk #{money(total_at_risk)}; #{unweighted} unweighted (no amount attr)"
    )

    findings
    |> Enum.sort_by(&(&1.amount_at_risk || -1.0), :desc)
    |> Enum.take(5)
    |> Enum.each(fn f ->
      IO.puts(
        "    #{f.case_id}: fitness #{Float.round(f.fitness, 4)}, " <>
          "precision #{inspect(f.precision)}, at risk #{money(f.amount_at_risk)}"
      )
    end)

    IO.puts(
      "  vocabulary: DFG adjacent-pair fitness + ETC escaping-edge precision " <>
        "(alpha 0.0) -- NOT alignment-based conformance"
    )
  end

  defp extract_findings(rows) when is_list(rows), do: rows
  defp extract_findings(%{findings: rows}) when is_list(rows), do: rows

  defp extract_findings(other),
    do: die("conformance_leakage returned an unrecognized shape: #{inspect(other)}")

  # -- stage 4: metering pipeline -------------------------------------------

  defp stage4_metering(parsed) do
    banner("STAGE 4 -- metering: emit -> admit_entitled_usage -> reconcile")

    {period_start, period_end} = @period

    # Real entitlement folds through the shipped reconcile_entitlement/2 --
    # never hand-built states. One stays ACTIVE; one is folded all the way
    # to CANCELLED with a 2016 watermark, so every 2017+ fixture usage event
    # against it lands after cancellation.
    active_state =
      fold_entitlement("ent-intl-active", [
        {"ENTITLEMENT_CREATION_REQUESTED", "2015-06-01T00:00:00Z"},
        {"ENTITLEMENT_ACTIVE", "2015-06-02T00:00:00Z"}
      ])

    cancelled_state =
      fold_entitlement("ent-dom-cancelled", [
        {"ENTITLEMENT_CREATION_REQUESTED", "2016-01-01T00:00:00Z"},
        {"ENTITLEMENT_ACTIVE", "2016-01-02T00:00:00Z"},
        {"ENTITLEMENT_CANCELLING", "2016-01-03T00:00:00Z"},
        {"ENTITLEMENT_CANCELLED", "2016-01-04T00:00:00Z"}
      ])

    IO.puts(
      "  folded entitlements: ent-intl-active=#{active_state.status}, " <>
        "ent-dom-cancelled=#{cancelled_state.status}"
    )

    states = %{
      active_state.entitlement_id => active_state,
      cancelled_state.entitlement_id => cancelled_state
    }

    intl_usage = emit(parsed[:international].events, "ent-intl-active")
    dom_usage = emit(parsed[:domestic].events, "ent-dom-cancelled")

    adversarial = [
      # entitlement_id no fold ever produced -> :unknown_entitlement
      usage_event!("adv-unknown-1", "ent-never-folded", 1.0, "2017-06-01T00:00:00Z"),
      # negative quantity on a live entitlement -> :negative_quantity
      usage_event!("adv-negative-1", "ent-intl-active", -1.0, "2017-06-01T00:00:00Z"),
      # non-ISO8601 occurred_at on a live entitlement -> :malformed_occurred_at
      usage_event!("adv-malformed-1", "ent-intl-active", 1.0, "not-a-timestamp")
    ]

    all_usage = intl_usage ++ dom_usage ++ adversarial

    %{billable: billable, refusals: refusals} =
      ok!(
        BeamPM.Revenue.Metering.admit_entitled_usage(all_usage, states),
        "Metering.admit_entitled_usage"
      )

    conservation = length(billable) + length(refusals) == length(all_usage)

    conservation ||
      die(
        "conservation violated: #{length(billable)} billable + #{length(refusals)} " <>
          "refusals != #{length(all_usage)} input events"
      )

    IO.puts(
      "  admitted #{length(billable)} billable of #{length(all_usage)} " <>
        "(conservation holds: billable + refusals == input)"
    )

    refusals
    |> Enum.frequencies_by(& &1.reason)
    |> Enum.sort()
    |> Enum.each(fn {reason, count} -> IO.puts("    refused #{inspect(reason)}: #{count}") end)

    recon = reconcile(billable, "single emission")

    IO.puts(
      "  reconciled ent-intl-active/#{@metric}: total_quantity " <>
        "#{recon.total_quantity} governed cases across " <>
        "#{length(recon.applied_event_ids)} applied event ids " <>
        "(a case count, not a money figure; no rates exist anywhere -- 05:93)"
    )

    # Dedup proof: a full second emission pass concatenated onto the first
    # must reconcile to the identical receipt (deterministic sha256 event
    # ids dedup inside the shipped BeamPM.Billing.reconcile/4).
    doubled = intl_usage ++ emit(parsed[:international].events, "ent-intl-active")

    %{billable: doubled_billable} =
      ok!(
        BeamPM.Revenue.Metering.admit_entitled_usage(doubled, states),
        "Metering.admit_entitled_usage (double emission)"
      )

    recon2 = reconcile(doubled_billable, "double emission")

    recon2 == recon ||
      die(
        "double-emission dedup FAILED: reconciliation differs from single emission\n" <>
          "  single: #{inspect(recon)}\n  double: #{inspect(recon2)}"
      )

    IO.puts(
      "  dedup proof: #{length(doubled_billable)} billable events from the double " <>
        "emission reconcile to the identical receipt (total_quantity " <>
        "#{recon2.total_quantity}, #{length(recon2.applied_event_ids)} ids) -- " <>
        "zero double-billing"
    )
  end

  defp emit(events, entitlement_id) do
    case BeamPM.Revenue.Metering.emit_usage_events(events, entitlement_id, @metric, @period) do
      {:ok, events} when is_list(events) -> events
      events when is_list(events) -> events
      {:error, reason} -> die("Metering.emit_usage_events(#{entitlement_id}): #{inspect(reason)}")
      other -> die("Metering.emit_usage_events returned unrecognized shape: #{inspect(other)}")
    end
  end

  defp reconcile(billable, label) do
    case BeamPM.Billing.reconcile(billable, "ent-intl-active", @metric, @period) do
      {:error, reason} -> die("Billing.reconcile (#{label}): #{inspect(reason)}")
      recon -> recon
    end
  end

  defp fold_entitlement(entitlement_id, lifecycle) do
    Enum.reduce(lifecycle, nil, fn {event_type, effective_at}, state ->
      event =
        ok!(
          BeamPM.Entitlement.EntitlementEvent.new(%{
            event_id: "#{entitlement_id}|#{event_type}|#{effective_at}",
            entitlement_id: entitlement_id,
            event_type: event_type,
            effective_at: effective_at
          }),
          "EntitlementEvent.new(#{event_type})"
        )

      case BeamPM.Entitlement.reconcile_entitlement(state, event) do
        {:error, reason} ->
          die("reconcile_entitlement(#{entitlement_id}, #{event_type}): #{inspect(reason)}")

        next_state ->
          next_state
      end
    end)
  end

  defp usage_event!(event_id, entitlement_id, quantity, occurred_at) do
    ok!(
      BeamPM.Billing.UsageEvent.new(%{
        event_id: event_id,
        entitlement_id: entitlement_id,
        quantity: quantity,
        metric_name: @metric,
        occurred_at: occurred_at
      }),
      "UsageEvent.new(#{event_id})"
    )
  end

  # -- stage 5: Claude workflow receipt -------------------------------------

  defp stage5_workflow_receipt do
    banner("STAGE 5 -- Claude workflow receipt (Reactor DAG over the real journal)")

    {:ok, _} = Application.ensure_all_started(:reactor)

    result =
      if function_exported?(BeamPM.ClaudeWorkflowReactor, :run, 1) do
        BeamPM.ClaudeWorkflowReactor.run(@journal_path)
      else
        Reactor.run(
          BeamPM.ClaudeWorkflowReactor,
          %{journal_path: @journal_path},
          %{},
          async?: false
        )
      end

    receipt = ok!(result, "ClaudeWorkflowReactor run")

    IO.puts(
      "  journal sha256 #{receipt.journal_sha256}\n" <>
        "  total agents: #{receipt.total_agents} across #{length(receipt.waves)} waves"
    )

    Enum.each(receipt.waves, fn wave ->
      IO.puts(
        "    wave #{wave.phase}: #{wave.agent_count} agent(s), " <>
          "ordinal span #{inspect(wave.ordinal_span)} " <>
          "(journal-line distance, not wall-clock time)"
      )
    end)

    IO.puts(
      "  phase labels are the documented ordinal heuristic over wave structure " <>
        "(measure -> design -> develop -> actuate -> qualify)"
    )
  end

  # -- shared helpers -------------------------------------------------------

  defp ok!({:ok, value}, _stage), do: value
  defp ok!({:error, reason}, stage), do: die("#{stage} returned an error tuple: #{inspect(reason)}")
  defp ok!(value, _stage), do: value

  defp money(nil), do: "n/a (trace carries no Amount/RequestedAmount attribute)"

  defp money(value) when is_number(value),
    do: "#{:erlang.float_to_binary(value / 1, decimals: 2)} #{@money_label}"

  defp days(seconds), do: Float.round(seconds / 86_400, 2)

  defp banner(title) do
    IO.puts("\n== #{title}")
  end

  defp die(message) do
    IO.puts(:stderr, "revenue_suite_demo: #{message}")
    System.halt(1)
  end
end

Beam4PM.RevenueSuiteDemo.main()
