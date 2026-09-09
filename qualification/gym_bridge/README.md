# Gym Bridge: beam4pm actuation over real gymact gyms

Stream P2 of beam4pm's actuator substrate (gates PI7/PI8). `gym_bridge.py` is
the fixed-wire-protocol DO endpoint: a JSON-lines subprocess wrapping REAL
gyms from `/Users/sac/gymact` (read-only), driven through gymact's own
`GymAct` kernel -- its real admission/authority boundary -- never a fixture.

Doctrine: the bridge never plans and never grants itself authority. It
executes exactly one already-constructed action JSON per `step` and reports
the real consequence. `SELECT`/`CONSTRUCT` happen upstream in beam4pm's
planner; `DO` happens here, gated by gymact's own `AllowListAuthorityResolver`.

## Wire protocol (fixed)

```text
python3 gym_bridge.py --gym <name> [--config '<json>']

in:  {"op":"reset"}                 out: {"ok":true,"observation":<json>}
in:  {"op":"step","action":<json>}  out: {"ok":true,"observation":<json>,
                                          "reward":<num>,"done":<bool>,
                                          "info":<json>}
in:  {"op":"close"}                 out: {"ok":true}   then exit 0
any error: {"ok":false,"error":"<reason>"} on stdout; the bridge keeps
running unless fatal. Unknown --gym: {"ok":false,...} then exit 2.
```

The `action` object is `{"capability": "<binding or IRI>", "payload": {...}}`.
`info` carries the capability IRI, its `consequence` (`READ`/`DO`), kernel
acceptance, receipt standing, and the gym's own applicability/result fields.

## Gyms probed, and which actually run here

Probed FOR REAL on this machine (import + kernel materialize + observe +
teardown, via `--list`) on 2026-09-04, interpreter
`/Users/sac/gymact/.venv/bin/python` (Python 3.13.9, used read-only):

```text
$ /Users/sac/gymact/.venv/bin/python gym_bridge.py --list
{"gym": "lock-and-key", "runnable": true, "observation_keys": ["dead_end", "depth", "final_open", "held_key", "holding_key", "locks_open", "rack_jammed", "solved"]}
{"gym": "chatman-state", "runnable": true, "observation_keys": ["repo_limit"]}
{"gym": "cube-counter", "runnable": false, "error": "ImportError: cube_counter requires the optional 'cube' extra (...)"}
{"gym": "gymnasium", "runnable": true, "observation_keys": ["env_id", "info", "observation", "reward", "terminated", "truncated"]}
```

(`cube-counter`'s `runnable:false` here is this machine's own missing
`cube` extra, unrelated to the bridge itself -- reported by `--list`'s real
probe, never hidden, per its own doctrine below.)

1. `lock-and-key` (`gymact.gyms.lock_and_key`) -- pure Python, no network, no
   Docker, no optional packages. Hidden seeded key permutation, reversible
   `pick_key`/`drop_key`, irreversible `force_latch` dead-end trap. Reward =
   real `locks_open` delta; `done` = `solved or dead_end`.
2. `chatman-state` (`gymact.gyms.chatman_state_gym`) -- REAL portfolio state
   of this machine (`.git` scan under `$HOME`, real `git log`). Bridge policy
   refuses the two live-`gh` bindings (`list_github_repos`,
   `portfolio_summary`) fail-closed with `REFUSED:BRIDGE_NETWORK_POLICY` --
   this bridge must have no network side effects; `list_local_repos` and
   `estimated_effort_cost` are local-only and allowed.
3. `cube-counter` (`gymact.gyms.cube_counter`) -- CUBE's own no-Docker
   `counter-cube` benchmark; runnable when gymact's venv has the `cube`
   extra installed. On a machine without `counter_cube`, `--list` reports it
   `runnable:false` with the real ImportError, never hidden.
4. `gymnasium` (`gymact.gyms.gymnasium_env.GymnasiumProvider`) -- generic
   bridge over the standard `gymnasium` package's own environment registry
   (63 environments registered in a plain interpreter with zero optional
   extras, measured via `python3 -c "import gymnasium;
   print(len(gymnasium.registry))"`, growing with Box2D/MuJoCo/Atari extras
   and third-party `gymnasium.register()` calls). `env_id` is a runtime
   `--config` parameter (default `CartPole-v1`), not a code-time dispatch
   key: this ONE registry entry drives ANY already-registered
   Gymnasium-API-compliant environment with zero gym-specific bridge code.
   Reward = gymnasium's own real per-step `reward` (not a delta -- unlike
   lock-and-key/CUBE, gymnasium's `reward` is already the per-step value,
   not a cumulative counter); `done` = `terminated or truncated`, gymnasium's
   own real episode-end signal.

