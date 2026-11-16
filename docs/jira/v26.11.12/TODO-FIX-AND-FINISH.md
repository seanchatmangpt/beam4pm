# TODO-FIX-AND-FINISH (beam4pm)

Standing: UNVERIFIED

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R9, re-read where marked confirmed.

## Fix

- HIGH `lib/beam4pm_powl_model.ex:379` calls `BeamPM.Digest.hash/1`; module lives only in
  untracked `lib/beam4pm_digest.ex` (confirmed `git status` `??`). Check: fresh clone
  `mix compile --warnings-as-errors` exits 0.
- MED `test/beam4pm_engine_dispatch_gate_test.exs:~236-255` absent engine source takes an
  `IO.puts` branch with zero assertions (confirmed; now prints BLOCKED, not fully silent).
  Check: test fails or is tagged skip loudly when source absent.
- MED `lib/beam4pm_repop_ocel_verifier.ex:155-156` ignores `:canonical_form`: UNVERIFIED
  (line now `Jason.decode`; re-locate). Check: planted bad canonical form is refused.
- MED `lib/beam4pm_repop_ocel_verifier.ex:509-512` `pinned_manifest` does `File.read!` (raises)
  at runtime (confirmed). Check: missing manifest returns typed refusal.
- MED `mix.exs:132-151` `ash_a2a` dep path / env / git-ref cond (confirmed); stale lock
  UNVERIFIED. Check: `mix deps.get` identical with and without sibling checkout.
- MED `lib/beam4pm_repop.ex:129-170` wasm resolved from cwd, pin checked at compile time:
  UNVERIFIED (not re-read). Check: run from other cwd succeeds.
- LOW `lib/beam4pm_codec.ex:14785` `String.to_atom(v)` in `convert_in(:atom, ...)` (confirmed);
  reachability UNVERIFIED. Check: enum allowlist, no `to_atom` in codec.
- LOW `lib/beam4pm_process_governor.ex:776` MatchError on malformed receipt: UNVERIFIED
  (line is `Jason.decode` case now). Check: malformed receipt returns typed error.
- LOW integrity chain omits attributes/objects, fnv1a32, no authenticity; dead code in
  `conformance.ex`; cubic DFS; DFS overflow reported as fitness 0: UNVERIFIED.

## Finish

- Add court: dispatch-source absence is a typed BLOCKED result, not a print.
- Tie digest seam (`beam4pm_digest.ex`) tests (`test/beam4pm_digest_test.exs`) into CI.
- Document `min_fitness` semantics. Check: moduledoc states comparison direction.

## Commit hygiene

- Untracked and required by tracked code: `lib/beam4pm_digest.ex`, `lib/beam4pm_repop.ex`,
  `lib/beam4pm_repop_ocel_verifier.ex`, `priv/repop/`, `test/fixtures/repop_ocel/`,
  `test/beam4pm_{a2a_router_http,digest,repop_ocel_verifier,repop}_test.exs` (confirmed `??`).
  Check: `git status --short | grep '??'` empty after commit.
- Modified-uncommitted: `lib/beam4pm_powl_model.ex`, `mix.exs`, `mix.lock`, `ontology.ttl`,
  a2a router/agent, 4 tests (confirmed ` M`). Check: clean tree.
- `native/ferroplan` submodule dirty (confirmed ` m`). Check: `git submodule status` clean.
- `qualification/fixtures/a2a/agent-card.json` modified; compared against live router it was
  generated from (UNVERIFIED). Check: fixture independent of router output.

## Decide

- Is `priv/repop/repop_kernel_wasm.wasm` a committed binary or built artifact?
- `ash_a2a` consumption: Hex pin, sibling path, or git ref as the single CI source.

## Reuse

- Fail-closed per-item validator `lib/beam4pm_ocel_log_ingest.ex:143-247` (UNVERIFIED lines).
- Injectable digest seam `lib/beam4pm_digest.ex`; closed-vocabulary refusals in repop verifier.

## See Also

- `/Users/sac/ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md`
- `/Users/sac/pm4exunit/docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md`
