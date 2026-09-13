# Fortune 5 planning facade + enterprise planning capability boundary tests

## Summary

Added `BeamPM.EnterprisePlanning`, a facade module composing the existing
`BeamPM.Ferroplan` planning engine (classical/PDDL3/temporal, HTN/HDDL, FOND,
explanation, validation, and session/replanning surfaces) behind one explicit
planning contract. The module routes requests to the strongest admitted
native planning class per request, exposes a machine-readable capability
boundary (`capabilities/0`), and explicitly refuses named unsupported
planning classes (POMDP, contingent partial observability, probabilistic
MDP, continuous-time effects, dynamic derived predicates) rather than
silently degrading to a weaker planning model. A companion test file locks
this capability boundary and refusal behavior.

## Status

Done — already merged/committed.

## Commits

- `2c73b7f` feat(planning): add Fortune 5 planning facade
- `f66a926` test(planning): lock enterprise planning capability boundary

## Changes

- Added `lib/beam4pm_enterprise_planning.ex` (192 lines, new file) defining
  `BeamPM.EnterprisePlanning`:
  - `capabilities/0` — returns supported classes
    (`:classical, :numeric, :preferences, :temporal, :htn, :hddl, :fond`),
    unsupported classes (`:pomdp, :contingent_partial_observability,
    :probabilistic_mdp, :continuous_time_effects,
    :dynamic_derived_predicates`), the lifecycle operation list
    (`:solve, :validate, :explain, :replan, :fork_scenario, :observe,
    :goal_change, :bounded_search`), and fixed `authority: :candidate_only`
    / `actuation: :not_provided` markers.
  - `solve/2` — routes a `%{class:, domain:, problem:, ...}` request: PDDL
    classes (`:classical, :numeric, :preferences, :temporal`) go through
    `Ferroplan.plan_production/4` with per-class mode options; `:htn` →
    `Ferroplan.htn_plan/3`; `:hddl` → `Ferroplan.hddl_solve/3`; `:fond` →
    `Ferroplan.fond_policy/3`. Known-unsupported classes return
    `{:error, {:unsupported_planning_class, class}}`; unrecognized classes
    return `{:error, {:unknown_planning_class, other}}`; malformed requests
    (missing/mistyped required fields) return
    `{:error, {:invalid_planning_request, req}}` via a guard-clause fallback.
  - `explain/4` — delegates to `Ferroplan.explain/4` for a concrete candidate
    plan.
  - `validate/5` — opens a temporary native planning session via
    `with_session/4`, calls `Ferroplan.session_plan_valid?/4`, and always
    frees the session afterward (validation is inspection only).
  - `open_session/3`, `fork_scenario/2`, `observe/3`, `set_goal/3`,
    `replan/4`, `close_session/2` — thin delegations to the corresponding
    `Ferroplan.session_*` functions, with `replan/4` guarding on positive
    `evals`/`mem_mb` bounds.
  - Private helpers `production_options/2`, `merge_limits/2`, `maybe_put/3`,
    `with_session/4` for building per-class request options and
    session lifecycle management (open → run → always free).
- Added `test/beam4pm_enterprise_planning_test.exs` (40 lines, new file)
  with 4 `ExUnit` tests on `BeamPM.EnterprisePlanning`:
  1. `capabilities/0` declares `authority: :candidate_only`,
     `actuation: :not_provided`, the exact supported-class set, and that
     `:validate, :explain, :replan, :fork_scenario, :observe` are present in
     `lifecycle`.
  2. `solve/2` returns `{:error, {:unsupported_planning_class, class}}` for
     each of `:pomdp, :contingent_partial_observability,
     :probabilistic_mdp`.
  3. `solve/2` returns `{:error, {:unknown_planning_class, :magic}}` for an
     unrecognized class atom, distinguishing it from the named-unsupported
     case.
  4. `solve/2` returns `{:error, {:invalid_planning_request, %{class:
     :classical}}}` for a request missing required `domain`/`problem`
     fields.

## Verification

None stated. Neither commit message references a test/lint/CI run; the
second commit (`f66a926`) adds the `ExUnit` test file itself but the commit
message does not state that it was executed or that it passed.

## Related

None stated — no PR numbers or branch names appear in either commit subject.
