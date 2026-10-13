#!/usr/bin/env python3
"""Court: strata-pack qualification -> CastleOcel-vocabulary OCEL conversion.

Chicago-school: the converter really runs over the pinned REAL qualification
report captured from ggen-marketplace's qualification court
(``scripts/qualify_packs.py --report`` at ggen 26.10.11, /tmp at
capture time, pinned below by sha256). No mocks, no synthesized fixture.
"""

import hashlib
import importlib.util
import json
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures" / "strata-qualification.json"
FIXTURE_SHA256 = "4b12771ac8872070f90a9b49b5aa7eab265e218278a3295abd4ddc6a5732287c"
TIMESTAMP = "2026-10-13T00:00:00Z"

_spec = importlib.util.spec_from_file_location("strata_pack_ocel", HERE / "strata_pack_ocel.py")
strata_pack_ocel = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_spec.name and strata_pack_ocel)

CASTLE_EVENT_NAMES = {
    "system_bootstrapped", "pod_provisioned", "container_started",
    "ggen_sync_observed", "activity_started", "activity_finished",
    "episode_recorded", "evidence_admitted", "episode_receipt_sealed",
    "refused_observation",
}
REQUIRED_OBJECTS = {
    "evidence_admitted": {"gym_act_episode"},
    "refused_observation": {"system"},
    "ggen_sync_observed": {"container"},
}


@pytest.fixture(scope="module")
def report():
    raw = FIXTURE.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == FIXTURE_SHA256, "pinned fixture drifted"
    return json.loads(raw)


@pytest.fixture(scope="module")
def envelope(report):
    return json.loads(strata_pack_ocel.convert_bytes(report, TIMESTAMP).decode("utf-8"))


def test_fixture_is_a_real_qualification_v1_report(report):
    assert report["schema"] == "https://ggen.dev/marketplace/qualification/v1"
    assert report["ggen"] == "ggen 26.10.11"
    assert report["pack_count"] == len(report["packs"]) == 7


def test_event_count_equals_pack_count(envelope, report):
    assert len(envelope["events"]) == report["pack_count"] == 7


def test_standing_values_map_one_to_one(envelope, report):
    by_pack = {e["attributes"]["pack"]: e for e in envelope["events"]}
    assert {e["attributes"]["standing"] for e in envelope["events"]} == set(
        r["status"] for r in report["packs"]
    )
    for record in report["packs"]:
        event = by_pack[record["name"]]
        assert event["attributes"]["standing"] == record["status"]
        assert event["event_type"] == strata_pack_ocel.STANDING_TO_EVENT[record["status"]]


def test_refusal_class_carried_through(envelope, report):
    by_pack = {e["attributes"]["pack"]: e for e in envelope["events"]}
    for record in report["packs"]:
        if record["status"] != "REFUSED":
            continue
        attrs = by_pack[record["name"]]["attributes"]
        assert attrs["refusal_class"] == record["code"]
        assert attrs["refusal_class"].startswith("REFUSED:")
    assert any("refusal_class" in e["attributes"] for e in envelope["events"])


def test_events_use_castle_ocel_vocabulary_and_bindings(envelope):
    for event in envelope["events"]:
        assert event["event_type"] in CASTLE_EVENT_NAMES
        assert event["attributes"]["authority"] == "none"
        assert event["attributes"]["provenance"] == "observation_only"
        assert event["attributes"]["tool"] == "ggen qualification"
        assert event["event_time"] == TIMESTAMP
    # each emitted event type carries exactly its CastleOcel object binding
    bound = {e["event_type"]: REQUIRED_OBJECTS[e["event_type"]] for e in envelope["events"]}
    for event_type, object_types in bound.items():
        assert object_types <= {"system", "pod", "container", "gym_act_episode"}


def test_determinism_identical_bytes_on_rerun(report):
    first = strata_pack_ocel.convert_bytes(report, TIMESTAMP)
    second = strata_pack_ocel.convert_bytes(report, TIMESTAMP)
    assert first == second


def test_cli_roundtrip_real_file(tmp_path):
    out = tmp_path / "ocel.json"
    import subprocess, sys

    proc = subprocess.run(
        [sys.executable, str(HERE / "strata_pack_ocel.py"), str(FIXTURE),
         "--timestamp", TIMESTAMP, "-o", str(out)],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0, proc.stderr
    first = out.read_bytes()
    proc = subprocess.run(
        [sys.executable, str(HERE / "strata_pack_ocel.py"), str(FIXTURE),
         "--timestamp", TIMESTAMP, "-o", str(out)],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0
    assert out.read_bytes() == first  # drift court: identical bytes


def test_unknown_standing_refuses():
    with pytest.raises(ValueError, match="REFUSED:STRATA_UNKNOWN_STANDING"):
        strata_pack_ocel.convert({"schema": strata_pack_ocel.REPORT_SCHEMA,
                                  "pack_count": 1, "packs": [{"name": "x", "status": "MAYBE"}]},
                                 TIMESTAMP)


def test_wrong_schema_refuses():
    with pytest.raises(ValueError, match="REFUSED:STRATA_REPORT_SCHEMA"):
        strata_pack_ocel.convert({"schema": "https://example.invalid/v9", "packs": []}, TIMESTAMP)
