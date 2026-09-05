"""Chicago-style tests for gym_bridge.py -- the REAL bridge subprocess against
REAL gymact gyms. No `unittest.mock` / `Mock` / `MagicMock` / `patch` /
`monkeypatch` anywhere in this file (grep-verified as part of the deliverable
evidence): every test spawns the actual `python3 gym_bridge.py --gym <name>`
subprocess, speaks the fixed JSON-lines protocol over its real stdin/stdout,
and asserts on the real returned observations, rewards, done flags, refusals,
and exit codes.

Interpreter resolution (real, probed -- never assumed):
  1. $GYM_BRIDGE_PYTHON if set;
  2. /Users/sac/gymact/.venv/bin/python (gymact's own venv, used read-only);
  3. sys.executable.
The first interpreter whose real `-c "import gymact"` subprocess exits 0 is
used. If none can import gymact, every test skips with a NAMED reason
(BLOCKED, not a fake pass) -- the same fail-closed convention as
/Users/sac/gymact/tests/test_chatman_state_gym.py's `pytest.mark.skipif` and
ggen-ecosystem's tests/test_container_smoke.sh.
"""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import unittest
from pathlib import Path

BRIDGE = str(Path(__file__).resolve().parent / "gym_bridge.py")
READ_TIMEOUT_S = 120.0  # chatman-state does a real depth-2 $HOME scan


def _resolve_interpreter() -> str | None:
    candidates = []
    env_python = os.environ.get("GYM_BRIDGE_PYTHON")
    if env_python:
        candidates.append(env_python)
    candidates.append("/Users/sac/gymact/.venv/bin/python")
    candidates.append(sys.executable)
    for candidate in candidates:
        if not candidate or not Path(candidate).exists():
            continue
        probe = subprocess.run(  # real import probe, no fabricated verdict
            [candidate, "-c", "import gymact"],
            capture_output=True,
            timeout=60,
        )
        if probe.returncode == 0:
            return candidate
    return None


PYTHON = _resolve_interpreter()
SKIP_REASON = (
    "BLOCKED: no interpreter on this machine can `import gymact` "
    "(tried $GYM_BRIDGE_PYTHON, /Users/sac/gymact/.venv/bin/python, "
    "sys.executable); build a scratch venv per README.md"
)


class BridgeProcess:
    """Real bridge subprocess with line-oriented JSON send/recv."""

    def __init__(self, *args: str) -> None:
        assert PYTHON is not None
        self.proc = subprocess.Popen(
            [PYTHON, BRIDGE, *args],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def send(self, obj: dict) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def send_raw(self, line: str) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def recv(self) -> dict:
        assert self.proc.stdout is not None
        ready, _, _ = select.select([self.proc.stdout], [], [], READ_TIMEOUT_S)
        if not ready:
            self.proc.kill()
            raise TimeoutError(f"no bridge response within {READ_TIMEOUT_S}s")
        line = self.proc.stdout.readline()
        if not line:
            raise EOFError(
                f"bridge stdout closed; stderr: {self.proc.stderr.read() if self.proc.stderr else ''!r}"
            )
        return json.loads(line)

    def roundtrip(self, obj: dict) -> dict:
        self.send(obj)
        return self.recv()

    def finish(self) -> int:
        try:
            if self.proc.stdin is not None:
                self.proc.stdin.close()
            return self.proc.wait(timeout=30)
        finally:
            if self.proc.poll() is None:
                self.proc.kill()
            for stream in (self.proc.stdout, self.proc.stderr):
                if stream is not None:
                    stream.close()


@unittest.skipIf(PYTHON is None, SKIP_REASON)
class TestLockAndKeyEpisode(unittest.TestCase):
    """reset + 2 real steps + close against the real lock-and-key gym."""

    def test_reset_step_step_close_protocol_and_state(self) -> None:
        bridge = BridgeProcess("--gym", "lock-and-key", "--config", '{"seed":7,"depth":3}')
        try:
            reset = bridge.roundtrip({"op": "reset"})
            self.assertIs(reset["ok"], True)
            obs = reset["observation"]
            self.assertEqual(obs["depth"], 3)
            self.assertEqual(obs["locks_open"], 0)
            self.assertIs(obs["solved"], False)
            self.assertIs(obs["holding_key"], False)

            step1 = bridge.roundtrip(
                {"op": "step", "action": {"capability": "pick_key", "payload": {"key": 0}}}
            )
            self.assertIs(step1["ok"], True)
            self.assertIs(step1["observation"]["holding_key"], True)
            self.assertEqual(step1["observation"]["held_key"], 0)
            self.assertEqual(step1["reward"], 0.0)
            self.assertIs(step1["done"], False)
            self.assertIs(step1["info"]["accepted"], True)
            self.assertIs(step1["info"]["applicable"], True)
            self.assertEqual(step1["info"]["consequence"], "DO")
            self.assertEqual(step1["info"]["receipt_standing"], "ALIVE")
            self.assertEqual(
                step1["info"]["capability"],
                "urn:gymact:lock-and-key:capability:pick_key",
            )

            step2 = bridge.roundtrip(
                {"op": "step", "action": {"capability": "drop_key", "payload": {}}}
            )
            self.assertIs(step2["ok"], True)
            self.assertIs(step2["observation"]["holding_key"], False)
            self.assertEqual(step2["observation"]["held_key"], -1)
            self.assertIs(step2["done"], False)
            self.assertIn("returned key 0", step2["info"]["result_text"])

            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)

    def test_irreversible_force_latch_reaches_a_real_dead_end(self) -> None:
        """depth=3: force once (+1 lock, rack jammed, 2 locks unreachable)
        -> dead_end=True -> the bridge reports done=True."""
        bridge = BridgeProcess("--gym", "lock-and-key", "--config", '{"seed":5,"depth":3}')
        try:
            reset = bridge.roundtrip({"op": "reset"})
            self.assertIs(reset["ok"], True)
            forced = bridge.roundtrip(
                {"op": "step", "action": {"capability": "force_latch", "payload": {}}}
            )
            self.assertIs(forced["ok"], True)
            self.assertEqual(forced["observation"]["locks_open"], 1)
            self.assertIs(forced["observation"]["rack_jammed"], True)
            self.assertIs(forced["observation"]["dead_end"], True)
            self.assertEqual(forced["reward"], 1.0)  # one real lock opened
            self.assertIs(forced["done"], True)  # dead end terminates the episode
            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)


