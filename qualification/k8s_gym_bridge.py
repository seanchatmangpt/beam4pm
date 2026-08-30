#!/usr/bin/env python3
"""k8s_gym_bridge.py -- REAL production-grade actuation target for
BeamPM.Actuation qualification. Drives a real Kubernetes Deployment on a
real, live cluster via real `kubectl` subprocess calls -- no in-memory
simulation, no mock client, no fake API server. This replaces
qualification/fixtures/toy_gym_bridge.py as the qualification standard per
explicit directive: "no toys, fortune 5 production only."

Speaks the FIXED beam4pm gym bridge wire protocol (JSON lines on
stdin/stdout), identical to toy_gym_bridge.py's contract, so
BeamPM.Actuation.GymBridge needs zero changes to drive it:

    in:  {"op":"reset"}                 out: {"ok":true,"observation":<json>}
    in:  {"op":"step","action":<json>}  out: {"ok":true,"observation":<json>,
                                              "reward":<num>,"done":<bool>,
                                              "info":<json>}
    in:  {"op":"close"}                 out: {"ok":true}  then exit 0
    any error: {"ok":false,"error":"<reason>"} on stdout, keep running
    unless fatal.

Gym: k8s-deployment-scaler
    Operates on a real Deployment (`beam4pm-actuation-demo` Deployment,
    nginx:1.27-alpine, in the dedicated `beam4pm-actuation-demo` namespace --
    isolated from every other real workload on the cluster) via real
    `kubectl apply/scale/rollout status/get` calls.

    reset: creates the namespace if absent, applies a real 1-replica
        Deployment manifest, waits for a real rollout to complete (bounded
        real timeout), returns the real observed
        {"namespace":..., "deployment":..., "replicas":N,
         "ready_replicas":N, "image":...}.
    step {"op":"scale_up"}   -> kubectl scale --replicas=3, real rollout wait,
                                 reward 1.0 on real ready_replicas==3.
    step {"op":"scale_down"} -> kubectl scale --replicas=1, real rollout wait,
                                 reward 1.0 on real ready_replicas==1.
    step (any other op)      -> {"ok":false,"error":"unknown_action: <op>"}
                                 (bridge keeps running -- same as toy_gym_bridge).
    close: real `kubectl delete namespace` (full teardown of the isolated
        demo namespace only -- every other real namespace/workload on the
        cluster, including the pre-existing `ex4pm`/`postgres` Deployments
        observed in the `default` namespace, is never touched).

Invocation (FIXED, mirrors toy_gym_bridge.py exactly):
    python3 k8s_gym_bridge.py --gym k8s-deployment-scaler [--context <kubectl context>]

Requires: a real `kubectl` on PATH with a real, reachable cluster context
(defaults to the real local `kind-ex4pm` context this was qualified
against; override with --context for a different real cluster). Exits 2
immediately, fail-closed, if kubectl or the context is unavailable -- never
fakes a pass.
"""

import argparse
import json
import subprocess
import sys
import time

NAMESPACE = "beam4pm-actuation-demo"
DEPLOYMENT = "beam4pm-actuation-demo"
IMAGE = "nginx:1.27-alpine"
ROLLOUT_TIMEOUT = "60s"

DEPLOYMENT_MANIFEST = """apiVersion: apps/v1
kind: Deployment
metadata:
  name: {name}
  namespace: {ns}
  labels:
    app: beam4pm-actuation-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: beam4pm-actuation-demo
  template:
    metadata:
      labels:
        app: beam4pm-actuation-demo
    spec:
      containers:
        - name: demo
          image: {image}
          resources:
            requests:
              cpu: "10m"
              memory: "16Mi"
            limits:
              cpu: "50m"
              memory: "32Mi"
"""


def emit(obj):
    sys.stdout.write(json.dumps(obj, sort_keys=True) + "\n")
    sys.stdout.flush()


