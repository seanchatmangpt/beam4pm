#!/usr/bin/env python3
"""JSON-lines gym bridge: beam4pm's fixed wire protocol over REAL gymact gyms.

Invocation (fixed protocol, spoken on stdin/stdout, one JSON object per line):

    python3 gym_bridge.py --gym <name> [--config '<json>']

    in:  {"op":"reset"}                 out: {"ok":true,"observation":<json>}
    in:  {"op":"step","action":<json>}  out: {"ok":true,"observation":<json>,
                                              "reward":<num>,"done":<bool>,
                                              "info":<json>}
    in:  {"op":"close"}                 out: {"ok":true}   then exit 0
    any error: {"ok":false,"error":"<reason>"} on stdout; the bridge keeps
    running unless the failure is fatal (stdin EOF, unknown gym at startup).

    python3 gym_bridge.py --list        probes every registered gym FOR REAL
                                        (import + materialize + observe +
                                        teardown) and prints one JSON line per
                                        gym: {"gym":..., "runnable":bool, ...}.

Unknown --gym name: {"ok":false,"error":...} on stdout, exit 2 (fail-closed).

REAL collaborators only. Every episode runs through gymact's own `GymAct`
kernel -- its real admission/authority boundary -- never through a fake:

* Construction mirrors gymact's own tests:
  - `GymAct(authority_resolver=AllowListAuthorityResolver({AUTH}))` +
    `gym.register_provider(...)` + `MaterializationIntent(provider=...,
    config=...)` mirrors /Users/sac/gymact/tests/test_lock_and_key.py:23-35
    (`_gym()` / `_materialize()`).
  - chatman-state's materialize config `{"repo_limit": N}` mirrors
    /Users/sac/gymact/tests/test_chatman_state_gym.py:46-48.
  - DO actuation via `gym.act(ActuationIntent(episode_id=..., capability=...,
    payload=..., authority_ref=AUTH))` mirrors
    /Users/sac/gymact/tests/test_lock_and_key.py:71-84.
  - READ capabilities go through `gym.read(episode_id, iri, payload)` --
    the kernel's real READ port (/Users/sac/gymact/src/gymact/kernel.py:536-560);
    `gym.act()` refuses READ capabilities with
    `READ_CAPABILITY_IS_NOT_ACTUATION` (verified by a real run, see README).

Network policy (fail-closed): chatman-state's `list_github_repos` and
`portfolio_summary` bindings shell out to the live `gh` CLI
(/Users/sac/gymact/src/gymact/gyms/chatman_state.py -- "this session's own
already-authenticated `gh` CLI session"). This bridge is required to have NO
network side effects, so those two bindings are refused at the bridge boundary
with {"ok":false,...} before any dispatch; `list_local_repos` and
`estimated_effort_cost` are pure local filesystem + git subprocess and are
allowed.

SELECT/CONSTRUCT/DO doctrine: this bridge is the DO endpoint's transport only.
It never plans; it executes exactly one already-admitted action JSON per
"step" and reports the real consequence. Authority inside the episode is
gymact's own `AllowListAuthorityResolver` -- the bridge holds a single
episode-scoped authority ref and never fabricates admission for a capability
the kernel refuses.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from typing import Any

# --- gymact bootstrap -------------------------------------------------------
# The interpreter must already have gymact's dependencies (rfc8785, pydantic,
# blake3, ...). If `gymact` itself is not installed as a package, fall back to
# the source tree (read-only sys.path insertion; nothing is written there).
try:  # pragma: no cover - exercised for real by the test's interpreter probe
    import gymact  # noqa: F401
except ModuleNotFoundError:
    _src = os.environ.get("GYMACT_SRC", "/Users/sac/gymact/src")
    if os.path.isdir(_src):
        sys.path.insert(0, _src)
try:
    from gymact import AllowListAuthorityResolver, GymAct, MaterializationIntent
    from gymact.models import ActuationIntent, Consequence
except ModuleNotFoundError as exc:  # fail-closed, never a fake pass
    print(
        json.dumps(
            {
                "ok": False,
                "error": (
                    "BLOCKED: gymact not importable by this interpreter "
                    f"({exc}); run under an interpreter with gymact's "
                    "dependencies installed (see README.md)"
                ),
            }
        ),
        flush=True,
    )
    raise SystemExit(2)

AUTHORITY_REF = "urn:beam4pm:gym-bridge:authority"


# --- gym registry -----------------------------------------------------------
# Each entry: how to lazily import the real provider, the default materialize
# config, bindings refused at the bridge boundary (network policy), and the
# reward/done projection from the gym's own real observed state.


def _load_lock_and_key():
    from gymact.gyms.lock_and_key import LockAndKeyProvider

    return LockAndKeyProvider()


def _load_chatman_state():
    from gymact.gyms.chatman_state_gym import ChatmanStateProvider

    return ChatmanStateProvider()


def _load_cube_counter():
    # Requires the optional 'cube' extra (counter_cube); raises ImportError on
    # a machine without it -- probed for real by --list and reported
    # runnable:false in that case, never silently hidden.
    from gymact.gyms.cube_counter import CubeCounterProvider

    return CubeCounterProvider()


def _lock_reward(before: dict[str, Any], after: dict[str, Any]) -> float:
    return float(after.get("locks_open", 0) - before.get("locks_open", 0))


def _lock_done(state: dict[str, Any]) -> bool:
    return bool(state.get("solved")) or bool(state.get("dead_end"))


def _zero_reward(before: dict[str, Any], after: dict[str, Any]) -> float:
    del before, after
    return 0.0


def _never_done(state: dict[str, Any]) -> bool:
    del state
    return False


def _cube_reward(before: dict[str, Any], after: dict[str, Any]) -> float:
    # CUBE's own task.evaluate() reward, surfaced in the gym's observed state
    # (/Users/sac/gymact/src/gymact/gyms/cube_counter.py:83-89) -- report the
    # real delta, never a bridge-invented score.
    return float(after.get("reward", 0.0)) - float(before.get("reward", 0.0))


def _cube_done(state: dict[str, Any]) -> bool:
    return bool(state.get("solved"))


GYMS: dict[str, dict[str, Any]] = {
    "lock-and-key": {
        "provider": "lock-and-key",
        "load": _load_lock_and_key,
        "default_config": {"seed": 7, "depth": 3},
        "forbidden_bindings": {},
        "reward": _lock_reward,
        "done": _lock_done,
    },
    "chatman-state": {
        "provider": "chatman-state",
        "load": _load_chatman_state,
        "default_config": {"repo_limit": 5},
        "forbidden_bindings": {
            "list_github_repos": "network side effect (live gh CLI call) forbidden by bridge policy",
            "portfolio_summary": "network side effect (live gh CLI call) forbidden by bridge policy",
        },
        "reward": _zero_reward,
        "done": _never_done,
    },
    "cube-counter": {
        "provider": "cube-counter",
        "load": _load_cube_counter,
        # requires_authority=False: this bridge admits DO through gymact's
        # AllowListAuthorityResolver already; CUBE's counter is an in-memory
        # benchmark task with no external consequence.
        "default_config": {"target": 3, "requires_authority": False},
        "forbidden_bindings": {},
        "reward": _cube_reward,
        "done": _cube_done,
    },
}


class BridgeSession:
    """One live gymact episode behind the fixed wire protocol."""

    def __init__(self, gym_name: str, config: dict[str, Any]) -> None:
        self.gym_name = gym_name
        self.spec = GYMS[gym_name]
        self.config = config or dict(self.spec["default_config"])
        self.loop = asyncio.new_event_loop()
        self.gym: GymAct | None = None
        self.episode_id: str | None = None

    def _run(self, coro):
        return self.loop.run_until_complete(coro)

    # -- protocol ops --------------------------------------------------------

    def reset(self) -> dict[str, Any]:
        if self.gym is not None and self.episode_id is not None:
            try:
                self._run(self.gym.teardown(self.episode_id, authority_ref=AUTHORITY_REF))
            except Exception:
                pass
        # Real kernel + real authority resolver + real provider -- mirrors
        # /Users/sac/gymact/tests/test_lock_and_key.py:23-35.
        self.gym = GymAct(authority_resolver=AllowListAuthorityResolver({AUTHORITY_REF}))
        self.gym.register_provider(self.spec["load"]())
        materialization = self._run(
            self.gym.materialize(
                MaterializationIntent(provider=self.spec["provider"], config=self.config)
            )
        )
        if not materialization.accepted:
            raise RuntimeError(
                f"materialize refused: {materialization.receipt.reason}"
            )
        self.episode_id = materialization.episode.episode_id
        observation = self._run(self.gym.observe(self.episode_id))
        return {"ok": True, "observation": observation.state}

    def _resolve_capability(self, ref: str):
        assert self.gym is not None and self.episode_id is not None
        env = self.gym._episodes[self.episode_id].environment
        for cap in env.capabilities():
            if cap.iri == ref or cap.binding == ref:
                return cap
        raise ValueError(f"unknown capability for gym {self.gym_name!r}: {ref!r}")

    def step(self, action: Any) -> dict[str, Any]:
        if self.gym is None or self.episode_id is None:
            return {"ok": False, "error": "no live episode: send {\"op\":\"reset\"} first"}
        if not isinstance(action, dict):
            return {"ok": False, "error": "action must be a JSON object"}
        cap_ref = action.get("capability")
        if not isinstance(cap_ref, str) or not cap_ref:
            return {
                "ok": False,
                "error": "action.capability must be a non-empty string (binding or IRI)",
            }
        payload = action.get("payload", {})
        if not isinstance(payload, dict):
            return {"ok": False, "error": "action.payload must be a JSON object"}
        try:
            capability = self._resolve_capability(cap_ref)
        except ValueError as exc:
            return {"ok": False, "error": str(exc)}
        refusal = self.spec["forbidden_bindings"].get(capability.binding)
        if refusal is not None:
            return {
                "ok": False,
                "error": f"REFUSED:BRIDGE_NETWORK_POLICY {capability.binding}: {refusal}",
            }

        before_obs = self._run(self.gym.observe(self.episode_id)).state
        info: dict[str, Any] = {
            "capability": capability.iri,
            "binding": capability.binding,
            "consequence": capability.consequence.value,
        }
        try:
            if capability.consequence is Consequence.READ:
                # Kernel READ port -- /Users/sac/gymact/src/gymact/kernel.py:536-560.
                effect = self._run(self.gym.read(self.episode_id, capability.iri, payload))
                info["accepted"] = True
                # READ gyms differ in the key their env.actuate() uses:
                # chatman-state returns "result", lock-and-key's read_locks
                # returns "result_text" -- surface whichever is real.
                info["result"] = effect.get("result", effect.get("result_text"))
            else:
                # Kernel DO port with real authority admission -- mirrors
                # /Users/sac/gymact/tests/test_lock_and_key.py:71-84.
                result = self._run(
                    self.gym.act(
                        ActuationIntent(
                            episode_id=self.episode_id,
                            capability=capability.iri,
                            payload=payload,
                            authority_ref=AUTHORITY_REF,
                        )
                    )
                )
                info["accepted"] = bool(result.accepted)
                info["receipt_reason"] = result.receipt.reason
                info["receipt_standing"] = result.receipt.standing.value
                if result.effect is not None:
                    info["applicable"] = result.effect.get("applicable")
                    info["result_text"] = result.effect.get("result_text")
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}

        after_obs = self._run(self.gym.observe(self.episode_id)).state
        reward = self.spec["reward"](before_obs, after_obs)
        done = self.spec["done"](after_obs)
        return {
            "ok": True,
            "observation": after_obs,
            "reward": reward,
            "done": done,
            "info": info,
        }

    def close(self) -> dict[str, Any]:
        if self.gym is not None and self.episode_id is not None:
            try:
                self._run(self.gym.teardown(self.episode_id, authority_ref=AUTHORITY_REF))
            except Exception as exc:
                return {"ok": False, "error": f"teardown failed: {type(exc).__name__}: {exc}"}
        return {"ok": True}


# --- real gym probing (--list) ----------------------------------------------


def probe_gym(name: str) -> dict[str, Any]:
    """Probe one gym FOR REAL: import provider, materialize a real episode,
    observe real state, tear down. Never a fabricated verdict."""
    spec = GYMS[name]
    try:
        session = BridgeSession(name, dict(spec["default_config"]))
        reset = session.reset()
        obs_keys = sorted(reset["observation"].keys()) if reset.get("ok") else []
        closed = session.close()
        session.loop.close()
        return {
            "gym": name,
            "runnable": bool(reset.get("ok")) and bool(closed.get("ok")),
            "observation_keys": obs_keys,
        }
    except Exception as exc:
        return {"gym": name, "runnable": False, "error": f"{type(exc).__name__}: {exc}"}


# --- main loop ---------------------------------------------------------------


def emit(obj: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def serve(gym_name: str, config: dict[str, Any]) -> int:
    session = BridgeSession(gym_name, config)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as exc:
            emit({"ok": False, "error": f"invalid JSON line: {exc}"})
            continue
        if not isinstance(msg, dict):
            emit({"ok": False, "error": "each line must be a JSON object with an 'op'"})
            continue
        op = msg.get("op")
        try:
            if op == "reset":
                emit(session.reset())
            elif op == "step":
                emit(session.step(msg.get("action")))
            elif op == "close":
                emit(session.close())
                return 0
            else:
                emit({"ok": False, "error": f"unknown op: {op!r}"})
        except Exception as exc:  # non-fatal: report, keep serving
            emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
    # stdin EOF without close: tear down and exit cleanly.
    session.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gym", help="registered gym name (see --list)")
    parser.add_argument(
        "--config", default=None, help="JSON object overriding the gym's materialize config"
    )
    parser.add_argument(
        "--list", action="store_true", help="probe every registered gym for real and exit"
    )
    args = parser.parse_args(argv)

    if args.list:
        for name in GYMS:
            emit(probe_gym(name))
        return 0

    if not args.gym:
        emit({"ok": False, "error": "--gym <name> is required (or --list)"})
        return 2
    if args.gym not in GYMS:
        emit(
            {
                "ok": False,
                "error": f"unknown gym: {args.gym!r}; registered: {sorted(GYMS)}",
            }
        )
        return 2

    config: dict[str, Any] = {}
    if args.config is not None:
        try:
            config = json.loads(args.config)
        except json.JSONDecodeError as exc:
            emit({"ok": False, "error": f"--config is not valid JSON: {exc}"})
            return 2
        if not isinstance(config, dict):
            emit({"ok": False, "error": "--config must be a JSON object"})
            return 2

    return serve(args.gym, config)


if __name__ == "__main__":
    raise SystemExit(main())
