#!/usr/bin/env bash
set -euo pipefail

WEAVER_VERSION="0.26.1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${ROOT}/qualification/weaver/gall004/registry"
INVALID="${ROOT}/qualification/weaver/gall004/invalid.txt"
STATE_DIR="${GALL004_WEAVER_STATE_DIR:-$(mktemp -d)}"
OTLP_PORT="${GALL004_WEAVER_OTLP_PORT:-14317}"
ADMIN_PORT="${GALL004_WEAVER_ADMIN_PORT:-14320}"
REPORT="${STATE_DIR}/live-check-report.json"
LOG="${STATE_DIR}/live-check.log"
RECEIPT="${STATE_DIR}/weaver-court-receipt.json"

cleanup() {
  if [[ -n "${LIVE_PID:-}" ]] && kill -0 "${LIVE_PID}" 2>/dev/null; then
    kill "${LIVE_PID}" 2>/dev/null || true
    wait "${LIVE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

command -v weaver >/dev/null || {
  echo "BLOCKED: weaver v${WEAVER_VERSION} is required on PATH" >&2
  exit 78
}
command -v curl >/dev/null || {
  echo "BLOCKED: curl is required for Weaver admin health/stop" >&2
  exit 78
}
command -v python3 >/dev/null || {
  echo "BLOCKED: python3 is required to verify the Weaver JSON report" >&2
  exit 78
}

ACTUAL_VERSION="$(weaver --version 2>&1 || true)"
case "${ACTUAL_VERSION}" in
  *"${WEAVER_VERSION}"*) ;;
  *)
    echo "REFUSED: exact Weaver v${WEAVER_VERSION} required, observed: ${ACTUAL_VERSION}" >&2
    exit 65
    ;;
esac

mkdir -p "${STATE_DIR}"

# Court 1: the qualification registry itself must resolve under the exact Weaver.
weaver registry check --registry "${REGISTRY}" --v2

# Court 2: real OTLP/gRPC round trip. Weaver's emit command uses the standard
# OTel SDK; the endpoint env sends it to this exact live-check listener.
weaver registry live-check   --registry "${REGISTRY}"   --v2   --format json   --output=http   --otlp-grpc-address 127.0.0.1   --otlp-grpc-port "${OTLP_PORT}"   --admin-port "${ADMIN_PORT}"   --inactivity-timeout 60   --fail-on violation   >"${LOG}" 2>&1 &
LIVE_PID=$!

ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${ADMIN_PORT}/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "${LIVE_PID}" 2>/dev/null; then
    cat "${LOG}" >&2 || true
    echo "BUILD_BROKEN: Weaver live-check exited before health became ready" >&2
    exit 1
  fi
  sleep 1
done
[[ "${ready}" == 1 ]] || {
  cat "${LOG}" >&2 || true
  echo "BLOCKED: Weaver live-check health endpoint did not become ready" >&2
  exit 78
}

OTEL_EXPORTER_OTLP_ENDPOINT="http://127.0.0.1:${OTLP_PORT}"   weaver registry emit --registry "${REGISTRY}" --v2 --skip-policies

curl -fsS -X POST "http://127.0.0.1:${ADMIN_PORT}/stop" -o "${REPORT}"
wait "${LIVE_PID}"
LIVE_PID=""

python3 - "${REPORT}" <<'PY'
import json, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))

def values(node, key):
    if isinstance(node, dict):
        if key in node:
            yield node[key]
        for value in node.values():
            yield from values(value, key)
    elif isinstance(node, list):
        for value in node:
            yield from values(value, key)

totals = [value for value in values(data, "total_entities") if isinstance(value, int)]
if not totals or max(totals) <= 0:
    raise SystemExit("Weaver report did not prove any telemetry entities were observed")

violations = []
for counts in values(data, "advice_level_counts"):
    if isinstance(counts, dict):
        value = counts.get("violation", 0)
        if isinstance(value, int):
            violations.append(value)
if violations and max(violations) != 0:
    raise SystemExit(f"Weaver semantic court reported violations: {violations}")
PY

# Court 3: undeclared authority material must not pass the semantic court.
set +e
weaver registry live-check   --registry "${REGISTRY}"   --v2   --input-source "${INVALID}"   --input-format text   --format json   --no-stream   --fail-on violation   >"${STATE_DIR}/negative.json" 2>"${STATE_DIR}/negative.err"
NEGATIVE_EXIT=$?
set -e
if [[ "${NEGATIVE_EXIT}" -eq 0 ]]; then
  echo "BUILD_BROKEN: undeclared authority token attribute was accepted" >&2
  exit 1
fi

python3 - "${ROOT}" "${REPORT}" "${RECEIPT}" "${ACTUAL_VERSION}" <<'PY'
import hashlib, json, os, sys
root, report_path, out_path, version = sys.argv[1:]

def sha(path):
    with open(path, "rb") as handle:
        return "sha256:" + hashlib.sha256(handle.read()).hexdigest()

receipt = {
    "schema": "beam4pm.gall.weaver-court/v26.9.18",
    "standing": "PARTIAL_ALIVE",
    "authority": "none",
    "weaver_version": version.strip(),
    "registry_manifest_digest": sha(os.path.join(root, "qualification/weaver/gall004/registry/manifest.yaml")),
    "registry_definition_digest": sha(os.path.join(root, "qualification/weaver/gall004/registry/gall004.yaml")),
    "live_check_report_digest": sha(report_path),
    "otlp_round_trip": True,
    "negative_unknown_authority_attribute_refused": True,
    "evidence_ceiling": "qualification-registry; generated runtime semconv projection and independent postcondition remain separate courts",
}
encoded = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()
receipt["receipt_digest"] = "sha256:" + hashlib.sha256(encoded).hexdigest()
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(receipt, handle, indent=2, sort_keys=True)
    handle.write("\n")
print(json.dumps(receipt, sort_keys=True))
PY

echo "GALL-004 Weaver court receipt: ${RECEIPT}"
