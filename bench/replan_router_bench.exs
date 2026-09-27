# Deterministic latency benchmark + regression court for the pure replanning
# ladder BeamPM.ReplanRouter.route/2 and the BeamPM.PlanLineage hash chain
# (PR #91).
#
#   MIX_ENV=test mix run --no-start bench/replan_router_bench.exs [receipt.json]
#
# Real collaborators only: real router structs, real sha256 canonical-JSON
# digests, real OCEL event structs. No engine is involved (route/2 is pure),
# so the court is host-portable. Each case runs WARMUP untimed iterations,
# then N timed iterations measured with :timer.tc around the exact public
# call on a FIXED input state (route/2 is pure, so every iteration does the
# same work).
#
# Court (all on the MINIMUM sample, nanoseconds, :timer.tc/2 with :nanosecond; on an oversubscribed host
# p50/p95 measure scheduler contention, the minimum estimates intrinsic cost):
#
#   1. relative: min_ns <= ratio * D, where D = min_ns of `digest_ref` (one
#      PlanLineage.digest/1 of an admitted preimage, measured in the same run).
#      This counts canonical-JSON sha256 digests and is load/host invariant.
#   2. absolute: min_ns <= bound_min_ns, about 10x the recorded minimum, a
#      backstop against the digest itself regressing.
#   3. scaling: a route on a state holding 4_000 prior events / a 2_000-link
#      lineage must stay within `ratio` of the same route on a fresh state --
#      a per-decision cost that grows with history (the O(n) `events ++ [e]`
#      append, a lineage re-verify per route) is caught here.
#
# p50/p95/max and the host load average are observation only.
alias BeamPM.{PlanLineage, ReplanRouter}

n = String.to_integer(System.get_env("REPLAN_BENCH_N", "2000"))
warmup = 200

preimage = %{subject: "sha-subject", pack: "sha-pack", policy: "sha-policy", world: "sha-world"}

plan = %{
  "solved" => true,
  "policy" =>
    for(
      i <- 0..31,
      do: %{"state" => "s#{i}", "action" => "a#{i}", "outcomes" => [%{"state" => "g"}]}
    )
}

policy_pre = %{preimage | policy: ReplanRouter.policy_digest(plan)}
fresh = ReplanRouter.new(plan_id: "plan-b", preimage: preimage, run_id: "bench")

policy_st =
  ReplanRouter.new(plan_id: "plan-b", preimage: policy_pre, universal_plan: plan, run_id: "bench")

obs = fn extra ->
  Map.merge(
    %{
      preimage: preimage,
      conformance: :deviates,
      plan_valid: false,
      observed_at: "2026-09-26T00:00:00Z"
    },
    Map.new(extra)
  )
end

# A long-history state: 4_000 routed decisions (events) and a 2_000-link lineage.
long =
  Enum.reduce(1..4_000, fresh, fn i, st ->
    o = if rem(i, 2) == 0, do: obs.(conformance: :conforms, plan_valid: true), else: obs.([])
    {_, _, st} = ReplanRouter.route(o, st)
    st
  end)

lineage_1000 =
  Enum.reduce(1..1_000, PlanLineage.new(), fn i, ch ->
    {_, ch} = PlanLineage.derive(ch, "p#{i}", %{"i" => i})
    ch
  end)

cont = obs.(conformance: :conforms, plan_valid: true)
step = obs.([])
stale = obs.(preimage: %{preimage | world: "drift"})
bad_keys = obs.([]) |> Map.put("goal_met", true)

follow = %{
  preimage: policy_pre,
  conformance: :deviates,
  policy_state: "s31",
  observed_at: "2026-09-26T00:00:00Z"
}