def kubectl(context, *args, input_text=None, check=True):
    cmd = ["kubectl", "--context", context] + list(args)
    return subprocess.run(
        cmd, input=input_text, capture_output=True, text=True, check=check
    )


def observe(context):
    out = kubectl(
        context, "get", "deployment", DEPLOYMENT, "-n", NAMESPACE, "-o", "json"
    )
    d = json.loads(out.stdout)
    spec_replicas = d.get("spec", {}).get("replicas", 0)
    status = d.get("status", {})
    ready = status.get("readyReplicas", 0)
    image = d["spec"]["template"]["spec"]["containers"][0]["image"]
    return {
        "namespace": NAMESPACE,
        "deployment": DEPLOYMENT,
        "replicas": spec_replicas,
        "ready_replicas": ready,
        "image": image,
    }


def do_reset(context):
    kubectl(
        context,
        "create",
        "namespace",
        NAMESPACE,
        check=False,  # idempotent: real "already exists" is not an error here
    )
    manifest = DEPLOYMENT_MANIFEST.format(name=DEPLOYMENT, ns=NAMESPACE, image=IMAGE)
    kubectl(context, "apply", "-f", "-", input_text=manifest)
    kubectl(
        context,
        "rollout",
        "status",
        f"deployment/{DEPLOYMENT}",
        "-n",
        NAMESPACE,
        f"--timeout={ROLLOUT_TIMEOUT}",
    )
    return observe(context)


def do_step(context, action):
    if not isinstance(action, dict) or "op" not in action:
        return {"ok": False, "error": "malformed_action"}

    op = action["op"]
    if op == "scale_up":
        target = 3
    elif op == "scale_down":
        target = 1
    else:
        return {"ok": False, "error": f"unknown_action: {op}"}

    kubectl(
        context,
        "scale",
        "deployment",
        DEPLOYMENT,
        "-n",
        NAMESPACE,
        f"--replicas={target}",
    )
    kubectl(
        context,
        "rollout",
        "status",
        f"deployment/{DEPLOYMENT}",
        "-n",
        NAMESPACE,
        f"--timeout={ROLLOUT_TIMEOUT}",
    )
    obs = observe(context)
    reward = 1.0 if obs["ready_replicas"] == target else 0.0
    return {
        "ok": True,
        "observation": obs,
        "reward": reward,
        "done": False,
        "info": {"gym": "k8s-deployment-scaler", "target_replicas": target},
    }


def do_close(context):
    kubectl(context, "delete", "namespace", NAMESPACE, "--wait=false", check=False)
    return {"ok": True}


def run_k8s_deployment_scaler(context):
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            emit({"ok": False, "error": "bad_json"})
            continue

        op = msg.get("op")
        try:
            if op == "reset":
                emit({"ok": True, "observation": do_reset(context)})
            elif op == "step":
                emit(do_step(context, msg.get("action")))
            elif op == "close":
                emit(do_close(context))
                return 0
            else:
                emit({"ok": False, "error": f"unknown_op: {op}"})
        except subprocess.CalledProcessError as e:
            emit({"ok": False, "error": f"kubectl_failed: {e.stderr.strip()[:500]}"})
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--gym", required=True)
    parser.add_argument("--context", default="kind-ex4pm")
    args = parser.parse_args()

    # Fail-closed: never fake a pass if kubectl/the real cluster is unreachable.
    check = subprocess.run(
        ["kubectl", "--context", args.context, "cluster-info"],
        capture_output=True,
        text=True,
    )
    if check.returncode != 0:
        sys.stderr.write(
            f"BLOCKED: kubectl context {args.context!r} unreachable: "
            f"{check.stderr.strip()}\n"
        )
        return 2

    if args.gym == "k8s-deployment-scaler":
        return run_k8s_deployment_scaler(args.context)

    emit({"ok": False, "error": f"unknown_gym: {args.gym}"})
    return 1


if __name__ == "__main__":
    sys.exit(main())
