#!/usr/bin/env bash
# b4pm_1704_guarded_def_crosscheck.sh -- B4PM-1704
#
# Cross-checks scripts/rename_function_preflight_guard.exs's shape (b)
# refusal against the actual documented failure mode from
# docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4, root
# cause (b): a real `mix igniter.refactor.rename_function` subprocess
# invocation against a guarded-def fixture silently renames call sites
# while leaving the guarded definition itself untouched, with exit 0 and
# no error surfaced.
#
# Requires a local checkout of ~/ggen_igniter (the umbrella that vendors
# `igniter.refactor.rename_function` as a real, compiled Mix task) with
# deps already fetched/compiled -- same precondition documented in
# ~/ggen_igniter/test/ggen_igniter_base_mix_task_end_user_test.exs, which
# this script's evidence method matches: copy real fixture content into a
# temporary subdirectory of that project's own working tree (so it
# compiles against already-fetched deps with no network access), run the
# real CLI subprocess, inspect the result, then remove the probe
# directory -- verified clean via `git status --short`.
#
# This script is READ-ONLY with respect to beam4pm: it only touches a
# temporary directory inside ~/ggen_igniter, always removed before exit.
#
# Usage: bash scripts/b4pm_1704_guarded_def_crosscheck.sh

set -euo pipefail

GGEN_IGNITER_ROOT="${GGEN_IGNITER_ROOT:-$HOME/ggen_igniter}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/b4pm_1704/shape_b_guarded_def.ex"
PROBE_REL="lib/tmp_b4pm1704_probe_crosscheck"
PROBE="$GGEN_IGNITER_ROOT/$PROBE_REL"

if [ ! -d "$GGEN_IGNITER_ROOT" ]; then
  echo "SKIPPED: ggen_igniter checkout not found at $GGEN_IGNITER_ROOT" >&2
  echo "Set GGEN_IGNITER_ROOT to a local checkout with deps compiled to run this cross-check." >&2
  exit 0
fi

cleanup() {
  rm -rf "$PROBE"
}
trap cleanup EXIT

rm -rf "$PROBE"
mkdir -p "$PROBE"
cp "$FIXTURE" "$PROBE/shape_b_guarded_def.ex"

echo "=== before rename (real fixture, guarded def) ==="
grep -n "def read\|def caller\|fetch(id)\|read(id)" "$PROBE/shape_b_guarded_def.ex"

echo
echo "=== running real: mix igniter.refactor.rename_function ==="
( cd "$GGEN_IGNITER_ROOT" && \
  mix igniter.refactor.rename_function \
    "B4pm1704Fixtures.ShapeBGuardedDef.read/1" \
    "B4pm1704Fixtures.ShapeBGuardedDef.fetch/1" \
    --yes )
subprocess_exit=$?

echo
echo "=== after rename ==="
grep -n "def read\|def caller\|fetch(id)\|read(id)" "$PROBE/shape_b_guarded_def.ex"

echo
echo "subprocess exit code: $subprocess_exit (expected 0 -- no error surfaced)"

if [ "$subprocess_exit" -ne 0 ]; then
  echo "UNEXPECTED: subprocess did not exit 0; this run does not reproduce the documented silent-partial-rename failure mode." >&2
  exit 1
fi

if grep -q "def read(id) when is_atom(id) do" "$PROBE/shape_b_guarded_def.ex" \
   && grep -q "fetch(id)" "$PROBE/shape_b_guarded_def.ex" \
   && ! grep -q "with {:ok, value} <- read(id) do" "$PROBE/shape_b_guarded_def.ex"; then
  echo
  echo "CONFIRMED: silent partial rename reproduced --"
  echo "  guarded definition 'def read(id) when is_atom(id) do' left UNCHANGED,"
  echo "  call site renamed 'read(id)' -> 'fetch(id)', exit 0, no error surfaced."
  echo "This is the exact documented failure mode from"
  echo "docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4, root cause (b),"
  echo "which scripts/rename_function_preflight_guard.exs's shape (b) refusal exists to prevent."
  exit 0
else
  echo "UNEXPECTED: file content after rename does not match the documented partial-rename shape." >&2
  exit 1
fi
