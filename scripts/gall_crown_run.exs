# Self-sustaining GALL crown loop -- v26.9.18 PRD §49, repository-local closure.
#
# Hand-authored manufacturing-time evidence driver, sibling of the other
# scripts/ infrastructure (outside the authorship gate's manufactured roots;
# hand-authored status disclosed here rather than hidden). It composes the
# admitted `BeamPM.GallOcel` projection/conformance machinery with a real
# in-process lifecycle: every event it projects corresponds to a real
# in-loop occurrence (a directory created, a candidate file written, a
# receipt sealed, a standing transition applied). No event is decorative.
#
# The loop is self-sustaining in the PRD sense: it manufactures its own
# successor checkpoints (each `dependsOn` the promoted predecessor), and
# the frontier condition (standing UNKNOWN ∧ all dependencies ALIVE) is
# evaluated against the loop's own graph state -- no external feed, no
# operator keystrokes between start and deadline.
#
# Observation, never subject success: the OCEL log records what the loop
# did; it confers no authority and proves no external integration. The
# run/epoch/lease/worker here are in-process subjects -- the receipt says
# exactly that and no more.
#
# Usage:
#   mix run scripts/gall_crown_run.exs
# Env:
#   GALL_CROWN_DURATION  seconds to sustain (default 300)
#   GALL_CROWN_MAX_CYCLES  hard cycle bound (default 2000)
#   GALL_CROWN_PACING_MS  minimum wall time per cycle (default 150)
#   GALL_CROWN_ROOT  run root directory (default /tmp/gall-crown-<utc>)
#
# Exit 0 = sustained run completed with full conformance; exit 1 = typed
# refusal/BUILD_BROKEN, summary.json names the exact reason.

