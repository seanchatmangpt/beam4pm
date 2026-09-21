#!/usr/bin/env bash
# WS2 DfCM scheduled-task recovery court.
#
# Purpose: verify an already-manufactured WS2 planning crown at one exact,
# contained subject. This court is OBSERVE/VERIFY only. It never manufactures
# new semantic work, commits, pushes, merges, publishes, deploys, or grants DO
# authority.
set -euo pipefail

DEFAULT_SUBJECT_SHA="574368706e6afd804c7a13771bed3cf03da33ce0"
SUBJECT_SHA="${1:-$DEFAULT_SUBJECT_SHA}"
REPO_ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MAIN_REF="${WS2_DFCM_MAIN_REF:-origin/main}"
EXPECTED_COUNT="${WS2_DFCM_EXPECTED_COUNT:-50}"

refuse() {
  local code="$1"
  shift
  printf 'REFUSED[%s]:%s\n' "$code" "$*" >&2
  exit 2
}

cd "$REPO_ROOT"

git rev-parse --git-dir >/dev/null 2>&1 || refuse NOT_A_GIT_REPOSITORY "$REPO_ROOT"
TARGET_SHA="$(git rev-parse --verify "${SUBJECT_SHA}^{commit}" 2>/dev/null)" ||
  refuse SUBJECT_NOT_FOUND "$SUBJECT_SHA"
HEAD_SHA="$(git rev-parse HEAD)"

[ "$HEAD_SHA" = "$TARGET_SHA" ] ||
  refuse SUBJECT_MISMATCH "head=$HEAD_SHA target=$TARGET_SHA"

git diff --quiet || refuse DIRTY_WORKTREE "unstaged changes present before verification"
git diff --cached --quiet || refuse DIRTY_INDEX "staged changes present before verification"
[ -z "$(git ls-files --others --exclude-standard)" ] ||
  refuse UNTRACKED_INPUT "untracked files present before verification"

git rev-parse --verify "${MAIN_REF}^{commit}" >/dev/null 2>&1 ||
  refuse MAIN_REF_UNAVAILABLE "$MAIN_REF"

git merge-base --is-ancestor "$TARGET_SHA" "$MAIN_REF" ||
  refuse SUBJECT_NOT_CONTAINED "target=$TARGET_SHA main_ref=$MAIN_REF"

CROWN_DIR="ontology/ws2-planning-blackboard"
[ -d "$CROWN_DIR" ] || refuse CROWN_DIRECTORY_MISSING "$CROWN_DIR"

mapfile -t crown_files < <(
  find "$CROWN_DIR" -maxdepth 1 -type f -name 'WS2-BB-*.ttl' -print | sort
)
[ "${#crown_files[@]}" -eq "$EXPECTED_COUNT" ] ||
  refuse CROWN_CARDINALITY "expected=$EXPECTED_COUNT observed=${#crown_files[@]}"

for n in $(seq 101 150); do
  matches="$(find "$CROWN_DIR" -maxdepth 1 -type f -name "WS2-BB-${n}-*.ttl" -print | wc -l | tr -d ' ')"
  [ "$matches" -eq 1 ] ||
    refuse CROWN_IDENTITY "WS2-BB-$n observed=$matches"
done

grep -Fq 'def authority_ceiling, do: :select' lib/beam4pm_dfcm.ex ||
  refuse AUTHORITY_CEILING_DRIFT "BeamPM.Dfcm must remain SELECT-only"

grep -Fq ':construct_contingent_policy' lib/beam4pm_dfcm.ex ||
  refuse DFCM_PHASE_DRIFT "contingent-policy phase missing"

grep -Fq 'scripts/gate_m2_check.sh' CLAUDE.md ||
  refuse M2_DOCTRINE_MISSING "repository doctrine no longer names deterministic reprojection"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
bash scripts/gate_m2_check.sh
M2_RC=$?
set -e
ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[ "$M2_RC" -eq 0 ] || refuse M2_FAILED "exit=$M2_RC target=$TARGET_SHA"

[ "$(git rev-parse HEAD)" = "$TARGET_SHA" ] ||
  refuse SUBJECT_MOVED "before=$TARGET_SHA after=$(git rev-parse HEAD)"

git diff --quiet || refuse M2_LEFT_DRIFT "unstaged changes remain after deterministic reprojection"
git diff --cached --quiet || refuse M2_LEFT_INDEX_DRIFT "staged changes remain after deterministic reprojection"
[ -z "$(git ls-files --others --exclude-standard)" ] ||
  refuse M2_LEFT_UNTRACKED "untracked files remain after deterministic reprojection"

python3 - "$TARGET_SHA" "$MAIN_REF" "$EXPECTED_COUNT" "$STARTED_AT" "$ENDED_AT" <<'PY'
import json
import sys

subject, main_ref, expected_count, started_at, ended_at = sys.argv[1:]
print(json.dumps({
    "receipt_type": "WS2_DFCM_SCHEDULED_RECOVERY",
    "subject_sha": subject,
    "main_ref": main_ref,
    "containment": "VERIFIED_ANCESTOR",
    "ws2_bb_contract_count": int(expected_count),
    "dfcm_authority_ceiling": "SELECT",
    "verification": {
        "court": "scripts/gate_m2_check.sh",
        "exit": 0,
        "deterministic_reprojection": "VERIFIED",
        "worktree_after": "CLEAN",
    },
    "changed_repository_state": False,
    "authority": "OBSERVE_VERIFY_ONLY",
    "standing": "ALIVE[WS2_DFCM_EXACT_SUBJECT_RECOVERY]",
    "started_at": started_at,
    "ended_at": ended_at,
    "falsifiers": [
        "subject is not exact HEAD",
        "subject is not contained in origin/main",
        "WS2-BB-101..150 is incomplete or duplicated",
        "BeamPM.Dfcm authority exceeds SELECT",
        "deterministic reprojection fails",
        "verification leaves repository drift",
    ],
}, sort_keys=True))
PY
