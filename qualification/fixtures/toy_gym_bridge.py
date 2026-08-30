#!/usr/bin/env python3
"""toy_gym_bridge.py -- REAL fixture gym bridge for BeamPM.Actuation qualification.

This is a real collaborator (a deterministic fake ENVIRONMENT, not a mock of
our own code): a tiny state machine spoken to over the FIXED beam4pm gym
bridge wire protocol (JSON lines on stdin/stdout):

    in:  {"op":"reset"}                 out: {"ok":true,"observation":<json>}
    in:  {"op":"step","action":<json>}  out: {"ok":true,"observation":<json>,
                                              "reward":<num>,"done":<bool>,
                                              "info":<json>}
    in:  {"op":"close"}                 out: {"ok":true}  then exit 0
    any error: {"ok":false,"error":"<reason>"} on stdout, keep running
    unless fatal.

Gyms:

    toy-counter  deterministic counter machine. reset -> counter=0, steps=0.
                 step {"op":"inc"}  -> counter+1, reward 1.0, done when
                                       counter >= 3
                 step {"op":"noop"} -> counter unchanged, reward 0.0
                 any other action   -> {"ok":false,"error":"unknown_action"}
                 (bridge keeps running)

    crashy       reset works ({"counter":0}); the FIRST step request makes
                 the process exit(3) abruptly with NO reply -- a real
                 mid-actuation environment crash for the compensation path.

Invocation (FIXED): python3 toy_gym_bridge.py --gym <name>
"""

import argparse
import json
import sys


def emit(obj):
    sys.stdout.write(json.dumps(obj, sort_keys=True) + "\n")
    sys.stdout.flush()


def run_toy_counter():
    state = None
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
        if op == "reset":
            state = {"counter": 0, "steps": 0}
            emit({"ok": True, "observation": dict(state)})
        elif op == "step":
            if state is None:
                emit({"ok": False, "error": "not_reset"})
                continue
            action = msg.get("action")
            if not isinstance(action, dict) or "op" not in action:
                emit({"ok": False, "error": "malformed_action"})
                continue
            if action["op"] == "inc":
                state["counter"] += 1
                state["steps"] += 1
                reward = 1.0
            elif action["op"] == "noop":
                state["steps"] += 1
                reward = 0.0
            else:
                emit({"ok": False, "error": "unknown_action: %s" % action["op"]})
                continue
            emit(
                {
                    "ok": True,
                    "observation": dict(state),
                    "reward": reward,
                    "done": state["counter"] >= 3,
                    "info": {"gym": "toy-counter"},
                }
            )
        elif op == "close":
            emit({"ok": True})
            return 0
        else:
            emit({"ok": False, "error": "unknown_op: %s" % op})
    return 0


def run_crashy():
    state = None
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
        if op == "reset":
            state = {"counter": 0}
            emit({"ok": True, "observation": dict(state)})
        elif op == "step":
            # A real abrupt environment crash: no reply, non-zero exit.
            sys.exit(3)
        elif op == "close":
            emit({"ok": True})
            return 0
        else:
            emit({"ok": False, "error": "unknown_op: %s" % op})
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--gym", required=True)
    args = parser.parse_args()
    if args.gym == "toy-counter":
        return run_toy_counter()
    if args.gym == "crashy":
        return run_crashy()
    emit({"ok": False, "error": "unknown_gym: %s" % args.gym})
    return 1


if __name__ == "__main__":
    sys.exit(main())
