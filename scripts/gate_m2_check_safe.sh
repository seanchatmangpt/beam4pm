#!/usr/bin/env bash
# GATE M2 SIGKILL-survival wrapper.
#
# scripts/gate_m2_check.sh's own EXIT trap (restore_manufactured/
# restore_stash/restore_ontology) cannot fire on SIGKILL -- no bash trap can,
# per POSIX signal semantics. That means the recovery guarantee for a hard
# kill (CI timeout, OOM-killer, a forced kill) has to live OUTSIDE the killed
# process. This wrapper is that outside layer: it runs gate_m2_check.sh as a
# child, and regardless of how the child exits -- normal success, normal
# failure, or killed by a signal the child itself could never trap -- this
# wrapper (a separate, still-alive process) checks whether the git-recoverable
# paths (ontology.ttl, ggen.lock, the 4 hand-authored dependent test files)
# are still clean at the pre-run HEAD, and if not, restores them via
# `git checkout --` (the durable, on-disk-in-.git backup gate_m2_check.sh's
# own preflight guarantees is safe to use, since it refuses to run at all
# against a tree that was already dirty for those paths).
set -uo pipefail
cd "$(dirname "$0")/.."

GIT_RECOVERABLE_PATHS=(ontology.ttl ggen.lock \
  test/beam4pm_actuation_k8s_test.exs \
  test/beam4pm_process_governor_k8s_test.exs \
  test/beam4pm_pddl_projection_test.exs \
  test/beam4pm_ash_ai_tools_test.exs)

pre_dirty="$(git status --porcelain -- "${GIT_RECOVERABLE_PATHS[@]}" 2>/dev/null || true)"
if [ -n "$pre_dirty" ]; then
  echo "GATE M2 SAFE WRAPPER: REFUSED -- git-recoverable paths already dirty before starting:" >&2
  echo "$pre_dirty" >&2
  exit 1
fi

bash scripts/gate_m2_check.sh
child_status=$?

post_dirty="$(git status --porcelain -- "${GIT_RECOVERABLE_PATHS[@]}" 2>/dev/null || true)"
untracked_missing=0
for f in "${GIT_RECOVERABLE_PATHS[@]}"; do
  [ -f "$f" ] || untracked_missing=1
done

if [ -n "$post_dirty" ] || [ "$untracked_missing" -eq 1 ]; then
  echo "GATE M2 SAFE WRAPPER: git-recoverable paths left dirty/missing (child exited $child_status, likely SIGKILL or an unhandled abort) -- restoring from git HEAD:" >&2
  echo "$post_dirty" >&2
  for f in "${GIT_RECOVERABLE_PATHS[@]}"; do
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 && git checkout -- "$f"
  done
  restored_dirty="$(git status --porcelain -- "${GIT_RECOVERABLE_PATHS[@]}" 2>/dev/null || true)"
  if [ -n "$restored_dirty" ]; then
    echo "GATE M2 SAFE WRAPPER: restore FAILED, tree still dirty:" >&2
    echo "$restored_dirty" >&2
    exit 1
  fi
  echo "GATE M2 SAFE WRAPPER: restored git-recoverable paths to pre-run HEAD state." >&2
fi

exit "$child_status"
