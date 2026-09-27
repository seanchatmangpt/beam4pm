# Deterministic latency benchmark + regression court for the live DfCM /
# Ferroplan repair runtime (BeamPM.Dfcm, PR #89).
#
#   MIX_ENV=test mix run --no-start bench/dfcm_runtime_bench.exs [receipt.json]
#
# Real collaborators only: the real ferroplan wasm engine hosted by wasmex,
# real sessions, real forks. Each case runs WARMUP untimed iterations, then N
# timed iterations measured with :timer.tc around the exact public call.
#
# Court (all on the MINIMUM sample, microseconds): on a shared, oversubscribed
# host p50/p95 measure scheduler contention, while the minimum over N runs
# estimates the intrinsic cost of the path. Two bounds per case:
#
#   1. relative: min_us <= ratio * R, where R = min_us of `engine_roundtrip`
#      (one real session_valid? call on the same engine, measured in the same
#      run). This is load- and host-invariant: it counts engine round trips.
#      The boundary guard's ratio is 0.75, so a guard that makes even ONE engine
#      call before refusing (>= 1 R) fails; engine-backed ratios sit about 2x
#      above the recorded round-trip count of each path.
#   2. absolute: min_us <= bound_min_us, about 10x the recorded minimum, as a
#      backstop against the round trip itself regressing.
#
# p50/p95/max and the host load average are recorded as observation only.
# Anti-vacuity mutants (guard calling the engine, a 25ms stall on the reuse
# path) are recorded with their exit codes in the committed receipt.
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
  {:engine_roundtrip, 2_000, nil, fn -> {nil, fn _ -> Ferroplan.session_valid?(parent) end} end,
   fn {:ok, %{"valid" => true}} -> :ok end},
  {:boundary_refusal_contradiction, 150, 0.75,
   fn ->
     {nil,
      fn _ -> Dfcm.observe_and_repair_session(parent, [{"(at a)", true}, {"(at a)", false}]) end}
   end, fn {:error, {:contradictory_observations, _}} -> :ok end},
  {:reuse_suffix, 5_000, 16,
   fn ->
     {nil,
      fn _ -> Dfcm.observe_and_repair_session(parent, [{"(at a)", true}], event_id: "bench") end}
   end, fn {:ok, %{decision: :reuse_suffix}} -> :ok end},
  {:evidence_refused_reuse, 8_000, 25,
   fn ->
     {fresh_fork.(),
      fn fork ->
        Dfcm.observe_and_repair_session(fork, [{"(at a)", true}],
          evidence: %{conforms: false},
          reuse_admissible: false,
          event_id: "bench"
        )
      end}
   end, fn {:ok, %{trigger: :evidence_refused_reuse, decision: :replanned_full}} -> :ok end},
  {:drift_full_replan, 8_000, 25,
   fn ->
     {fresh_fork.(),
      fn fork -> Dfcm.observe_and_repair_session(fork, drift, event_id: "bench") end}
   end, fn {:ok, %{trigger: :invalid_plan, plan_id: id}} when is_binary(id) -> :ok end},
  {:probe_three_counterfactuals, 25_000, 80,
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

run_once = fn {_name, _bound, _ratio, setup, check} ->
  {subject, call} = setup.()
  {us, result} = :timer.tc(fn -> call.(subject) end)
  :ok = check.(result)
  if subject, do: {:ok, %{"freed" => true}} = Ferroplan.session_free(subject)
  us
end

# Round-robin: iteration i runs every case once, so every case (and the
# round-trip baseline the ratios divide by) samples the same load window.
for _ <- 1..warmup, c <- cases, do: run_once.(c)

samples_by_case =
  Enum.reduce(1..n, Map.new(cases, &{elem(&1, 0), []}), fn _, acc ->
    Enum.reduce(cases, acc, fn c, acc2 ->
      Map.update!(acc2, elem(c, 0), &[run_once.(c) | &1])
    end)
  end)

results =
  for {name, bound_min_us, ratio, _setup, _check} <- cases do
    sorted = Enum.sort(Map.fetch!(samples_by_case, name))

    %{
      "case" => Atom.to_string(name),
      "n" => n,
      "p50_us" => percentile.(sorted, 0.5),
      "p95_us" => percentile.(sorted, 0.95),
      "max_us" => List.last(sorted),
      "min_us" => hd(sorted),
      "bound_min_us" => bound_min_us,
      "bound_roundtrip_ratio" => ratio
    }
  end

roundtrip_us = hd(results)["min_us"]

results =
  Enum.map(results, fn r ->
    ratio_ok =
      is_nil(r["bound_roundtrip_ratio"]) or
        r["min_us"] <= r["bound_roundtrip_ratio"] * roundtrip_us

    r
    |> Map.put("roundtrips", Float.round(r["min_us"] / max(roundtrip_us, 1), 2))
    |> Map.put("within_bound", r["min_us"] <= r["bound_min_us"] and ratio_ok)
  end)

{:ok, %{"freed" => true}} = Ferroplan.session_free(parent)

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
  "court" =>
    "per case: min_us <= bound_min_us and min_us <= bound_roundtrip_ratio * engine_roundtrip.min_us",
  "engine_roundtrip_min_us" => roundtrip_us,
  "results" => results,
  "pass" => Enum.all?(results, & &1["within_bound"])
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
    "REGRESSION: court failed in " <>
      Enum.map_join(Enum.reject(results, & &1["within_bound"]), ",", & &1["case"])
  )

  System.halt(1)
end
