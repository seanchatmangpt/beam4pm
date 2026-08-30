# Hand-authored, NOT manufactured (no `bpma:AdmittedActuation` individual
# needs its own test case rendered per-action -- see
# test/beam4pm_actuation_test.exs's generic allowlist coverage for that).
# This file proves the k8s_scale_up/k8s_scale_down admitted actuations
# genuinely drive BeamPM.Actuation.run/2 -> a real subprocess -> real
# kubectl -> a real live Kubernetes Deployment, not just that
# qualification/k8s_gym_bridge.py works standalone (already qualified
# directly, twice, against the real kind-ex4pm cluster).
#
# Gated fail-closed, not faked: a compile-time check shells out to a real
# `kubectl --context kind-ex4pm cluster-info` and sets `@moduletag skip:
# reason` when the cluster is unreachable (CI/Docker have no kind-ex4pm
# checkout at all) -- the same fail-closed-rather-than-fabricated pattern
# tests/test_container_smoke.sh already uses in the ggen-ecosystem repo
# for an unavailable Docker daemon. A skipped-via-tag module reports
# cleanly as "N tests, 0 failures, N skipped" with exit code 0 -- the
# actual documented ExUnit mechanism for a runtime-conditional skip.
#
# REAL BUGS FOUND AND FIXED (2026-08-30, caught by two separate real
# `docker build` runs, never assumed): TWO earlier versions of this file
# got the ExUnit skip API wrong, both confirmed the hard way by re-running
# the same real `docker build` that caught each one:
#   1. `setup_all` returning `{:skip, reason}` -- ExUnit only allows
#      `setup_all` to return `:ok`, a keyword list, or a map; this raised
#      a real RuntimeError, marking tests "invalid" (0 failures counted,
#      so the summary line looked clean) while making the OVERALL `mix
#      test` process exit non-zero -- silently breaking the CI/Docker
#      build for anyone without a reachable cluster.
#   2. `setup` (per-test) returning `{:skip, reason}` -- same RuntimeError,
#      same failure mode; neither `setup` nor `setup_all` accepts this
#      shape in this ExUnit version (1.19.5).
# `@moduletag skip: reason_or_false`, computed once at compile time via a
# module attribute, is the actual correct, documented mechanism. Verified
# for real both ways: with the cluster reachable, `mix test` on this file
# still reports "3 tests, 0 failures" (exit 0); with a deliberately broken
# KUBECONFIG, it reports "3 tests, 0 failures, 3 skipped" (exit 0) --
# genuinely clean now, confirmed by checking $? directly, not assumed from
# the summary line alone.
defmodule BeamPM.ActuationK8sTest do
  @moduledoc """
  Chicago-style qualification of the k8s_scale_up/k8s_scale_down admitted
  actuations (`bpma:k8s_scale_up_aa`/`bpma:k8s_scale_down_aa`) through the
  real `BeamPM.Actuation.run/2` BRCE pipeline: real Reactor run, a real
  `qualification/k8s_gym_bridge.py` subprocess, real `kubectl` calls against
  the real, live `kind-ex4pm` cluster's isolated `beam4pm-actuation-demo`
  namespace, real `beam4pm-brce/v1` receipt files on disk. Completes the
  "no toys, fortune 5 production only" mandate through the Reactor
  admission boundary, not just at the bridge-script level.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Actuation

  @context "kind-ex4pm"

  # Compile-time reachability check -- runs once, when this test module is
  # compiled, not once per test. System.cmd/3 RAISES
  # ErlangError{original: :enoent} rather than returning a tuple when the
  # executable itself doesn't exist on PATH (confirmed for real -- a
  # genuinely likely case here: CI/Docker never install kubectl at all) --
  # caught explicitly so an environment with no kubectl binary skips
  # exactly as cleanly as one with kubectl but no reachable cluster.
  @cluster_skip_reason (try do
                          case System.cmd("kubectl", ["--context", @context, "cluster-info"],
                                 stderr_to_stdout: true
                               ) do
                            {_out, 0} -> false
                            {out, _status} -> "kind-ex4pm cluster unreachable: #{String.slice(out, 0, 200)}"
                          end
                        rescue
                          e in ErlangError -> "kubectl not available: #{inspect(e)}"
                        end)

  @moduletag :tmp_dir
  @moduletag :external_k8s
  @moduletag skip: @cluster_skip_reason

  defp bridge_path do
    path = Path.expand("qualification/k8s_gym_bridge.py")
    unless File.exists?(path), do: raise("k8s_gym_bridge.py not found at #{path}")
    path
  end

  defp run_opts(tmp_dir, run_id) do
    # Real k8s rollouts (namespace create/apply/rollout-wait, and now a
    # real blocking namespace delete on close) can legitimately exceed
    # actuation_opts[:bridge_timeout]'s 10_000ms default -- caught for real
    # against the live kind-ex4pm cluster (a "kubectl_failed: error: object
    # has been deleted" from Elixir force-closing the Port mid-rollout).
    # 90s comfortably covers k8s_gym_bridge.py's own ROLLOUT_TIMEOUT (60s).
    [
      gym: "k8s-deployment-scaler",
      bridge: bridge_path(),
      receipts_dir: tmp_dir,
      run_id: run_id,
      bridge_timeout: 90_000
    ]
  end

  defp read_receipt!(tmp_dir, run_id) do
    path = Path.join(tmp_dir, run_id <> ".json")
    assert File.exists?(path), "expected consequence receipt at #{path}"
    path |> File.read!() |> JSON.decode!()
  end

  test "k8s_scale_up is admitted, actuated for real, and observed real cluster state in the receipt",
       %{tmp_dir: tmp_dir} do
    run_id = "act-k8s-up-#{System.unique_integer([:positive])}"
    action = %{action_name: "k8s_scale_up", preconditions: [], effects: []}

    assert {:ok, out} = Actuation.run(action, run_opts(tmp_dir, run_id))
    assert out.performed == true

    receipt = read_receipt!(tmp_dir, run_id)
    assert receipt["receipt_schema"] == "beam4pm-brce/v1"
    assert receipt["action"]["action_name"] == "k8s_scale_up"
    assert receipt["admission"]["admitted"] == true

    # Real observed state from the real cluster, not fabricated:
    # observation_after is the gym bridge's own real kubectl-derived
    # observation, embedded verbatim.
    obs = receipt["execution"]["observation_after"]
    assert obs["namespace"] == "beam4pm-actuation-demo"
    assert obs["ready_replicas"] == 3
  end

  test "k8s_scale_down is admitted, actuated for real, and reaches the real target replica count",
       %{tmp_dir: tmp_dir} do
    # NOTE: BeamPM.Actuation.run/2 does its own reset+close per call (the
    # bridge's `reset` (re)creates the demo namespace/deployment at 1
    # replica; `close` tears the namespace down again) -- this test proves
    # k8s_scale_down's own admission+execution+receipt path is real and
    # sound, not a continuous 3->1 transition on one running deployment
    # (that would be BeamPM.ProcessGovernor's job, a separate feature).
    run_id = "act-k8s-down-#{System.unique_integer([:positive])}"
    action = %{action_name: "k8s_scale_down", preconditions: [], effects: []}

    assert {:ok, out} = Actuation.run(action, run_opts(tmp_dir, run_id))
    assert out.performed == true

    receipt = read_receipt!(tmp_dir, run_id)
    assert receipt["action"]["action_name"] == "k8s_scale_down"
    assert receipt["admission"]["admitted"] == true

    obs = receipt["execution"]["observation_after"]
    assert obs["namespace"] == "beam4pm-actuation-demo"
    assert obs["ready_replicas"] == 1
  end

  test "an unadmitted action name against the k8s gym is refused fail-closed, never silently actuated",
       %{tmp_dir: tmp_dir} do
    run_id = "act-k8s-refused-#{System.unique_integer([:positive])}"
    action = %{action_name: "k8s_delete_namespace", preconditions: [], effects: []}

    assert {:error, {:refused, reason}} = Actuation.run(action, run_opts(tmp_dir, run_id))
    assert reason =~ "is not an admitted actuation"
    # A refused (never-admitted) action still gets a real typed failure
    # receipt written -- fail-closed, never silent -- per run/2's own
    # documented contract ("in ALL three cases exactly one consequence
    # receipt exists on disk").
    receipt = read_receipt!(tmp_dir, run_id)
    assert receipt["admission"]["admitted"] == false
  end
end
