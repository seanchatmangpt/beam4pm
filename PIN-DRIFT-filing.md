# PIN-DRIFT-filing.md — autofde-lab ferroplan pin drift (b4p-f5-05 scope 4)

FILED, NOT FIXED. This ticket only leaves the named pointer; the autofde-lab
re-pin is its own ticket (its receipts bind to the pin — see §3). Filed
2026-09-18 by the b4p-f5-05 audit wave, branch `chore/ferroplan-pin-audit`.

## 1. The pin, as it exists today

- File: `/Users/sac/autofde-lab/src/autofde_lab/wasm/_registry.py` (line 172).
  NOTE: `_CONTEXT.md` recorded the shorthand path `~/autofde-lab/_registry.py`;
  the file actually lives under `src/autofde_lab/wasm/` since the
  `src/skdecide → src/autofde_lab` move (autofde-lab commit `891509f6`).
- Entry: component `ferroplan`, `capability_class="planning-runtime"`,
  `branch="main"`, `revision="282fae46a7cf4f71ab473e33b5f3fdb4d73433c9"`.
- Pinned commit: `282fae4` — "feat(core): implement and oracle-admit all
  planning families (#38)", dated **2026-08-05**. It predates the entire
  FOND-HTN line (native HDDL front-end, `solve_hddl`, FOND policies, wasm
  ops `hddl_solve`/`htn_plan`/`fond_policy`).

## 2. Drift, measured (commands in the worktree submodule clone after
cross-fetch; exits in WAVE-RECEIPT.md)

| comparison | result |
|---|---|
| `282fae4` vs ~/ferroplan local `main` (`6cacbda`) | `git rev-list --left-right --count 282fae4...6cacbda` → **0 / 384** — the pin is 384 commits behind the local hardened main |
| `282fae4` vs ferroplan `origin/main` (`1ac9520`) | **0 / 199** — the pin is an ancestor of what is ALREADY PUSHED upstream; 199 commits are available without any of the unpushed 185 |
| reachability | `282fae4` is an ancestor of both `origin/main` and local `main` — a fast-forward re-pin, no reconcile needed on the autofde side |

Drift summary: even a conservative re-pin to ferroplan `origin/main` would
advance the registry 199 commits (all FOND-HTN waves 1–4); a re-pin to
post-wave-6 reconciled main (after b4p-f5-04 + b4p-f5-05 scope 2–3) would
carry the full 384+ line including both FOND soundness fixes
(FOUND_BUG_1 on main, FOUND_BUG_2 at `d00dcf8`) that `282fae4` predates.

## 3. What autofde receipts bind to

`src/autofde_lab/wasm/_model.py` enforces exact-revision receipt binding:

- line 94–96: a component revision must be an exact 40-char SHA (no branch
  floats) — the pin is deliberately immovable-by-accident;
- line 154: receipts record `"source_revision": self.component.revision`;
- line 202: `if subject.get("source_revision") != component.revision` —
  receipts whose `source_revision` differs from the registry pin do not
  admit.

Consequence: any pin bump changes what future receipts bind to and orphans
comparison against existing receipts earned on `282fae4`. Existing
receipts stay valid (they name their own revision), but cross-revision
verdict comparisons are NOT meaningful — ferroplan verdicts moved inside the
drift window (e.g. HDDL fixtures can go `solved → NoPlan` under the
hardened empty-task-network semantics; see `_CONTEXT.md` probe). The upgrade
must re-earn receipts on the new pin and re-baseline any recorded verdicts.

## 4. Handoff (for the owning ticket, when cut)

1. Do it AFTER the beam4pm reconcile (b4p-f5-05 scope 2–3) so autofde-lab
   pins the SAME reunion commit as beam4pm — three pins become one, not
   three becomes two.
2. Bump `revision` in `src/autofde_lab/wasm/_registry.py` (exact SHA only).
3. Rebuild the wasm artifact at the new pin; re-run the planning component
   gates; re-earn or explicitly re-baseline receipts whose
   `source_revision` changed.
4. Expect verdict movement (FOND/HDDL semantics hardened across the 384
   commits); treat new refusals as engine truth (precedent: beam4pm
   `ace23e5` corrected a false-positive solve to the engine's real
   `NoPlan`/`FP_MODEL`).
