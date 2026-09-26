#!/usr/bin/env python3
"""Deterministic timing benchmark for the WS2 manufacture court (hand-authored).

Measures, on real inputs:
  * semantic court over the real WS2-PLAN-051..100 fragments (subprocess,
    end-to-end, median of --runs);
  * semantic court over a synthetic census of N contracts built from the real
    fragments' shape (pairwise Jaccard is O(N^2), so this bounds growth);
  * pure-Python BLAKE3 throughput (the CI floor when no blake3 backend exists)
    and, when available, the native backend;
  * optionally receipt-first over a real post-sync tree (--post-sync-root with
    --evidence), i.e. the real 90-output ggen receipt.

Writes a JSON bench receipt (--out). Regression bounds in the committed
receipt are asserted by test_ws2_manufacture_court.RegressionBound.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
COURT = HERE / "ws2_manufacture_court.py"
sys.path.insert(0, str(HERE))
import blake3_digest  # noqa: E402

GGEN_BPM = "https://ggen.dev/ontology/beam-process-model#"


def timed(cmd: list[str], runs: int, env: dict | None = None) -> dict:
    samples = []
    for _ in range(runs):
        start = time.perf_counter()
        proc = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, **(env or {})})
        samples.append(time.perf_counter() - start)
        if proc.returncode != 0:
            raise SystemExit(f"BENCH_SUBJECT_FAILED:{cmd}:{proc.stderr.strip()}")
    return {
        "runs": runs,
        "median_s": round(statistics.median(samples), 6),
        "min_s": round(min(samples), 6),
        "max_s": round(max(samples), 6),
    }


def synthetic_root(n: int) -> Path:
    root = Path(tempfile.mkdtemp(prefix=f"ws2-bench-{n}-"))
    frag = root / "ontology" / "ws2-autonomic-planning"
    frag.mkdir(parents=True)
    (root / "ontology.ttl").write_text(f"@prefix bpm: <{GGEN_BPM}> .\n")
    for i in range(n):
        number = 51 + i
        name = f"bench_contract_{number:04d}"
        fields = [f"f{number}_a", f"f{number}_b", f"shared_{number % 7}"]
        body = [f"@prefix bpm: <{GGEN_BPM}> .", "@prefix b4p: <https://beam4pm.dev/ontology/instance#> .", ""]
        body.append(f"b4p:{name}_rt a bpm:RecordType ;")
        body.append(f'    bpm:recordName "{name}" ; bpm:recordDoc "Synthetic bench contract {number}." ;')
        body.append("    bpm:hasField " + ", ".join(f"b4p:{name}_{f}_f" for f in fields) + " .")
        for order, field in enumerate(fields, 1):
            body.append(
                f'b4p:{name}_{field}_f a bpm:Field ; bpm:fieldName "{field}" ; bpm:fieldType "string" ;'
                f' bpm:fieldDoc "Bench field." ; bpm:fieldRequired "true" ; bpm:fieldOrder {order} .'
            )
        (frag / f"{number:03d}-{name}.ttl").write_text("\n".join(body) + "\n")
    return root


def throughput(backend: str, size: int) -> float:
    tmp = Path(tempfile.mkdtemp(prefix="ws2-bench-b3-"))
    try:
        path = tmp / "blob"
        path.write_bytes(os.urandom(size))
        start = time.perf_counter()
        blake3_digest.file_digest(path, force=backend)
        return round((size / (1 << 20)) / (time.perf_counter() - start), 4)
    finally:
        shutil.rmtree(tmp)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--synthetic", type=int, nargs="*", default=[50, 200, 400])
    ap.add_argument("--post-sync-root", type=Path)
    ap.add_argument("--evidence", type=Path)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()

    result: dict = {
        "schema": "https://beam4pm.dev/receipts/ws2-court-bench/v1",
        "authority": "NONE",
        "host": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "machine": platform.machine(),
        },
        "semantic_court_real50": timed(
            [sys.executable, str(COURT), "semantic", "--root", str(REPO)], args.runs
        ),
        "semantic_court_synthetic": {},
        "blake3_mib_per_s": {"pure-python": throughput("pure-python", 1 << 20)},
    }
    for n in args.synthetic:
        root = synthetic_root(n)
        try:
            result["semantic_court_synthetic"][str(n)] = timed(
                [
                    sys.executable,
                    str(COURT),
                    "semantic",
                    "--root",
                    str(root),
                    "--first",
                    "51",
                    "--last",
                    str(50 + n),
                ],
                args.runs,
            )
        finally:
            shutil.rmtree(root)
    for backend in ("python-blake3", "b3sum"):
        try:
            result["blake3_mib_per_s"][backend] = throughput(backend, 8 << 20)
        except (ImportError, FileNotFoundError, subprocess.CalledProcessError):
            result["blake3_mib_per_s"][backend] = None
    if args.post_sync_root and args.evidence:
        for backend in ("pure-python", blake3_digest.backend()):
            result[f"receipt_first_real_{backend}"] = timed(
                [
                    sys.executable,
                    str(COURT),
                    "receipt-first",
                    "--root",
                    str(args.post_sync_root),
                    "--evidence",
                    str(args.evidence),
                ],
                1 if backend == "pure-python" else args.runs,
                env={"WS2_BLAKE3_BACKEND": backend},
            )
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.write_text(text)
    print(text, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
