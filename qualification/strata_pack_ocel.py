#!/usr/bin/env python3
"""Convert a ggen-marketplace qualification report into OCEL 2.0 events.

Corpus: the per-pack verdict records emitted by ggen-marketplace's
qualification court (``scripts/qualify_packs.py --report``; schema
``https://ggen.dev/marketplace/qualification/v1``). Each per-pack record
carries ``name`` / ``status`` (``ALIVE`` | ``REFUSED`` | ``SKIPPED`` |
``WARN``) and, for refusals, ``code`` (``REFUSED:<CLASS>:<detail>``).

Output: one OCEL event per pack verdict, emitted through beam4pm's
``BeamPM.CastleOcel`` vocabulary and wire shape:

  * event names come from the closed CASTLE vocabulary
    (``BeamPM.CastleOcel.event_names/0``): ALIVE -> ``evidence_admitted``,
    REFUSED -> ``refused_observation``, SKIPPED/WARN -> ``ggen_sync_observed``;
  * object types are CASTLE's: ``system`` / ``pod`` / ``container`` /
    ``gym_act_episode``;
  * per-event object bindings honor the vocabulary's per-event-type binding
    (``evidence_admitted`` binds ``gym_act_episode``;
    ``refused_observation`` binds ``system``; ``ggen_sync_observed`` binds
    ``container``);
  * every event carries the fixed CastleOcel attributes
    ``authority=none`` / ``provenance=observation_only`` plus the verdict
    attributes: ``pack``, ``standing``, ``refusal_class`` (refusals only),
    ``tool="ggen qualification"``, and the caller-supplied timestamp as
    ``event_time``.

Timestamps are caller-supplied, never sampled (CastleOcel determinism
convention); the converter reads no clock, so the same report converts to
byte-identical output every run.

Wire shape: the repo's existing OCEL 2.0 envelope
(``{"objectTypes", "eventTypes", "objects", "events"}`` with
``{event_id, event_type, event_time, attributes}`` event maps), decodable by
``BeamPM.Ocel.decode/1``. No second wire shape is introduced.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

REPORT_SCHEMA = "https://ggen.dev/marketplace/qualification/v1"
TOOL = "ggen qualification"

# BeamPM.CastleOcel closed event vocabulary (event_names/0).
CASTLE_EVENT_NAMES = frozenset(
    {
        "system_bootstrapped",
        "pod_provisioned",
        "container_started",
        "ggen_sync_observed",
        "activity_started",
        "activity_finished",
        "episode_recorded",
        "evidence_admitted",
        "episode_receipt_sealed",
        "refused_observation",
    }
)

# BeamPM.CastleOcel per-event-type object binding, restricted to the event
# names this converter may emit.
REQUIRED_OBJECTS = {
    "evidence_admitted": ("gym_act_episode",),
    "refused_observation": ("system",),
    "ggen_sync_observed": ("container",),
}

# Verdict standing -> CastleOcel event name. Total over the report's status
# domain (ALIVE / REFUSED / SKIPPED / WARN); an unknown status refuses.
STANDING_TO_EVENT = {
    "ALIVE": "evidence_admitted",
    "REFUSED": "refused_observation",
    "SKIPPED": "ggen_sync_observed",
    "WARN": "ggen_sync_observed",
}


def convert(report: dict[str, Any], timestamp: str) -> dict[str, Any]:
    """Report JSON -> OCEL 2.0 envelope dict (one event per pack verdict)."""
    if not isinstance(report, dict):
        raise ValueError("REFUSED:STRATA_REPORT_NOT_AN_OBJECT")
    if report.get("schema") != REPORT_SCHEMA:
        raise ValueError(f"REFUSED:STRATA_REPORT_SCHEMA:{report.get('schema')!r}")
    packs = report.get("packs")
    if not isinstance(packs, list):
        raise ValueError("REFUSED:STRATA_REPORT_PACKS_NOT_A_LIST")

    records = sorted(packs, key=lambda record: record["name"])
    if report.get("pack_count", len(records)) != len(records):
        raise ValueError("REFUSED:STRATA_REPORT_PACK_COUNT_MISMATCH")

    events: list[dict[str, Any]] = []
    objects: dict[tuple[str, str], dict[str, object]] = {}

    for index, record in enumerate(records, start=1):
        standing = record.get("status")
        event_name = STANDING_TO_EVENT.get(standing)
        if event_name is None:
            raise ValueError(f"REFUSED:STRATA_UNKNOWN_STANDING:{standing!r}")
        name = record["name"]

        refusal_class = None
        if standing == "REFUSED":
            refusal_class = record.get("code")
            if not isinstance(refusal_class, str) or not refusal_class:
                raise ValueError(f"REFUSED:STRATA_MISSING_REFUSAL_CODE:{name}")

        attrs: dict[str, Any] = {
            "authority": "none",
            "provenance": "observation_only",
            "pack": name,
            "standing": standing,
            "tool": TOOL,
        }
        if refusal_class is not None:
            attrs["refusal_class"] = refusal_class

        bindings = {}
        for object_type in REQUIRED_OBJECTS[event_name]:
            if object_type == "system":
                object_id = "ggen-qualification"
            elif object_type == "container":
                object_id = f"ggen-qualification:{name}"
            else:
                object_id = f"pack:{name}"
            bindings[object_type] = object_id
            objects[(object_type, object_id)] = {
                "object_id": object_id,
                "object_type": object_type,
                "attributes": {},
            }

        events.append(
            {
                "event_id": f"strata-{index:04d}-{event_name}",
                "event_type": event_name,
                "event_time": timestamp,
                "attributes": attrs,
            }
        )

    return {
        "objectTypes": [
            {"name": object_type, "attributes": []}
            for object_type in sorted({object_type for (object_type, _) in objects})
        ],
        "eventTypes": [
            {"name": event_name, "attributes": []}
            for event_name in sorted({event["event_type"] for event in events})
        ],
        "objects": [
            objects[key] for key in sorted(objects, key=lambda k: (k[0], k[1]))
        ],
        "events": events,
    }


def convert_bytes(report: dict[str, Any], timestamp: str) -> bytes:
    """Deterministic bytes: sorted keys, stable indent, trailing newline."""
    envelope = convert(report, timestamp)
    return (json.dumps(envelope, indent=2, sort_keys=True) + "\n").encode("utf-8")


def fixture_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert a ggen qualification report into CastleOcel-vocabulary OCEL events."
    )
    parser.add_argument("report", type=Path, help="qualification report JSON (qualification/v1 schema)")
    parser.add_argument(
        "--timestamp", required=True,
        help="caller-supplied event time (ISO-8601); never sampled from the clock",
    )
    parser.add_argument("-o", "--out", type=Path, default=None, help="output path (default stdout)")
    args = parser.parse_args(argv)

    try:
        report = json.loads(args.report.read_text(encoding="utf-8"))
        payload = convert_bytes(report, args.timestamp)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"REFUSED:STRATA_CONVERT_FAILED:{error}", file=sys.stderr)
        return 2

    if args.out is None:
        sys.stdout.buffer.write(payload)
    else:
        args.out.write_bytes(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
