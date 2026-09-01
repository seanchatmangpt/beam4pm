#!/usr/bin/env bash
# B4PM-1708 -- standing regression guard for the receipt_chain_sync.sh ->
# actuation_sync.sh / process_governor_sync.sh chained pipeline.
#
# Precondition this guard exists to protect (B4PM-1708 acceptance bullet 1,
# reproduced verbatim from the real file content as of this story):
#
#   lib/beam4pm_process_governor.ex:474:
#       def contracts, do: @contracts
#   lib/beam4pm_process_governor.ex:158 (inside initial_snapshot/2):
#       def initial_snapshot(process_id, _opts \\ []) when is_binary(process_id) do
#   lib/beam4pm_process_governor.ex:362 (inside run/2):
#       def run(process_id, actuation_opts) when is_binary(process_id) and is_list(actuation_opts) do
#
# These are exactly the two known-bad Igniter.Refactors.Rename hazard
# shapes documented as Defect 4 in
# docs/jira/v26.8.31/03-known-defects-and-mitigations.md: shape (a) a
# parenless zero-arity def (line 474), and shape (b) a guarded def with a
# `when` clause (lines 158, 362). B4PM-1704 built the real AST pre-flight
# guard for these two shapes
# (scripts/rename_function_preflight_guard.exs). No rename step exists in
# the current pipeline (this guard's own PASS below re-confirms that for
# real, every run) -- this script's job is to make sure that stays true: if
# a future change ever wires Igniter.Refactors.Rename into
# receipt_chain_sync.sh, actuation_sync.sh, or process_governor_sync.sh, it
# cannot do so without also invoking the B4PM-1704 guard in the same file.
#
# Usage: bash scripts/rename_hazard_pipeline_guard.sh [script...]
#   With no arguments, checks the real chained pipeline (the 3 scripts
#   named in B4PM-1708). With arguments, checks exactly those files instead
#   (used by the B4PM-1708 fixture to prove real refusal without touching
#   the real pipeline scripts).
set -euo pipefail
cd "$(dirname "$0")/.."

RENAME_PATTERN='Igniter\.Refactors\.Rename'
GUARD_PATTERN='rename_function_preflight_guard\.exs'

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=(
    scripts/receipt_chain_sync.sh
    scripts/actuation_sync.sh
    scripts/process_governor_sync.sh
  )
fi

violations=()

for f in "${TARGETS[@]}"; do
  if [ ! -f "$f" ]; then
    echo "rename_hazard_pipeline_guard: FAIL -- target file does not exist: $f" >&2
    exit 2
  fi

  if grep -qE "$RENAME_PATTERN" "$f"; then
    if ! grep -qE "$GUARD_PATTERN" "$f"; then
      violations+=("$f")
    fi
  fi
done

if [ "${#violations[@]}" -gt 0 ]; then
  echo "rename_hazard_pipeline_guard: REFUSED -- Igniter.Refactors.Rename call(s)" >&2
  echo "found without the B4PM-1704 pre-flight guard" \
       "(rename_function_preflight_guard.exs) also invoked in the same file:" >&2
  for v in "${violations[@]}"; do
    echo "  - $v" >&2
  done
  echo "Wire scripts/rename_function_preflight_guard.exs into the same code" \
       "path before any Igniter.Refactors.Rename call in these files." >&2
  exit 1
fi

echo "rename_hazard_pipeline_guard: PASS -- no unguarded Igniter.Refactors.Rename" \
     "call in: ${TARGETS[*]}"