@unittest.skipIf(PYTHON is None, SKIP_REASON)
class TestChatmanStateEpisode(unittest.TestCase):
    """Real machine-portfolio gym: local-filesystem reads allowed, live-gh
    bindings refused fail-closed at the bridge boundary."""

    def test_reset_step_step_close_with_real_local_data(self) -> None:
        bridge = BridgeProcess("--gym", "chatman-state", "--config", '{"repo_limit":3}')
        try:
            reset = bridge.roundtrip({"op": "reset"})
            self.assertIs(reset["ok"], True)
            self.assertEqual(reset["observation"], {"repo_limit": 3})

            step1 = bridge.roundtrip(
                {"op": "step", "action": {"capability": "list_local_repos", "payload": {}}}
            )
            self.assertIs(step1["ok"], True)
            self.assertEqual(step1["reward"], 0.0)
            self.assertIs(step1["done"], False)
            self.assertEqual(step1["info"]["consequence"], "READ")
            rows = step1["info"]["result"]
            self.assertLessEqual(len(rows), 3)
            self.assertGreater(len(rows), 0)
            for row in rows:  # real repos on this real machine
                self.assertIn("name", row)
                self.assertIn("path", row)
                self.assertTrue(Path(row["path"]).is_dir(), row["path"])

            step2 = bridge.roundtrip(
                {
                    "op": "step",
                    "action": {
                        "capability": "estimated_effort_cost",
                        "payload": {"repo": "/Users/sac/gymact", "since": "7 days ago"},
                    },
                }
            )
            self.assertIs(step2["ok"], True)
            cost = step2["info"]["result"]
            self.assertEqual(cost["unit"], "engineering_hour")
            self.assertEqual(cost["kind"], "declared_estimate")
            self.assertEqual(cost["source"], "commit-and-diff-size-heuristic-v1")
            self.assertGreaterEqual(cost["quantity"], 0.0)

            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)

    def test_network_binding_is_refused_fail_closed_and_bridge_survives(self) -> None:
        bridge = BridgeProcess("--gym", "chatman-state", "--config", '{"repo_limit":2}')
        try:
            self.assertIs(bridge.roundtrip({"op": "reset"})["ok"], True)
            refused = bridge.roundtrip(
                {"op": "step", "action": {"capability": "list_github_repos", "payload": {}}}
            )
            self.assertIs(refused["ok"], False)
            self.assertIn("REFUSED:BRIDGE_NETWORK_POLICY", refused["error"])
            # The refusal must not kill the session: a further real step works.
            after = bridge.roundtrip(
                {"op": "step", "action": {"capability": "list_local_repos", "payload": {}}}
            )
            self.assertIs(after["ok"], True)
            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)