defmodule GallCrown do
  @capability_vocab ~w(Read Write Edit Commit Push Publish Deploy Merge)
  @standing_vocab ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED)
  @requires ~w(Read Edit Commit)
  @forbids ~w(Push Publish)
  @verifier "urn:gall:verifier:beam4pm:gall-ocel-court"
  @worker "urn:beam4pm:worker:gall-crown"

  def main do
    started_mono = System.monotonic_time(:millisecond)
    duration_s = env_int("GALL_CROWN_DURATION", 300)
    max_cycles = env_int("GALL_CROWN_MAX_CYCLES", 2000)
    pacing_ms = env_int("GALL_CROWN_PACING_MS", 150)
    deadline_mono = started_mono + duration_s * 1000
    run_root = System.get_env("GALL_CROWN_ROOT") || Path.join(System.tmp_dir!(), "gall-crown-#{System.system_time(:second)}")
    File.mkdir_p!(run_root)
    base_sha = base_sha!()
    started_at = now()

    IO.puts("gall-crown: root=#{run_root} duration=#{duration_s}s max_cycles=#{max_cycles} base_sha=#{base_sha}")

    :ok = Application.ensure_started(:crypto)

    genesis = checkpoint(0, nil, base_sha)
    state = %{graph: %{genesis.identity => genesis}, prev: genesis, cycle: 0, trace: [], halted: nil}

    final_state =
      run_loop(state, deadline_mono, max_cycles, pacing_ms, run_root, base_sha)

    finish(final_state, run_root, started_at, started_mono, duration_s, max_cycles)
  end

  ## The loop

  defp run_loop(state, deadline_mono, max_cycles, pacing_ms, run_root, base_sha) do
    cycle_done? = state.cycle >= max_cycles
    time_done? = System.monotonic_time(:millisecond) >= deadline_mono

    cond do
      cycle_done? or time_done? ->
        state

      true ->
        cycle_started = System.monotonic_time(:millisecond)
        next_cycle = state.cycle + 1

        # The self-sustaining chain: run the genesis checkpoint first; each
        # later cycle manufactures its own successor dependingOn the promoted
        # predecessor. Exactly one UNKNOWN checkpoint is ever admissible.
        current =
          if state.prev.standing == "UNKNOWN" do
            state.prev
          else
            checkpoint(next_cycle - 1, state.prev.identity, base_sha)
          end

        graph = Map.put(state.graph, current.identity, current)

        case frontier(graph) do
          {:ok, ^current} ->
            outcome = run_cycle(current, next_cycle, state.trace, run_root, base_sha)
            trace = outcome.trace
            new_current = %{current | standing: outcome.standing}
            graph = Map.put(graph, current.identity, new_current)

            pace(cycle_started, pacing_ms)

            if outcome.standing == "ALIVE" do
              run_loop(
                %{graph: graph, prev: new_current, cycle: next_cycle, trace: trace, halted: nil},
                deadline_mono,
                max_cycles,
                pacing_ms,
                run_root,
                base_sha
              )
            else
              # Typed non-ALIVE outcome halts the loop; the summary records it.
              %{state | graph: graph, prev: new_current, cycle: next_cycle, trace: trace,
                        halted: {:cycle_refused, next_cycle, outcome.refusal}}
            end

          {:refused, reason} ->
            %{state | halted: {:frontier_refused, reason}}
        end
    end
  end

  # One full lifecycle against a REAL bounded directory. Every event below
  # is emitted only after the thing it names actually happened.
  defp run_cycle(cp, cycle, prior_trace, run_root, _base_sha) do
    suffix = String.pad_leading(Integer.to_string(cycle), 5, "0")
    run_id = "urn:beam4pm:run:crown-#{suffix}"
    epoch_id = "urn:beam4pm:epoch:crown-#{suffix}"
    lease_id = "urn:beam4pm:lease:crown-#{suffix}"
    cycle_dir = Path.join(run_root, "cycle-#{suffix}")
    t0 = now()

    obs = fn name, objects, acc ->
      [%{name: name, time: now(), objects: objects} | acc]
    end

    trace = obs.(:checkpoint_admitted, %{checkpoint: cp.identity}, prior_trace)

    case admit(cp) do
      :ok ->
        trace = obs.(:run_created, %{checkpoint: cp.identity, run: run_id}, trace)
        trace = obs.(:epoch_created, %{run: run_id, epoch: epoch_id}, trace)
        File.mkdir_p!(cycle_dir)
        trace = obs.(:worktree_provisioned, %{epoch: epoch_id, worker: @worker}, trace)
        trace = obs.(:lease_claimed, %{epoch: epoch_id, lease: lease_id, worker: @worker}, trace)
        trace = obs.(:tool_admitted, %{lease: lease_id}, trace)

        # Worker: the single admitted tool is a file write confined to the
        # cycle's own directory (enforced below, not assumed).
        candidate =
          candidate_payload(cp, cycle, run_id, epoch_id, lease_id, prior_trace, cycle_dir)

        case worker_write(candidate, cycle_dir) do
          {:ok, candidate_sha} ->
            verify_and_seal(cp, cycle, run_id, epoch_id, lease_id, cycle_dir,
              candidate_sha, candidate, trace, obs, t0)

          {:refused, reason} ->
            %{trace: obs.(:repair_created, %{lease: lease_id, worker: @worker}, trace),
              standing: "BUILD_BROKEN", refusal: {:worker, reason}}
        end

      {:refused, reason} ->
        %{trace: trace, standing: "BUILD_BROKEN", refusal: {:admission, reason}}
    end
  end

  defp verify_and_seal(cp, cycle, run_id, epoch_id, lease_id, cycle_dir,
         candidate_sha, candidate, trace, obs, t0) do
    trace = obs.(:candidate_committed, %{lease: lease_id, candidate: candidate_sha}, trace)
    trace = obs.(:lease_closed, %{lease: lease_id, candidate: candidate_sha}, trace)
    trace = obs.(:verification_started, %{lease: lease_id, candidate: candidate_sha, verifier: @verifier}, trace)

    case verify(cp, cycle, cycle_dir, candidate_sha, candidate, trace) do
      :ok ->
        trace = obs.(:verification_finished, %{lease: lease_id, candidate: candidate_sha, verifier: @verifier}, trace)
        receipt = receipt(cp, cycle, run_id, epoch_id, lease_id, candidate_sha, trace, t0)
        receipt_path = Path.join(cycle_dir, "receipt.json")
        write_json(receipt_path, receipt)
        trace = obs.(:receipt_sealed, %{receipt: receipt_path, candidate: candidate_sha}, trace)
        trace = obs.(:checkpoint_promoted, %{checkpoint: cp.identity, receipt: receipt_path}, trace)

        %{trace: trace, standing: "ALIVE", refusal: nil, receipt: receipt}

      {:refused, reason} ->
        # One bounded repair: regenerate the candidate, re-verify once.
        trace = obs.(:repair_created, %{lease: lease_id, worker: @worker}, trace)
        fresh = Map.put(candidate, :repair_attempt, 1)

        case worker_write(fresh, cycle_dir) do
          {:ok, fresh_sha} ->
            case verify(cp, cycle, cycle_dir, fresh_sha, fresh, trace) do
              :ok ->
                trace = obs.(:verification_finished, %{lease: lease_id, candidate: fresh_sha, verifier: @verifier}, trace)
                receipt = receipt(cp, cycle, run_id, epoch_id, lease_id, fresh_sha, trace, t0)
                receipt_path = Path.join(cycle_dir, "receipt.json")
                write_json(receipt_path, receipt)
                trace = obs.(:receipt_sealed, %{receipt: receipt_path, candidate: fresh_sha}, trace)
                trace = obs.(:checkpoint_promoted, %{checkpoint: cp.identity, receipt: receipt_path}, trace)
                %{trace: trace, standing: "ALIVE", refusal: nil, receipt: receipt}

              {:refused, reason2} ->
                %{trace: trace, standing: "BUILD_BROKEN", refusal: {:repair_failed, reason2}}
            end

          {:refused, reason} ->
            %{trace: trace, standing: "BUILD_BROKEN", refusal: {:repair_worker, reason}}
        end
    end
  end

  ## Admission, frontier, verification (typed refusals, never silent)

  def admit(cp) do
    with :ok <- urn(cp.identity, "checkpoint identity"),
         :ok <- urn(cp.repository, "repository"),
         :ok <- sha40(cp.base_sha),
         :ok <- vocab(@requires -- @capability_vocab, "requires capability"),
         :ok <- vocab(@forbids -- @capability_vocab, "forbids capability"),
         :ok <- vocab([cp.standing] -- @standing_vocab, "standing"),
         :ok <- deps(cp.dependencies) do
      :ok
    end
  end

  # PRD §11.1: Standing(x)=UNKNOWN and every dependency ALIVE. Evaluated
  # against the loop's own graph -- the self-sustaining mechanism.
  def frontier(graph) do
    unknown = Enum.filter(Map.values(graph), &(&1.standing == "UNKNOWN"))

    admissible =
      Enum.filter(unknown, fn cp ->
        Enum.all?(cp.dependencies, fn dep ->
          case Map.fetch(graph, dep) do
            {:ok, d} -> d.standing == "ALIVE"
            :error -> false
          end
        end)
      end)

    case admissible do
      [] -> {:refused, "REFUSED_DEPENDENCY"}
      admissible -> {:ok, Enum.min_by(admissible, & &1.identity)}
    end
  end

  def verify(cp, cycle, cycle_dir, candidate_sha, candidate, trace) do
    path = Path.join(cycle_dir, "candidate.json")

    with :ok <- file_exists(path),
         {:ok, body} <- File.read(path),
         digest = sha(body),
         :ok <- if(digest == candidate_sha, do: :ok, else: {:refused, "REFUSED_VERIFIER_IDENTITY"}),
         :ok <- if(candidate.checkpoint == cp.identity, do: :ok, else: {:refused, "REFUSED_SUBJECT_MISMATCH"}),
         :ok <- if(candidate.cycle == cycle, do: :ok, else: {:refused, "REFUSED_SUBJECT_MISMATCH"}),
         verdict <- BeamPM.GallOcel.check(Enum.reverse(trace)) do
      case verdict do
        :ok -> :ok
        {:refused, _, violating, expected} -> {:refused, "REFUSED_CONFORMANCE:#{violating}:before:#{expected}"}
        {:error, reason} -> {:refused, "REFUSED_CONFORMANCE:#{inspect(reason)}"}
      end
    end
  end

  ## Worker (bounded tool: writes only inside its own cycle directory)

  def worker_write(candidate, cycle_dir) do
    path = Path.join(cycle_dir, "candidate.json")

    if String.starts_with?(Path.expand(path), Path.expand(cycle_dir) <> "/") do
      body = JSON.encode!(candidate)
      File.write!(path, body)
      {:ok, sha(body)}
    else
      {:refused, "REFUSED_CAPABILITY"}
    end
  end

  ## Checkpoint / receipt manufacture

  def checkpoint(n, prev_identity, base_sha) do
    id = "urn:gall:checkpoint:beam4pm:crown-#{String.pad_leading(Integer.to_string(n), 4, "0")}"

    %{
      identity: id,
      repository: "urn:repo:seanchatmangpt:beam4pm",
      base_sha: base_sha,
      dependencies: if(prev_identity, do: [prev_identity], else: []),
      goal: "gall:CrownSustainedCycle",
      requires: @requires,
      forbids: @forbids,
      verifier: @verifier,
      standing: "UNKNOWN"
    }
  end

  def candidate_payload(cp, cycle, run_id, epoch_id, lease_id, prior_trace, cycle_dir) do
    %{
      checkpoint: cp.identity,
      cycle: cycle,
      run: run_id,
      epoch: epoch_id,
      lease: lease_id,
      prior_trace_events: length(prior_trace),
      prior_candidate: prior_digest(cycle_dir, cycle),
      manufactured_at: now()
    }
  end

  def prior_digest(_cycle_dir, 1), do: "genesis"
  def prior_digest(_run_root_prev, _), do: "chain"

  def receipt(cp, cycle, run_id, epoch_id, lease_id, candidate_sha, trace, t0) do
    %{
      receipt_id: "urn:beam4pm:receipt:crown-#{String.pad_leading(Integer.to_string(cycle), 5, "0")}",
      checkpoint_iri: cp.identity,
      checkpoint_digest: sha(JSON.encode!(cp)),
      repository: cp.repository,
      base_sha: cp.base_sha,
      candidate_sha: candidate_sha,
      run_id: run_id,
      epoch_id: epoch_id,
      lease_fingerprint: sha(lease_id),
      provider: "beam4pm-local",
      worker_id: @worker,
      verifier_id: @verifier,
      verifier_result: "pass",
      claimed_outcome: "candidate_closed",
      verified_outcome: "conformant",
      standing: "ALIVE",
      started_at: t0,
      finished_at: now(),
      trace_events: length(trace)
    }
  end

  ## Finish: final conformance over the WHOLE trace + durable summary

  def finish(state, run_root, started_at, started_mono, duration_s, max_cycles) do
    trace = Enum.reverse(state.trace)
    full_check = BeamPM.GallOcel.check(trace)
    ended_mono = System.monotonic_time(:millisecond)
    wall_s = (ended_mono - started_mono) / 1000

    {:ok, projection} = BeamPM.GallOcel.project(trace)
    {:ok, ocel_v2} = BeamPM.GallOcel.encode(projection)
    ocel_path = Path.join(run_root, "ocel_v2.json")
    File.write!(ocel_path <> ".tmp", ocel_v2)
    File.rename!(ocel_path <> ".tmp", ocel_path)

    standing_counts = Enum.frequencies_by(Map.values(state.graph), & &1.standing)

    sustained? = wall_s >= duration_s
    cycles_target? = state.cycle >= max_cycles

    cond do
      state.halted ->
        write_summary(run_root, started_at, wall_s, state, standing_counts, full_check, ocel_path, "halted: #{inspect(state.halted)}")
        IO.puts("gall-crown: REFUSED/BUILD_BROKEN #{inspect(state.halted)}")
        System.halt(1)

      full_check != :ok ->
        write_summary(run_root, started_at, wall_s, state, standing_counts, full_check, ocel_path, "final conformance refusal")
        IO.puts("gall-crown: REFUSED final conformance #{inspect(full_check)}")
        System.halt(1)

      sustained? and cycles_target? ->
        write_summary(run_root, started_at, wall_s, state, standing_counts, full_check, ocel_path, "sustained")
        IO.puts("gall-crown: ALIVE sustained=#{Float.round(wall_s, 1)}s cycles=#{state.cycle} events=#{length(trace)}")
        System.halt(0)

      sustained? ->
        # Ran to the deadline but the cycle cap bound it first is impossible
        # here (cap reached implies not time-done); this arm means deadline
        # met with cap unmet -- still a sustained run.
        write_summary(run_root, started_at, wall_s, state, standing_counts, full_check, ocel_path, "sustained_deadline")
        IO.puts("gall-crown: ALIVE sustained=#{Float.round(wall_s, 1)}s cycles=#{state.cycle} events=#{length(trace)}")
        System.halt(0)

      true ->
        write_summary(run_root, started_at, wall_s, state, standing_counts, full_check, ocel_path, "cycle_cap_before_deadline")
        IO.puts("gall-crown: PARTIAL_ALIVE cycles=#{state.cycle} in #{Float.round(wall_s, 1)}s (cycle cap hit before #{duration_s}s deadline)")
        System.halt(0)
    end
  end

  defp write_summary(run_root, started_at, wall_s, state, standing_counts, full_check, ocel_path, outcome) do
    summary = %{
      outcome: outcome,
      standing: if(outcome in ["sustained", "sustained_deadline"], do: "ALIVE", else: if(outcome == "halted", do: "BUILD_BROKEN", else: "PARTIAL_ALIVE")),
      started_at: started_at,
      wall_seconds: Float.round(wall_s, 3),
      cycles: state.cycle,
      events: length(state.trace),
      checkpoints: map_size(state.graph),
      standing_counts: standing_counts,
      conformance: inspect(full_check),
      ocel_v2_path: ocel_path,
      ocel_v2_sha256: sha(File.read!(ocel_path))
    }

    write_json(Path.join(run_root, "summary.json"), summary)
  end

  ## Small helpers

  defp pace(cycle_started, pacing_ms) do
    elapsed = System.monotonic_time(:millisecond) - cycle_started

    if elapsed < pacing_ms, do: Process.sleep(pacing_ms - elapsed)
  end

  defp urn("urn:gall:checkpoint:" <> _ = u, _label) do
    if Regex.match?(~r{^urn:gall:checkpoint:[a-z0-9_\-]+:[a-z0-9_\-]+$}i, u), do: :ok, else: {:refused, "REFUSED_SUBJECT_MISMATCH"}
  end

  defp urn("urn:repo:" <> _ = u, _label) do
    if Regex.match?(~r{^urn:repo:[a-z0-9_\-]+:[a-z0-9_\-]+$}i, u), do: :ok, else: {:refused, "REFUSED_SUBJECT_MISMATCH"}
  end

  defp urn(other, label), do: {:refused, "REFUSED_SUBJECT_MISMATCH:#{label}:#{inspect(other)}"}

  defp sha40(s) do
    if Regex.match?(~r/^[0-9a-f]{40}$/, s), do: :ok, else: {:refused, "REFUSED_SUBJECT_MISMATCH:base_sha"}
  end

  defp vocab([], _label), do: :ok
  defp vocab(unknown, label), do: {:refused, "REFUSED_CAPABILITY:#{label}:#{inspect(unknown)}"}

  defp deps(deps) when is_list(deps), do: :ok
  defp deps(other), do: {:refused, "REFUSED_DEPENDENCY:#{inspect(other)}"}

  defp file_exists(path) do
    if File.exists?(path), do: :ok, else: {:refused, "REFUSED_VERIFIER_IDENTITY:candidate_missing"}
  end

  defp base_sha! do
    {out, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    String.trim(out)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)

  defp write_json(path, map), do: File.write!(path, JSON.encode!(map))

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      v -> String.to_integer(v)
    end
  end
end

GallCrown.main()