# {name, ratio_vs_digest, fun, expectation}
cases = [
  {:digest_ref, nil, fn -> PlanLineage.digest(preimage) end, fn h -> 64 = byte_size(h) end},
  {:route_continue, 3, fn -> ReplanRouter.route(cont, fresh) end,
   fn {:continue, _, _} -> :ok end},
  {:route_ladder_step, 12, fn -> ReplanRouter.route(step, fresh) end,
   fn {:session_replan, _, _} -> :ok end},
  {:route_refuse_stale, 8, fn -> ReplanRouter.route(stale, fresh) end,
   fn {:refuse_stale, _, _} -> :ok end},
  {:route_refuse_non_atom_keys, 2, fn -> ReplanRouter.route(bad_keys, fresh) end,
   fn {:refuse_malformed, %{reason: :non_atom_keys}, _} -> :ok end},
  {:route_follow_policy_32, 60, fn -> ReplanRouter.route(follow, policy_st) end,
   fn {:follow_policy, %{action: "a31"}, _} -> :ok end},
  {:route_continue_long_history, 3, fn -> ReplanRouter.route(cont, long) end,
   fn {:continue, _, _} -> :ok end},
  {:route_ladder_step_long_history, 12, fn -> ReplanRouter.route(step, long) end,
   fn {:session_replan, _, _} -> :ok end},
  {:lineage_verify_1000, 2800, fn -> PlanLineage.verify(lineage_1000) end, fn :ok -> :ok end}
]

measure = fn fun, check ->
  check.(fun.())
  for _ <- 1..warmup, do: fun.()

  samples =
    for _ <- 1..n do
      {ns, _} = :timer.tc(fun, :nanosecond)
      ns
    end
    |> Enum.sort()

  pct = fn p -> Enum.at(samples, min(length(samples) - 1, trunc(p * length(samples)))) end
  %{min_ns: hd(samples), p50_ns: pct.(0.5), p95_ns: pct.(0.95), max_ns: List.last(samples)}
end

results =
  Map.new(cases, fn {name, ratio, fun, check} -> {name, {ratio, measure.(fun, check)}} end)

{_, %{min_ns: d}} = results[:digest_ref]
d = max(d, 1)

# Absolute backstops (ns): ~10x the minima recorded in the committed receipt.
abs_bounds = %{
  digest_ref: 20_000,
  route_continue: 15_000,
  route_ladder_step: 100_000,
  route_refuse_stale: 50_000,
  route_refuse_non_atom_keys: 10_000,
  route_follow_policy_32: 500_000,
  route_continue_long_history: 15_000,
  route_ladder_step_long_history: 100_000,
  lineage_verify_1000: 25_000_000
}

# history scaling: long-history route min <= ratio * fresh route min
scaling = [
  {:route_continue_long_history, :route_continue, 3.0},
  {:route_ladder_step_long_history, :route_ladder_step, 3.0}
]

case_verdicts =
  for {name, {ratio, m}} <- results, into: %{} do
    rel_ok = ratio == nil or m.min_ns <= ratio * d
    abs_ok = m.min_ns <= Map.fetch!(abs_bounds, name)

    {name,
     Map.merge(m, %{
       ratio_bound: ratio,
       digests: Float.round(m.min_ns / d, 2),
       bound_min_ns: Map.fetch!(abs_bounds, name),
       pass: rel_ok and abs_ok
     })}
  end

scaling_verdicts =
  for {long_case, base_case, ratio} <- scaling do
    lm = case_verdicts[long_case].min_ns
    bm = max(case_verdicts[base_case].min_ns, 1)

    %{
      long: long_case,
      base: base_case,
      ratio_bound: ratio,
      observed: Float.round(lm / bm, 2),
      pass: lm <= ratio * bm
    }
  end

failed =
  (for({k, v} <- case_verdicts, not v.pass, do: Atom.to_string(k)) ++
     for(s <- scaling_verdicts, not s.pass, do: "scaling:#{s.long}"))
  |> Enum.sort()

receipt = %{
  "schema" => "beam4pm/bench-receipt/1",
  "subject" => "BeamPM.ReplanRouter.route/2 + BeamPM.PlanLineage (PR #91)",
  "n" => n,
  "warmup" => warmup,
  "digest_ref_min_ns" => d,
  "host_load_avg" => :os.cmd(~c"uptime") |> to_string() |> String.trim(),
  "otp" => System.otp_release(),
  "elixir" => System.version(),
  "cases" => Map.new(case_verdicts, fn {k, v} -> {Atom.to_string(k), v} end),
  "scaling" => scaling_verdicts,
  "failed_cases" => failed,
  "pass" => failed == [],
  "authority" => "NONE"
}

json = JSON.encode!(receipt)

case System.argv() do
  [path | _] -> File.write!(path, json)
  _ -> :ok
end

IO.puts(json)

if failed != [] do
  IO.puts(:stderr, "REGRESSION: court failed in #{Enum.join(failed, ", ")}")
  System.halt(1)
end
