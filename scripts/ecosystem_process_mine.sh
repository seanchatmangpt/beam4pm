#!/usr/bin/env bash
# ecosystem_process_mine.sh -- fetch the REAL manufacturing event log of the
# ggen-ecosystem rail (this repo's own GitHub Actions runs of the
# "beam4pm Manufacture (ggen-ecosystem rail)" workflow), then mine it with
# beam4pm's own generated process-mining suite.
#
# This is the point of beam4pm: the process-intelligence suite FOR the
# ggen-marketplace/ggen-ecosystem container. The container's manufacture rail
# is itself a process; its CI runs are its event log; beam4pm's generated
# BeamPM.Discovery/Precision are the miner. No synthetic fixtures anywhere --
# every event below is a real, timestamped step of a real hosted run.
#
# Usage (from the repo root; needs gh auth + mix deps compiled):
#   bash scripts/ecosystem_process_mine.sh
#
# Stage 1 (this script): gh api -> tmp/ecosystem-mine/rail-events.json
#   one JSON object per executed step of every run of the rail workflow:
#   {case_id, activity, time, run_conclusion, step_conclusion, job}
# Stage 2 (mix run scripts/ecosystem_process_mine.exs): OcelEvent admission
#   through the real validating constructors, traces_from_events,
#   dfg_from_traces, variants_from_traces, per-trace conformance (fitness +
#   real ETC precision) against the mined green-path model, and hard
#   assertions on the rail's lifecycle edges. Exits nonzero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-seanchatmangpt/beam4pm}"
WORKFLOW="${WORKFLOW:-beam4pm Manufacture (ggen-ecosystem rail)}"
OUT_DIR="tmp/ecosystem-mine"
mkdir -p "$OUT_DIR"

echo "== stage 1: fetching real rail runs from $REPO =="
runs_json="$OUT_DIR/rail-runs.json"
gh api "repos/$REPO/actions/runs?per_page=50" \
  --jq "[.workflow_runs[] | select(.name == \"$WORKFLOW\") | {id, conclusion, head_sha, run_started_at}]" \
  > "$runs_json"
run_count=$(python3 -c "import json;print(len(json.load(open('$runs_json'))))")
[ "$run_count" -gt 0 ] || { echo "REFUSED: zero rail runs found for '$WORKFLOW'" >&2; exit 2; }
echo "   $run_count real rail run(s)"

events_json="$OUT_DIR/rail-events.json"
python3 - "$runs_json" "$events_json" "$REPO" <<'PY'
import json, subprocess, sys

runs_path, events_path, repo = sys.argv[1:4]
runs = json.load(open(runs_path))
events = []
for run in runs:
    jobs = json.loads(subprocess.run(
        ["gh", "api", f"repos/{repo}/actions/runs/{run['id']}/jobs"],
        check=True, capture_output=True, text=True).stdout)["jobs"]
    for job in jobs:
        for step in job.get("steps", []):
            # only steps that actually executed carry a real timestamp
            if not step.get("started_at") or step.get("conclusion") == "skipped":
                continue
            events.append({
                "case_id": str(run["id"]),
                "activity": step["name"],
                "time": step["started_at"],
                # GitHub step timestamps are second-granular; several steps of
                # one job start in the same second, so started_at alone cannot
                # order a trace. step.number is the job's authoritative order.
                "number": step["number"],
                "run_conclusion": run["conclusion"] or "in_progress",
                "step_conclusion": step["conclusion"] or "unknown",
                "job": job["name"],
            })
json.dump(events, open(events_path, "w"), indent=2)
print(f"   {len(events)} real step events across {len(runs)} run(s)")
PY

echo "== stage 2: mining with beam4pm's generated discovery suite =="
mix run scripts/ecosystem_process_mine.exs