Gyms not bridged, with reasons observed in their sources: `cloud_topology_gym`
(needs botocore data files -- offline but an optional extra), `aws_botocore_*`
(same family), `browsergym`/`swegym`/`sregym` (external benchmark stacks),
`gcp_*` (provider census data / live probes), `terraform_*` (external
tooling), `inspect_evals.py`'s `InspectEvalsProvider` (materializes one
hardcoded Sample/task rather than adapting an open registry -- not the same
unbounded-scaling shape as `gymnasium_env.py`'s `GymnasiumProvider`).

## Real gymact construction mirrored (file:line)

- Kernel + resolver + provider + materialize:
  `/Users/sac/gymact/tests/test_lock_and_key.py:23-35` (`_gym()`,
  `_materialize()`); chatman-state config `{"repo_limit": N}` mirrors
  `/Users/sac/gymact/tests/test_chatman_state_gym.py:46-48`.
- DO actuation `gym.act(ActuationIntent(..., authority_ref=...))`:
  `/Users/sac/gymact/tests/test_lock_and_key.py:71-84`.
- READ port `gym.read(episode_id, iri, payload)`:
  `/Users/sac/gymact/src/gymact/kernel.py:536-560`. Verified by a real run
  that `gym.act()` on a READ capability is refused
  `REFUSED:READ_CAPABILITY_IS_NOT_ACTUATION` -- the bridge routes by each
  capability's real `Consequence`, honoring gymact's own consequence law.

## Interpreter

The invoking `python3` must be able to `import gymact` (rfc8785, pydantic,
blake3, ...). Resolution order used by the tests: `$GYM_BRIDGE_PYTHON`, then
`/Users/sac/gymact/.venv/bin/python` (read-only use of gymact's own venv),
then `sys.executable` -- each probed by a real `-c "import gymact"`
subprocess. To build a scratch venv without touching gymact:

```bash
python3 -m venv "$SCRATCH/venv"
"$SCRATCH/venv/bin/pip" install /Users/sac/gymact   # builds from source, writes nothing there
GYM_BRIDGE_PYTHON="$SCRATCH/venv/bin/python" python3 -m unittest test_gym_bridge -v
```

If no interpreter can import gymact, the bridge prints
`{"ok":false,"error":"BLOCKED: ..."}` and exits 2, and the tests skip with a
named BLOCKED reason -- never a fake pass.

## How BeamPM.Actuation invokes it

The BRCE broker (gate PI8) opens the bridge as an Erlang port and speaks the
protocol line-by-line; planner output (`planning_action` records --
`BeamPM.Types.Manifest.fields(:planning_action) == [:action_name,
:preconditions, :effects]`) is admitted first (`policy_decision`), and only
the admitted action's JSON crosses into `step`:

```elixir
port = Port.open({:spawn_executable, System.find_executable("python3")},
  [:binary, {:line, 1_048_576}, args: [bridge_py, "--gym", "lock-and-key"]])
Port.command(port, Jason.encode!(%{op: "reset"}) <> "\n")
# admitted planning_action -> {"op":"step","action":{"capability":...,"payload":...}}
# each reply feeds observation_before/after into the beam4pm-brce/v1 receipt,
# with BeamPM.Codec.to_map(:ocel_event, ...) rows for plan/admit/execute/observe.
Port.command(port, Jason.encode!(%{op: "close"}) <> "\n")
```

The receipt's `replay` block records `{"gym": name, "bridge_cmd": "python3
gym_bridge.py --gym <name>", "action_json": <exact step line>}` so the
actuation is replayable byte-for-byte against the same bridge.

## Qualification (Chicago, no mocks)

```bash
/Users/sac/gymact/.venv/bin/python -m unittest test_gym_bridge -v
```

10 tests, all against the real subprocess and real gyms: full
reset/step/step/close episodes for lock-and-key, chatman-state, and
gymnasium (real CartPole-v1), the irreversible `force_latch` dead-end, the
fail-closed network-policy refusal, gymnasium's illegal-action refusal and
READ-capability (`sample_action`) state-invariance, garbage/unknown-op
resilience, unknown-gym exit 2, and a real `--list` probe. Mock-grep over
this directory returns zero matches (verified each run):

```bash
grep -rn "unittest.mock\|Mock(\|MagicMock\|patch(\|monkeypatch" .
```