@unittest.skipIf(PYTHON is None, SKIP_REASON)
class TestGymnasiumEpisode(unittest.TestCase):
    """Real CartPole-v1 episode via gymact's `GymnasiumProvider` -- proves
    ANY Gymnasium-API-compliant environment is drivable through this bridge
    with zero gym-specific bridge code (env_id is a runtime --config
    parameter, not a code-time dispatch key)."""

    def test_reset_step_step_close_protocol_and_state(self) -> None:
        bridge = BridgeProcess("--gym", "gymnasium", "--config", '{"env_id":"CartPole-v1"}')
        try:
            reset = bridge.roundtrip({"op": "reset"})
            self.assertIs(reset["ok"], True)
            obs = reset["observation"]
            self.assertEqual(obs["env_id"], "CartPole-v1")
            self.assertEqual(len(obs["observation"]), 4)  # CartPole's real 4-float state
            self.assertIsNone(obs["reward"])  # no step taken yet
            self.assertIs(obs["terminated"], False)
            self.assertIs(obs["truncated"], False)

            step1 = bridge.roundtrip(
                {"op": "step", "action": {"capability": "step", "payload": {"action": 0}}}
            )
            self.assertIs(step1["ok"], True)
            self.assertIsInstance(step1["reward"], float)  # real per-step CartPole reward
            self.assertIs(step1["done"], False)
            self.assertIs(step1["info"]["accepted"], True)
            self.assertEqual(step1["info"]["consequence"], "DO")
            self.assertEqual(step1["info"]["receipt_standing"], "ALIVE")
            self.assertEqual(
                step1["info"]["capability"], "urn:gymact:gymnasium:capability:step"
            )
            self.assertNotEqual(step1["observation"]["observation"], obs["observation"])

            step2 = bridge.roundtrip(
                {"op": "step", "action": {"capability": "step", "payload": {"action": 1}}}
            )
            self.assertIs(step2["ok"], True)
            self.assertIs(step2["done"], False)

            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)

    def test_illegal_action_is_refused_but_wire_protocol_survives(self) -> None:
        """CartPole's real Discrete(2) action space only admits {0, 1}. An
        illegal action is refused by gymact's own kernel (never smuggled
        through as a state change) and reported via info, not a wire-level
        error -- matching gymact's own
        test_illegal_action_is_refused_and_does_not_change_real_state."""
        bridge = BridgeProcess("--gym", "gymnasium")
        try:
            self.assertIs(bridge.roundtrip({"op": "reset"})["ok"], True)
            before = bridge.roundtrip(
                {"op": "step", "action": {"capability": "step", "payload": {"action": 0}}}
            )
            self.assertIs(before["ok"], True)

            refused = bridge.roundtrip(
                {"op": "step", "action": {"capability": "step", "payload": {"action": 99}}}
            )
            self.assertIs(refused["ok"], True)  # wire-level ok; kernel refused the action
            self.assertIs(refused["info"]["accepted"], False)
            self.assertIn("PROVIDER_ERROR:ValueError", refused["info"]["receipt_reason"])
            self.assertEqual(refused["info"]["receipt_standing"], "BLOCKED")
            self.assertEqual(  # real state did not change on refusal
                refused["observation"], before["observation"]
            )

            # The refusal must not kill the session: a further real step works.
            after = bridge.roundtrip(
                {"op": "step", "action": {"capability": "step", "payload": {"action": 1}}}
            )
            self.assertIs(after["ok"], True)
            self.assertIs(after["info"]["accepted"], True)

            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)

    def test_sample_action_is_read_and_does_not_change_state(self) -> None:
        bridge = BridgeProcess("--gym", "gymnasium")
        try:
            self.assertIs(bridge.roundtrip({"op": "reset"})["ok"], True)
            before = bridge.roundtrip(
                {"op": "step", "action": {"capability": "step", "payload": {"action": 0}}}
            )
            self.assertIs(before["ok"], True)

            sampled = bridge.roundtrip(
                {"op": "step", "action": {"capability": "sample_action", "payload": {}}}
            )
            self.assertIs(sampled["ok"], True)
            self.assertEqual(sampled["info"]["consequence"], "READ")
            self.assertIs(sampled["info"]["accepted"], True)
            self.assertEqual(  # a READ never changes the real episode state
                sampled["observation"], before["observation"]
            )

            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)


