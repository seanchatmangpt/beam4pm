---
id: b4p-f5-10-ash-a2a-commandbus-skill-name-collision
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "ash_a2a: CommandBus re-dispatch resolves :change skills by skill.name — every duplicate-action-name :change skill (e.g. `create` across 597 resources) is refused :capability_mismatch; only the index-first namesake actuates"
standing: BLOCKED
branch: (ash_a2a) fix/commandbus-skill-name-resolution
worktree: ~/ash_a2a-wt/<new>
created: 2026-09-18T16:55:00Z
source: beam4pm capability sweep (wave agent A1, 2026-09-18, worktree wt-f5-capability @ b6d07f8, WAVE-RECEIPT.md) against ash_a2a 26.9.17 hex + main @ fa51fc8
depends: none (follows the v26.9.12+ all-public-actions default this wave consumed in beam4pm)
---

Read `_CONTEXT.md` first. Found by the operator-ordered "make sure all
capabilities work" sweep after beam4pm consumed the v26.9.12+ default in
which every public Ash action is exposed as a skill.

## The defect (fail-safe, but capability-destroying)

`CommandBus` re-dispatches a `:change`/`:external_do` skill by
`skill.name` alone (e.g. `:create`); `fetch_skill` resolves that name to
the index-FIRST skill with that name. On a multi-resource domain — which
is now the DEFAULT surface, since every public action becomes a skill — a
dispatch intended for `ResourceB.create` is routed to the anchor of
`ResourceA.create` (the index-first `create`), and BRCE then refuses with
`:capability_mismatch`. Measured on beam4pm's 1194-skill card: 597
`:create` skills exist; exactly 1 (the index-first) can actuate; the other
596 are refused fail-closed. No garbage is admitted (the failure is a
typed refusal — the safe direction), but the entire `:change` half of the
card is inoperable on any domain with duplicate action names.

## Scope (work lives in ~/ash_a2a)

1. Reproduce: two resources with same-named public `:create` actions; a
   granted dispatch to the second one returns `:capability_mismatch`
   while the first actuates. Fail-before receipt in ticket History.
2. Fix the resolution: CommandBus must carry the FULL capability id
   (`Resource.Action`) or the exact `%AshA2A.Skill{}` through the
   re-dispatch — never the bare display name. Keep the wire format
   backward-compatible (`metadata[:skill]` still accepts the short name
   where unambiguous; ambiguous names must resolve by the card's skill
   id, with a typed refusal when still ambiguous).
3. Non-vacuous tests: ambiguous-name dispatch actuates the right
   resource; unambiguous short name still works; still-ambiguous input
   refuses typed.
4. beam4pm consumption gate: rerun the A1 sweep probes (596 refused
   creates must drop to 0) + `mix test` green.

## Gates

- ash_a2a: fail-before/pass-after evidence in History; `mix test
  --max-cases 6` green; architecture verifier 17/17.
- beam4pm: capability sweep shows every `:change` skill reachable with a
  grant; suite green.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T16:55:00Z | BLOCKED | — | filed from wave receipt (A1): card==index 1194; 597 observe+597 change; only index-first `create` actuates; 596 typed `:capability_mismatch` refusals; replay/authority behavior otherwise correct | all |
| 2026-09-18T19:00:00Z | ALIVE (fix landed upstream; hex pick-up pending next release) | ash_a2a `main @ baa135d` (pushed, 0 ahead) via fix/commandbus-skill-name-resolution | FIXED + GATED. Fail-before: full-id dispatch to DupB.create -> :capability_mismatch (brce_gate); bare `create` SILENTLY actuated the index-first namesake. Fix: Dispatcher.dispatch/6 `resolved_skill:` opt (exact skill through the re-dispatch; selector lookup unchanged for all other callers; telemetry/OCEL shape unchanged); fetch_skill/2 + Info.skill/2 exact-id-wins + typed `{:ambiguous_skill, selector}` on multi-match; CommandBus maps it to refusal(:ambiguous_skill); S42 ambiguous_skill -> refused_capability (classification tripwire caught the gap as designed); Chicago actuator-arity law consciously updated dispatch/5 -> dispatch/6 (court caught it as designed). Pass-after: duplicate-action-names test 4/0; affected suites 20/0; architecture verifier 17/17; full suite 2076 tests / 3 failures = documented VendorCwd flake trio. beam4pm consumption gate: full sweep — 597/597 `:change` skills granted + reachable, ZERO capability-level refusals (priv/consumption_sweep_f510.exs on chore/a2a-capability-sweep-v26917; mix.exs path-override left uncommitted by design); beam4pm suite 1087/0. REMAINING: hex release cut on ash_a2a so default `~> 26.9` consumers get the fix without the override | none upstream; hex release = operator cut |
