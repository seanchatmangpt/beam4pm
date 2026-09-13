# Document RF1/RF2/RF3 native oracle build + env var setup

## Summary

RF1 (dfg-discovery), RF2 (conformance), and RF3 (OCEL) qualification suites were
failing because their native Rust oracle binaries under `native/*/target/`
(gitignored) had not been built, and RF2/RF3's `System.fetch_env!/1`-based env
vars were not set. The three oracles were built for real
(`cargo build --release` in `native/rf1-dfg-oracle`, `native/rf2-conformance-oracle`,
`native/rf3-ocel-oracle`) and the targeted suites run with the real env vars
pointed at the real fixtures under `qualification/fixtures/`, resulting in
19/19 passing. The recipe is now documented in `CONTRIBUTING.md` so it does not
need to be re-derived from test file comments each session.

## Status

Done - already merged/committed.

## Commits

- `91c83ab` docs: document RF1/RF2/RF3 native oracle build + env var setup

## Changes

- Added a 40-line section to `CONTRIBUTING.md` documenting the build+env recipe
  for the three oracle-backed qualification suites (1 file changed, 40
  insertions, 0 deletions).
- Documents building all three native oracles via `cargo build --release` in
  `native/rf1-dfg-oracle`, `native/rf2-conformance-oracle`, and
  `native/rf3-ocel-oracle`.
- Documents the `System.fetch_env!/1`-based environment variables RF2/RF3
  require, pointed at the real fixtures under `qualification/fixtures/`.
- Explicitly does not commit the built binaries (gitignored build artifacts
  under `native/*/target/`) and does not bake the env vars into a committed
  `.env.test`, since they are machine/build-specific absolute paths — documented
  as a recipe instead.

## Verification

Per the commit message: ran the targeted RF1/RF2/RF3 suites with the real env
vars against real fixtures — 19/19 pass. Full `mix test` run: 1073 tests, 0
failures, 88 skipped (down from 18 failures prior to the fix). No CI run or
lint output stated in the commit message.

## Related

None stated (no PR number or branch name in the commit subject or message).