@unittest.skipIf(PYTHON is None, SKIP_REASON)
class TestProtocolConformance(unittest.TestCase):
    def test_unknown_gym_fails_closed_with_exit_2(self) -> None:
        result = subprocess.run(
            [PYTHON, BRIDGE, "--gym", "no-such-gym"],
            input='{"op":"reset"}\n',
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(result.returncode, 2)
        reply = json.loads(result.stdout.splitlines()[0])
        self.assertIs(reply["ok"], False)
        self.assertIn("unknown gym", reply["error"])

    def test_garbage_and_unknown_ops_get_ok_false_without_dying(self) -> None:
        bridge = BridgeProcess("--gym", "lock-and-key")
        try:
            bridge.send_raw("this is not json")
            bad_json = bridge.recv()
            self.assertIs(bad_json["ok"], False)
            self.assertIn("invalid JSON", bad_json["error"])

            bad_op = bridge.roundtrip({"op": "bogus"})
            self.assertIs(bad_op["ok"], False)
            self.assertIn("unknown op", bad_op["error"])

            step_before_reset = bridge.roundtrip(
                {"op": "step", "action": {"capability": "read_locks", "payload": {}}}
            )
            self.assertIs(step_before_reset["ok"], False)
            self.assertIn("reset", step_before_reset["error"])

            # After all that abuse, a real episode still runs.
            reset = bridge.roundtrip({"op": "reset"})
            self.assertIs(reset["ok"], True)
            self.assertEqual(reset["observation"]["locks_open"], 0)
            closed = bridge.roundtrip({"op": "close"})
            self.assertEqual(closed, {"ok": True})
        finally:
            self.assertEqual(bridge.finish(), 0)

    def test_list_probes_real_gyms_and_reports_lock_and_key_runnable(self) -> None:
        result = subprocess.run(
            [PYTHON, BRIDGE, "--list"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(result.returncode, 0)
        rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        by_name = {row["gym"]: row for row in rows}
        self.assertIn("lock-and-key", by_name)
        self.assertIn("chatman-state", by_name)
        # These two are pure-local and must be runnable wherever this suite
        # itself runs (the suite already proved gymact imports here).
        self.assertIs(by_name["lock-and-key"]["runnable"], True)
        self.assertIs(by_name["chatman-state"]["runnable"], True)
        for row in rows:
            self.assertIn("runnable", row)
            if not row["runnable"]:
                self.assertIn("error", row)  # a real probed failure, named


class TestBridgeSessionKernelReuse(unittest.TestCase):
    """Direct in-process check (no subprocess) that `BridgeSession` builds and
    registers its real `GymAct` kernel ONCE and reuses it across repeated
    resets, instead of rebuilding it (and re-paying GymAct's real SHACL
    profile validation -- see BridgeSession.__init__'s comment in
    gym_bridge.py, and gymact/kernel.py:83-110) on every reset call. Real
    object, real kernel, real state assertions (object identity, distinct
    episode ids) -- no mock/patch/monkeypatch anywhere in this class."""

    @classmethod
    def setUpClass(cls) -> None:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        try:
            import gym_bridge as gym_bridge_module  # real in-process import probe
        except BaseException as exc:  # gym_bridge.py itself raises SystemExit(2)
            raise unittest.SkipTest(  # when gymact isn't importable here
                f"BLOCKED: gym_bridge not importable in-process ({exc!r}); "
                "run this suite under an interpreter with gymact installed "
                "(see README.md)"
            ) from None
        cls.gym_bridge_module = gym_bridge_module

    def test_gym_kernel_identity_is_stable_across_repeated_resets(self) -> None:
        session = self.gym_bridge_module.BridgeSession(
            "lock-and-key", {"seed": 7, "depth": 3}
        )
        try:
            first = session.reset()
            self.assertIs(first["ok"], True)
            kernel_after_first_reset = session.gym
            episode_after_first_reset = session.episode_id

            second = session.reset()
            self.assertIs(second["ok"], True)
            # The SAME kernel object serves the second episode -- no
            # reconstruction, no re-registration. `register_provider` raises
            # ValueError on a duplicate provider name (kernel.py:188-194), so
            # a regression back to per-reset reconstruction would surface
            # here as a real crash, not a silently-passing behavior change.
            self.assertIs(session.gym, kernel_after_first_reset)
            self.assertIsNotNone(session.episode_id)
            self.assertNotEqual(session.episode_id, episode_after_first_reset)

            third = session.reset()
            self.assertIs(third["ok"], True)
            self.assertIs(session.gym, kernel_after_first_reset)
        finally:
            session.close()
            session.loop.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
