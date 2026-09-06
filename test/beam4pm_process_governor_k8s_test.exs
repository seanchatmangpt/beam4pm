# Hand-authored, NOT manufactured (same convention as
# test/beam4pm_actuation_k8s_test.exs: no bpmg:ProcessContract individual
# needs its own generated test case rendered here -- see
# test/beam4pm_process_governor_test.exs's generic graph-driven coverage for
# that). This file proves the NEW BeamPM.ProcessGovernor.run/2
# `continuous: true` mode genuinely drives a real, CONTINUOUS
# k8s_scale_up -> k8s_scale_down sequence against ONE continuously-running
# Deployment -- exactly one reset at the start, exactly one close at the
# end, never one reset+close per transition -- closing the real defect
# test/beam4pm_actuation_k8s_test.exs's own header comment (lines 130-135 in
# the pre-existing file) already named as "a separate feature" for
# ProcessGovernor to close.
#
# Gated fail-closed, not faked: identical compile-time
# `@moduletag skip: @cluster_skip_reason` mechanism as
# test/beam4pm_actuation_k8s_test.exs -- a module attribute computed once at
# compile time via a real `kubectl --context kind-ex4pm cluster-info` check,
# NEVER `{:skip, reason}` from setup/setup_all (that raises RuntimeError in
# this ExUnit version, 1.19.5 -- see the sibling file's own header for the
# two real bugs that pattern caused and how they were caught).
defmodule BeamPM.ProcessGovernorK8sTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.ProcessGovernor.run/2`'s
  `continuous: true` mode (and the lower-level `BeamPM.Actuation.Session` +
  `apply_transition/3` building blocks it is built from) against the real,
  live `kind-ex4pm` cluster's isolated `beam4pm-actuation-demo` namespace.

  Continuity is proven TWO independent ways, per the chosen design's
  explicit requirement that verification not rest solely on the bridge's
  own self-report:

    1. The real per-transition `beam4pm-brce/v1` actuation receipts' own
       `observation_before`/`observation_after` `uid`/`creation_timestamp`
       fields (added to `qualification/k8s_gym_bridge.py`'s `observe/1`
       specifically to make receipts self-proving) stay IDENTICAL across
       both transitions.
    2. This test's OWN independent `kubectl get deployment -o json` calls,
       issued from ExUnit itself (not through the gym bridge subprocess at
       all), taken BETWEEN the two transitions and again just before the
       session closes - re-deriving the same uid from a source the code
       under test never touches.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Actuation.Session
  alias BeamPM.ProcessGovernor

  @context "kind-ex4pm"
  @namespace "beam4pm-actuation-demo"
  @deployment "beam4pm-actuation-demo"
  @process_id "k8s_scaling_governed"

  # Identical compile-time reachability check to
  # test/beam4pm_actuation_k8s_test.exs (see that file for the full
  # rationale, including the two real ExUnit-skip bugs this exact pattern
  # was hardened against).
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

  defp read_receipt!(path) do
    assert File.exists?(path), "expected actuation receipt at #{path}"
    path |> File.read!() |> JSON.decode!()
  end

  # Independent of BeamPM.Actuation.GymBridge entirely: a real, separate
  # `kubectl` subprocess issued directly from this test.
  defp kubectl_get_deployment! do
    {out, 0} =
      System.cmd("kubectl", [
        "--context",
        @context,
        "get",
        "deployment",
        @deployment,
        "-n",
        @namespace,
        "-o",
        "json"
      ])

    JSON.decode!(out)
  end

  defp namespace_exists? do
    case System.cmd("kubectl", ["--context", @context, "get", "namespace", @namespace],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> true
      {_out, _status} -> false
    end
  end

  test "ProcessGovernor.run/2 continuous: true drives k8s_scaling_governed as one continuous 1->3->1 session, receipts prove uid continuity",
       %{tmp_dir: tmp_dir} do
    opts = [
      gym: "k8s-deployment-scaler",
      bridge: bridge_path(),
      continuous: true,
      bridge_timeout: 90_000,
      receipts_dir: tmp_dir
    ]

    assert {:ok, final} = ProcessGovernor.run(@process_id, opts)
    assert final.state == "scaled_down"
    assert length(final.receipts) == 2

    [receipt2, receipt1] = final.receipts
    assert receipt1.ordinal == 1 and receipt1.outcome == :applied
    assert receipt2.ordinal == 2 and receipt2.outcome == :applied

    actuation1 = read_receipt!(receipt1.actuation.receipt_path)
    actuation2 = read_receipt!(receipt2.actuation.receipt_path)

    # Real replica-count transition genuinely happened, in the right order.
    assert actuation1["execution"]["observation_after"]["ready_replicas"] == 3
    assert actuation2["execution"]["observation_after"]["ready_replicas"] == 1

    # Continuity proof (receipt-embedded): every one of the four real
    # observations spanning both transitions (reset's own observation
    # (carried forward as transition 1's observation_before), transition
    # 1's own observation_after, transition 2's observation_before, and
    # transition 2's observation_after) carries the SAME metadata.uid - a
    # fresh reset would assign a fresh uid, so an identical uid across all
    # four is direct evidence no delete+recreate happened between the
    # initial reset and either step.
    reset_uid = actuation1["execution"]["observation_before"]["uid"]
    assert is_binary(reset_uid) and reset_uid != ""
    assert actuation1["execution"]["observation_after"]["uid"] == reset_uid
    assert actuation2["execution"]["observation_before"]["uid"] == reset_uid
    assert actuation2["execution"]["observation_after"]["uid"] == reset_uid

    reset_ts = actuation1["execution"]["observation_before"]["creation_timestamp"]
    assert actuation1["execution"]["observation_after"]["creation_timestamp"] == reset_ts
    assert actuation2["execution"]["observation_before"]["creation_timestamp"] == reset_ts
    assert actuation2["execution"]["observation_after"]["creation_timestamp"] == reset_ts

    # The continuous session's own close (BeamPM.Actuation.Session.close/2
    # -> GymBridge.close/2 -> a real "close" op -> qualification/
    # k8s_gym_bridge.py's do_close -> a real blocking
    # `kubectl delete namespace`) already ran by the time run/2 returned -
    # confirm independently, via this test's own separate kubectl call,
    # that the demo namespace is really gone (not left dangling by a
    # leaked bridge port).
    refute namespace_exists?(),
           "expected the continuous session's own close to have torn down the demo namespace"
  end

  test "independently re-derived continuity: this test's OWN kubectl calls between and after transitions confirm the same uid, never trusting the bridge's self-report alone",
       %{tmp_dir: tmp_dir} do
    base_opts = [
      gym: "k8s-deployment-scaler",
      bridge: bridge_path(),
      bridge_timeout: 90_000,
      receipts_dir: tmp_dir
    ]

    # Drives the EXACT SAME real building blocks
    # BeamPM.ProcessGovernor.run/2's continuous mode uses internally
    # (BeamPM.Actuation.Session.open/3, BeamPM.ProcessGovernor.
    # initial_snapshot/2, plan_transition/2, apply_transition/3,
    # BeamPM.Actuation.Session.close/2) by hand, so this test can issue its
    # own independent `kubectl` calls BETWEEN the two transitions - a
    # verification window run/2's own single opaque call cannot offer.
    assert {:ok, session} = Session.open(bridge_path(), "k8s-deployment-scaler", 90_000)

    try do
      assert {:ok, snapshot0} = ProcessGovernor.initial_snapshot(@process_id)

      assert {:ok, candidate1} = ProcessGovernor.plan_transition(snapshot0, 1)

      assert {:ok, snapshot1, receipt1} =
               ProcessGovernor.apply_transition(
                 snapshot0,
                 candidate1,
                 Keyword.put(base_opts, :session, session)
               )

      assert receipt1.outcome == :applied

      # Independent kubectl check BETWEEN the two transitions: the real
      # cluster, queried directly, already shows 3 ready replicas, and its
      # uid is captured here as the ground-truth reference for every
      # comparison below.
      mid_run = kubectl_get_deployment!()
      assert mid_run["status"]["readyReplicas"] == 3
      mid_uid = mid_run["metadata"]["uid"]
      assert is_binary(mid_uid) and mid_uid != ""

      assert {:ok, candidate2} = ProcessGovernor.plan_transition(snapshot1, 2)

      assert {:ok, _snapshot2, receipt2} =
               ProcessGovernor.apply_transition(
                 snapshot1,
                 candidate2,
                 Keyword.put(base_opts, :session, session)
               )

      assert receipt2.outcome == :applied

      # Independent kubectl check AFTER the second transition, still
      # BEFORE this test closes the session (so the Deployment still
      # exists to query) - the real cluster's uid is still identical to
      # the one captured mid-run, proving continuity across BOTH
      # transitions via a source entirely outside the code under test.
      post_run = kubectl_get_deployment!()
      assert post_run["status"]["readyReplicas"] == 1
      assert post_run["metadata"]["uid"] == mid_uid
      assert post_run["metadata"]["creationTimestamp"] == mid_run["metadata"]["creationTimestamp"]
    after
      assert :ok = Session.close(session, 90_000)
    end

    refute namespace_exists?(),
           "expected this test's own Session.close/2 to have torn down the demo namespace"
  end

  test "ProcessGovernor.replay/2 end-to-end on a real k8s_scaling_governed receipt chain, plus a real on-disk corruption falsifier",
       %{tmp_dir: tmp_dir} do
    # ONE real continuous k8s_scaling_governed session (identical pattern to
    # the first test above) backs BOTH assertions below: replay/2's
    # successful re-verification-and-re-mining path, and its
    # first-corrupted-receipt-wins failure path. Deliberately not split into
    # two independent `test` blocks - each would need its own full real
    # continuous run against the shared, fixed-name `beam4pm-actuation-demo`
    # namespace, doubling both wall-clock cost and the sequential-live-run
    # namespace-collision window a prior review already flagged (inherited,
    # not introduced, by the existing two tests above) for no benefit: the
    # falsifier only ever mutates bytes already on disk in `tmp_dir` and
    # never touches the cluster again once `run/2` has returned.
    opts = [
      gym: "k8s-deployment-scaler",
      bridge: bridge_path(),
      continuous: true,
      bridge_timeout: 90_000,
      receipts_dir: tmp_dir
    ]

    assert {:ok, final} = ProcessGovernor.run(@process_id, opts)
    assert final.state == "scaled_down"
    assert length(final.receipts) == 2

    [receipt2, receipt1] = final.receipts
    assert receipt1.ordinal == 1 and receipt1.outcome == :applied
    assert receipt1.actuation_name == "k8s_scale_up"
    assert receipt2.ordinal == 2 and receipt2.outcome == :applied
    assert receipt2.actuation_name == "k8s_scale_down"

    # -- Part 1: real end-to-end replay of the real k8s receipt chain --------
    # replay/2 re-opens both embedded beam4pm-brce/v1 actuation receipts from
    # disk, re-verifies each against `receipt.actuation_name`, and re-mines
    # the whole two-transition run as one real OCEL trace via
    # BeamPM.Discovery - proving replay works on a genuine k8s actuation
    # chain, not only the toy_counter_governed gym
    # test/beam4pm_process_governor_test.exs already covers.
    assert {:ok, replayed} = ProcessGovernor.replay(@process_id, Enum.reverse(final.receipts))
    assert replayed.final_state == final.state
    assert replayed.final_state == "scaled_down"

    assert %BeamPM.Types.LogTrace{
             case_id: @process_id,
             activity_sequence: [
               "plan",
               "admit",
               "execute",
               "observe",
               "plan",
               "admit",
               "execute",
               "observe"
             ]
           } = replayed.mined_trace

    dfg_tuples =
      Enum.map(replayed.dfg, fn e -> {e.source_activity, e.target_activity, e.frequency} end)

    assert {"observe", "plan", 1} in dfg_tuples
    assert {"admit", "execute", 2} in dfg_tuples
    assert {"plan", "admit", 2} in dfg_tuples
    assert {"execute", "observe", 2} in dfg_tuples

    # -- Part 2: real falsifier - corrupt receipt1's real actuation file on --
    # -- disk, prove replay/2 catches it at exactly ordinal 1 ----------------
    # Same decode -> mutate a real field -> re-encode -> write technique as
    # test/beam4pm_receipt_chain_test.exs's own "REAL FALSIFIER" test (never
    # a literal raw byte-flip, which risks landing on invalid JSON rather
    # than the specific `action.action_name` mismatch branch
    # `verify_and_mine_one/1` checks) - a real, on-disk, decodable-but-wrong
    # actuation receipt, not a fabricated in-memory one.
    actuation1_path = receipt1.actuation.receipt_path
    original = actuation1_path |> File.read!() |> JSON.decode!()
    original_action_name = original["action"]["action_name"]
    assert original_action_name == "k8s_scale_up"

    tampered =
      Map.update!(original, "action", fn a ->
        Map.put(a, "action_name", "TAMPERED_" <> a["action_name"])
      end)

    File.write!(actuation1_path, JSON.encode!(tampered))

    reread = actuation1_path |> File.read!() |> JSON.decode!()
    assert reread["action"]["action_name"] != original_action_name,
           "the corruption must actually change the real file's action_name"

    # receipt2's own actuation file is untouched - replay/2 must still fail
    # closed at receipt1 (the first receipt in the oldest-first replay
    # order), never skip past the broken one to a later "successful" state.
    assert {:error, {:replay_broken, 1, {:receipt_verification_failed, ^actuation1_path}}} =
             ProcessGovernor.replay(@process_id, Enum.reverse(final.receipts))
  end
end
