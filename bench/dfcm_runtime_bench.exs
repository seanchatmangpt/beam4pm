# Deterministic latency benchmark + regression court for the live DfCM /
# Ferroplan repair runtime (BeamPM.Dfcm, PR #89).
#
#   MIX_ENV=test mix run --no-start bench/dfcm_runtime_bench.exs [receipt.json]
#
# Real collaborators only: the real ferroplan wasm engine hosted by wasmex,
# real sessions, real forks. Each case runs WARMUP untimed iterations, then N
# timed iterations measured with :timer.tc around the exact public call.
# Bounds are regression ceilings on the MINIMUM sample (microseconds): on a
# shared, oversubscribed host p50/p95 measure scheduler contention, while the
# minimum over N runs estimates the intrinsic cost of the path. Ceilings sit
# well above the recorded baseline so load noise does not flap, but an
# order-of-magnitude regression (an accidental full replan on the reuse path,
# a boundary guard that starts calling the engine) exits with status 1. A
# second, load-invariant court requires the median boundary refusal to be cheaper
# than the cheapest engine-backed call. p50/p95/max and the host load average
# are recorded as observation, not as the court.
alias BeamPM.{Dfcm, Ferroplan}

unless Ferroplan.wasm_built?() do
  IO.puts(:stderr, "BLOCKED: " <> Ferroplan.wasm_missing_reason())
  System.halt(2)
end

case Ferroplan.start() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

domain = """
(define (domain rooms)
  (:requirements :strips :typing)
  (:types room)
  (:predicates (at ?r - room) (link ?a - room ?b - room))
  (:action go
    :parameters (?a - room ?b - room)
    :precondition (and (at ?a) (link ?a ?b))
    :effect (and (at ?b) (not (at ?a)))))
)
"""

problem = """
(define (problem three-room)
  (:domain rooms)
  (:objects a b c - room)
  (:init (at a) (link a b) (link b c) (link c b))
  (:goal (at b)))
"""

n = String.to_integer(System.get_env("DFCM_BENCH_N", "200"))
warmup = 20

{:ok, %{"handle" => parent}} = Ferroplan.session_new(domain, problem)
{:ok, %{"solved" => true}} = Ferroplan.session_think(parent, 10_000, 64)

fresh_fork = fn ->
  {:ok, %{"handle" => fork}} = Ferroplan.session_fork(parent)
  {:ok, %{"solved" => true}} = Ferroplan.session_think(fork, 10_000, 64)
  fork
end

drift = [{"(at a)", false}, {"(at c)", true}]

cases = [
  {:boundary_refusal_contradiction, 1_000,
   fn ->
     {nil,
      fn _ -> Dfcm.observe_and_repair_session(parent, [{"(at a)", true}, {"(at a)", false}]) end}
   end, fn {:error, {:contradictory_observations, _}} -> :ok end},
  {:reuse_suffix, 20_000,
   fn ->
     {nil,
      fn _ -> Dfcm.observe_and_repair_session(parent, [{"(at a)", true}], event_id: "bench") end}
   end, fn {:ok, %{decision: :reuse_suffix}} -> :ok end},
  {:drift_full_replan, 60_000,
   fn ->
     {fresh_fork.(),
      fn fork -> Dfcm.observe_and_repair_session(fork, drift, event_id: "bench") end}
   end, fn {:ok, %{trigger: :invalid_plan, plan_id: id}} when is_binary(id) -> :ok end},
  {:probe_three_counterfactuals, 150_000,
   fn ->
     {nil,
      fn _ ->
        Dfcm.probe_session(parent, [
          %{id: "baseline", goal: "(at b)"},
          %{id: "drift", goal: "(at b)", observations: drift},
          %{id: "unreachable", goal: "(at a)", observations: drift}
        ])
      end}
   end, fn {:ok, %{candidate_count: 3}} -> :ok end}
]

percentile = fn sorted, p ->
  Enum.at(sorted, min(length(sorted) - 1, trunc(Float.ceil(p * length(sorted))) - 1))
end

results =
  for {name, bound_min_us, setup, check} <- cases do
    run = fn ->
      {subject, call} = setup.()
      {us, result} = :timer.tc(fn -> call.(subject) end)
      :ok = check.(result)
      if subject, do: {:ok, %{"freed" => true}} = Ferroplan.session_free(subject)
      us
    end

    for _ <- 1..warmup, do: run.()
    samples = Enum.sort(for _ <- 1..n, do: run.())
    sorted = samples

    %{
      "case" => Atom.to_string(name),
      "n" => n,
      "p50_us" => percentile.(sorted, 0.5),
      "p95_us" => percentile.(sorted, 0.95),
      "max_us" => List.last(sorted),
      "min_us" => hd(sorted),
      "bound_min_us" => bound_min_us,
      "within_bound" => hd(sorted) <= bound_min_us
    }
  end

{:ok, %{"freed" => true}} = Ferroplan.session_free(parent)

[guard | engine_backed] = results
guard_cheaper = guard["p50_us"] < Enum.min(Enum.map(engine_backed, & &1["min_us"]))

wasm_sha =
  :crypto.hash(:sha256, File.read!(Ferroplan.wasm_path())) |> Base.encode16(case: :lower)

receipt = %{
  "schema" => "beam4pm/dfcm-runtime-bench/1",
  "subject" => "lib/beam4pm_dfcm.ex",
  "subject_sha256" =>
    :crypto.hash(:sha256, File.read!("lib/beam4pm_dfcm.ex")) |> Base.encode16(case: :lower),
  "ferroplan_wasm_sha256" => wasm_sha,
  "otp" => System.otp_release(),
  "elixir" => System.version(),
  "authority" => "NONE",
  "host_load_avg" => :os.cmd(~c"sysctl -n vm.loadavg") |> to_string() |> String.trim(),
  "court" => "min_us <= bound_min_us per case; boundary refusal p50 < cheapest engine-backed min",
  "results" => results,
  "pass" => Enum.all?(results, & &1["within_bound"]) and guard_cheaper
}

json = JSON.encode!(receipt)
IO.puts(json)

case System.argv() do
  [path | _] -> File.write!(path, json <> "\n")
  _ -> :ok
end

unless receipt["pass"] do
  IO.puts(
    :stderr,
    "REGRESSION: court failed (guard_cheaper=#{guard_cheaper}) in " <>
      Enum.map_join(Enum.reject(results, & &1["within_bound"]), ",", & &1["case"])
  )

  System.halt(1)
end
