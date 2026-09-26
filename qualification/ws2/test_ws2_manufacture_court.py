"""Chicago-style court tests for qualification/ws2/ws2_manufacture_court.py.

Real collaborators only: every case copies the real WS2-PLAN-051..100 Turtle
fragments into a temporary repository root, applies one concrete adversarial
mutation to real files on disk, runs the court as a real subprocess, and
asserts on its exit status, its typed refusal line and the identity files it
writes. No test doubles are used anywhere in this module.

Run: python3 -m unittest discover -s qualification/ws2 -p 'test_*.py' -v
"""

from __future__ import annotations

import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
COURT = HERE / "ws2_manufacture_court.py"
FRAGMENTS = REPO / "ontology" / "ws2-autonomic-planning"
# The court runs inside the manufacture workspace, whose consequence is
# `git add -A`; bytecode caches must never enter that patch.
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import blake3_digest  # noqa: E402

GGEN_BPM = "https://ggen.dev/ontology/beam-process-model#"
STALE_BPM = "https://beam4pm.dev/ontology/process#"


def run_court(*args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(COURT), *args],
        capture_output=True,
        text=True,
        env={**os.environ, **(env or {})},
        timeout=600,
    )


class SemanticCourt(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="ws2-court-"))
        self.frag = self.tmp / "ontology" / "ws2-autonomic-planning"
        self.frag.mkdir(parents=True)
        for src in sorted(FRAGMENTS.glob("*.ttl")):
            if 51 <= int(src.name[:3]) <= 100:
                shutil.copy2(src, self.frag / src.name)
        (self.tmp / "ontology.ttl").write_text(f"@prefix bpm: <{GGEN_BPM}> .\n")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    def file(self, number: int) -> Path:
        (match,) = self.frag.glob(f"{number:03d}-*.ttl")
        return match

    def semantic(self, *extra: str) -> subprocess.CompletedProcess:
        return run_court("semantic", "--root", str(self.tmp), *extra)

    def assertRefused(self, proc: subprocess.CompletedProcess, code: str, status: int = 2) -> None:
        self.assertEqual(proc.returncode, status, proc.stderr + proc.stdout)
        self.assertIn(f"[{code}]", proc.stderr)
        self.assertNotIn("ALIVE", proc.stdout)

    def test_real_fifty_contracts_are_admitted(self) -> None:
        proc = self.semantic()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        verdict = json.loads(proc.stdout.splitlines()[1])
        self.assertEqual(verdict["verdict"], "ALIVE[WS2_SEMANTIC_PROJECTION_50]")
        self.assertEqual(verdict["contracts"], 50)
        self.assertGreater(verdict["d_semantic_min"], verdict["epsilon"])

    def test_stale_namespace_that_ggen_cannot_select_is_refused(self) -> None:
        # Regression guard for 23769be5: bpm bound to a namespace the
        # beam4pm-process-model-pack SPARQL never selects -> zero projection.
        path = self.file(77)
        path.write_text(path.read_text().replace(GGEN_BPM, STALE_BPM))
        self.assertRefused(self.semantic(), "WS2_NAMESPACE_NOT_PROJECTABLE")

    def test_every_repository_fragment_binds_the_projectable_namespace(self) -> None:
        for number in range(51, 101):
            text = self.file(number).read_text()
            self.assertIn(f"@prefix bpm: <{GGEN_BPM}> .", text, number)
            self.assertNotIn(STALE_BPM, text, number)

    def test_missing_contract_breaks_census(self) -> None:
        self.file(64).unlink()
        self.assertRefused(self.semantic(), "WS2_SEMANTIC_CENSUS")

    def test_extra_contract_breaks_census(self) -> None:
        extra = self.frag / "099-shadow_copy.ttl"
        extra.write_text(self.file(99).read_text())
        self.assertRefused(self.semantic(), "WS2_SEMANTIC_CENSUS")

    def test_renumbered_contract_leaves_gap(self) -> None:
        src = self.file(75)
        src.rename(self.frag / src.name.replace("075-", "074-"))
        self.assertRefused(self.semantic(), "WS2_SEMANTIC_CENSUS_GAP")

    def test_duplicate_record_name_across_files_is_refused(self) -> None:
        left = self.file(52)
        name = left.name[4:-4]
        victim = self.file(53)
        victim.unlink()
        (self.frag / f"053-{name}.ttl").write_text(left.read_text())
        self.assertRefused(self.semantic(), "WS2_RECORD_NAME_COLLISION")

    def test_two_record_names_in_one_file_is_refused(self) -> None:
        path = self.file(60)
        path.write_text(path.read_text() + '\nb4p:x a bpm:Thing ; bpm:recordName "ghost_record" .\n')
        self.assertRefused(self.semantic(), "WS2_RECORD_IDENTITY")

    def test_optional_field_is_refused(self) -> None:
        path = self.file(61)
        text = path.read_text()
        path.write_text(text.replace('bpm:fieldRequired "true"', 'bpm:fieldRequired "false"', 1))
        self.assertRefused(self.semantic(), "WS2_REQUIRED_FIELD_COUNT")

    def test_do_surface_in_documentation_is_refused(self) -> None:
        path = self.file(62)
        text = path.read_text()
        path.write_text(text.replace('bpm:recordDoc "', 'bpm:recordDoc "Planner may execute this. ', 1))
        self.assertRefused(self.semantic(), "WS2_DO_SURFACE")

    def test_erlang_reserved_field_name_is_refused(self) -> None:
        path = self.file(63)
        text = path.read_text()
        first = text.split('bpm:fieldName "', 1)[1].split('"', 1)[0]
        path.write_text(text.replace(f'bpm:fieldName "{first}"', 'bpm:fieldName "receive"', 1))
        self.assertRefused(self.semantic(), "WS2_FIELD_NAME_NOT_ERLANG_ATOM")

    def test_identical_field_roles_are_semantic_fragmentation(self) -> None:
        import re

        donor = re.findall(r'bpm:fieldName "([^"]+)"', self.file(51).read_text())
        path = self.file(90)
        text = path.read_text()
        own = re.findall(r'bpm:fieldName "([^"]+)"', text)
        for old, new in zip(own, donor):
            text = text.replace(f'bpm:fieldName "{old}"', f'bpm:fieldName "{new}"')
        path.write_text(text)
        self.assertRefused(self.semantic(), "WS2_SEMANTIC_FRAGMENTATION")

    def test_name_already_owned_by_root_ontology_is_refused(self) -> None:
        name = self.file(56).name[4:-4]
        root = self.tmp / "ontology.ttl"
        root.write_text(root.read_text() + f'bpm:clash_rt a bpm:RecordType ; bpm:recordName "{name}" .\n')
        self.assertRefused(self.semantic(), "WS2_RECORD_NAME_COLLISION_EXTERNAL")

    def test_composed_tail_of_root_ontology_is_not_an_owner(self) -> None:
        # Inside the manufacture job ontology.ttl already carries every
        # fragment after the composition marker; that must not self-collide.
        root = self.tmp / "ontology.ttl"
        tail = "".join(
            f"\n\n# ---- composed canonical fragment: {p} ----\n{p.read_text()}"
            for p in sorted(self.frag.glob("*.ttl"))
        )
        root.write_text(root.read_text() + tail)
        self.assertEqual(self.semantic().returncode, 0)

    def test_filename_that_names_a_different_record_is_refused(self) -> None:
        path = self.file(58)
        path.rename(self.frag / "058-not_the_record_inside.ttl")
        self.assertRefused(self.semantic(), "WS2_FILENAME_IDENTITY_MISMATCH")

    def test_court_leaves_no_bytecode_in_the_manufacture_workspace(self) -> None:
        # The manufacture job diffs `git add -A`; a __pycache__ written by the
        # court leaked into ggen-sync.patch during the host replay of 553ad4a7.
        court_dir = self.tmp / "qualification" / "ws2"
        court_dir.mkdir(parents=True)
        for name in ("ws2_manufacture_court.py", "blake3_digest.py"):
            shutil.copy2(HERE / name, court_dir / name)
        env = {k: v for k, v in os.environ.items() if k != "PYTHONDONTWRITEBYTECODE"}
        proc = subprocess.run(
            [
                sys.executable,
                str(court_dir / "ws2_manufacture_court.py"),
                "semantic",
                "--root",
                str(self.tmp),
            ],
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(sorted(p.name for p in court_dir.rglob("__pycache__")), [])

    def _projection(self, names: list[str], erlang_form: str, test_form: str) -> None:
        (self.tmp / "src").mkdir(exist_ok=True)
        (self.tmp / "test").mkdir(exist_ok=True)
        (self.tmp / "src/beam4pm_types.erl").write_text("".join(erlang_form.format(n=n) for n in names))
        (self.tmp / "test/beam4pm_types_test.exs").write_text("".join(test_form.format(n=n) for n in names))

    def names(self) -> list[str]:
        return [self.file(n).name[4:-4] for n in range(51, 101)]

    def test_substring_projection_is_not_a_projection(self) -> None:
        # The 23769be5 court used `name in erlang`; a longer identifier that
        # merely contains the record name satisfied it.
        self._projection(self.names(), "-record(x_{n}_y, {{}}).\n", 'name: "x_{n}_y",\n')
        self.assertRefused(self.semantic("--require-projection"), "WS2_ERLANG_PROJECTION_MISSING", 1)

    def test_missing_test_projection_is_build_broken(self) -> None:
        self._projection(self.names(), "-record({n}, {{}}).\n", 'name: "other_{n}",\n')
        self.assertRefused(self.semantic("--require-projection"), "WS2_TEST_PROJECTION_MISSING", 1)

    def test_exact_projection_is_admitted(self) -> None:
        self._projection(self.names(), "-record({n}, {{}}).\n", 'name: "{n}",\n')
        proc = self.semantic("--require-projection")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(json.loads(proc.stdout.splitlines()[1])["projection_checked"])


class ReceiptCourt(unittest.TestCase):
    PRIMARY = ["src/beam4pm_types.erl", "lib/beam4pm_types.ex"]
    SECONDARY = ["docs/FORTUNE5_CONTROL_MATRIX.md"]

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="ws2-receipt-"))
        self.evidence = self.tmp / "evidence"
        self.evidence.mkdir()
        (self.evidence / "primary-ggen-targets.txt").write_text("\n".join(self.PRIMARY) + "\n")
        (self.evidence / "secondary-ggen-targets.txt").write_text("\n".join(self.SECONDARY) + "\n")
        self.write("src/beam4pm_types.erl", "%% GENERATED by ggen. Do not edit.\n-module(beam4pm_types).\n")
        self.write(
            "lib/beam4pm_types.ex", "# GENERATED by ggen. Do not edit.\ndefmodule BeamPM.Types do\nend\n"
        )
        self.write("docs/FORTUNE5_CONTROL_MATRIX.md", "# Control matrix\n\nno marker here\n")
        self.graph_hash = "a" * 64

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    def write(self, rel: str, text: str) -> None:
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def receipt(
        self, outputs: dict | None = None, graph_hash: str | None = None, raw: str | None = None
    ) -> None:
        target = self.tmp / ".ggen-v2/receipt.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        if raw is not None:
            target.write_text(raw)
            return
        if outputs is None:
            outputs = {
                rel: blake3_digest.file_digest(self.tmp / rel) for rel in self.PRIMARY + self.SECONDARY
            }
        payload = {"graph_hash": graph_hash or self.graph_hash, "outputs": outputs}
        target.write_text(json.dumps({"record": {}, "payload": payload}))

    def first(self) -> subprocess.CompletedProcess:
        return run_court("receipt-first", "--root", str(self.tmp), "--evidence", str(self.evidence))

    def second(self) -> subprocess.CompletedProcess:
        return run_court("receipt-second", "--root", str(self.tmp), "--evidence", str(self.evidence))

    def assertRefused(self, proc: subprocess.CompletedProcess, code: str) -> None:
        self.assertEqual(proc.returncode, 2, proc.stderr + proc.stdout)
        self.assertIn(f"REFUSED[{code}]", proc.stderr)

    def test_first_and_second_sync_identity_is_admitted(self) -> None:
        self.receipt()
        first = self.first()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("ALIVE[FIRST_SYNC_RECEIPT_OWNERSHIP]", first.stdout)
        second = self.second()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(
            (self.evidence / "first-sync-identity.json").read_bytes(),
            (self.evidence / "second-sync-identity.json").read_bytes(),
        )

    def test_sha256_digest_is_the_wrong_digest(self) -> None:
        # Regression guard for 23769be5: its court compared ggen's BLAKE3
        # output digests against SHA-256 and refused every honest receipt.
        import hashlib

        outputs = {
            rel: hashlib.sha256((self.tmp / rel).read_bytes()).hexdigest()
            for rel in self.PRIMARY + self.SECONDARY
        }
        self.receipt(outputs)
        self.assertRefused(self.first(), "RECEIPT_DIGEST_MISMATCH")

    def test_tampered_output_is_refused(self) -> None:
        self.receipt()
        self.write("lib/beam4pm_types.ex", "# GENERATED by ggen. Do not edit.\ndefmodule Evil do\nend\n")
        self.assertRefused(self.first(), "RECEIPT_DIGEST_MISMATCH")

    def test_output_outside_census_is_refused(self) -> None:
        self.write("lib/rogue.ex", "# GENERATED by ggen\n")
        outputs = {rel: blake3_digest.file_digest(self.tmp / rel) for rel in self.PRIMARY + ["lib/rogue.ex"]}
        self.receipt(outputs)
        self.assertRefused(self.first(), "OUTPUT_OUTSIDE_OWNERSHIP_CENSUS")

    def test_unmarked_primary_output_is_refused(self) -> None:
        self.write("src/beam4pm_types.erl", "-module(beam4pm_types).\n")
        self.receipt()
        self.assertRefused(self.first(), "OUTPUT_OWNERSHIP_UNMARKED")

    def test_unmarked_secondary_output_is_owned_by_receipt(self) -> None:
        self.receipt()
        self.assertEqual(self.first().returncode, 0)

    def test_receipted_output_missing_on_disk_is_refused(self) -> None:
        self.receipt()
        (self.tmp / "lib/beam4pm_types.ex").unlink()
        self.assertRefused(self.first(), "RECEIPTED_OUTPUT_MISSING")

    def test_absent_receipt_is_refused(self) -> None:
        self.assertRefused(self.first(), "MISSING_GGEN_RECEIPT")

    def test_malformed_receipt_json_is_refused(self) -> None:
        self.receipt(raw="{not json")
        self.assertRefused(self.first(), "GGEN_RECEIPT_MALFORMED")

    def test_non_hex_graph_hash_is_refused(self) -> None:
        self.receipt(graph_hash="unknown")
        self.assertRefused(self.first(), "GGEN_RECEIPT_GRAPH_HASH_MALFORMED")

    def test_path_escape_in_receipt_is_refused(self) -> None:
        self.receipt({"../outside.txt": "b" * 64})
        self.assertRefused(self.first(), "GGEN_RECEIPT_PATH_ESCAPE")

    def test_second_sync_on_different_graph_is_replay_mismatch(self) -> None:
        self.receipt()
        self.assertEqual(self.first().returncode, 0)
        self.receipt(graph_hash="c" * 64)
        self.assertRefused(self.second(), "SECOND_SYNC_GRAPH_IDENTITY_MISMATCH")

    def test_second_sync_byte_drift_outside_second_receipt_is_refused(self) -> None:
        self.receipt()
        self.assertEqual(self.first().returncode, 0)
        self.write("lib/beam4pm_types.ex", "# GENERATED by ggen. Do not edit.\ndefmodule Drift do\nend\n")
        only = {"src/beam4pm_types.erl": blake3_digest.file_digest(self.tmp / "src/beam4pm_types.erl")}
        self.receipt(only)
        self.assertRefused(self.second(), "SECOND_SYNC_BYTE_DRIFT")

    def test_second_without_first_identity_is_refused(self) -> None:
        self.receipt()
        self.assertRefused(self.second(), "FIRST_SYNC_IDENTITY_ABSENT")

    def test_receipt_key_reordering_does_not_change_identity(self) -> None:
        self.receipt()
        self.assertEqual(self.first().returncode, 0)
        baseline = (self.evidence / "first-sync-identity.json").read_bytes()
        forward = {rel: blake3_digest.file_digest(self.tmp / rel) for rel in self.PRIMARY + self.SECONDARY}
        self.receipt(dict(reversed(list(forward.items()))))
        self.assertEqual(self.first().returncode, 0)
        self.assertEqual((self.evidence / "first-sync-identity.json").read_bytes(), baseline)

    def test_duplicate_delivery_of_first_verdict_is_idempotent(self) -> None:
        self.receipt()
        runs = [self.first() for _ in range(2)]
        self.assertEqual([r.returncode for r in runs], [0, 0])
        self.assertEqual(runs[0].stdout, runs[1].stdout)


class Blake3Digest(unittest.TestCase):
    def test_empty_input_matches_spec_vector(self) -> None:
        self.assertEqual(
            blake3_digest.pure_python(b""),
            "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
        )

    def test_pure_python_matches_every_available_backend_across_tree_boundaries(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="ws2-b3-"))
        try:
            available = [b for b in blake3_digest.BACKENDS if b != "pure-python"]
            available = [
                b
                for b in available
                if (b == "b3sum" and shutil.which("b3sum"))
                or (b == "python-blake3" and _has_module("blake3"))
            ]
            if not available:
                self.skipTest("no independent BLAKE3 backend on this host (b3sum / blake3 module absent)")
            for size in (0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 3073, 8193, 65537):
                path = tmp / f"blob-{size}"
                path.write_bytes(bytes((i * 131 + 7) % 256 for i in range(size)))
                reference = blake3_digest.file_digest(path, force="pure-python")
                for other in available:
                    self.assertEqual(blake3_digest.file_digest(path, force=other), reference, (size, other))
        finally:
            shutil.rmtree(tmp)

    def test_unknown_backend_pin_is_refused(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-c", "import blake3_digest; blake3_digest.backend()"],
            cwd=HERE,
            capture_output=True,
            text=True,
            env={**os.environ, "WS2_BLAKE3_BACKEND": "md5"},
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("WS2_BLAKE3_BACKEND", proc.stderr)


class RegressionBound(unittest.TestCase):
    """Committed bounds from qualification/ws2/bench-receipt-ws2-court.json."""

    RECEIPT = HERE / "bench-receipt-ws2-court.json"

    def test_semantic_court_on_real_fifty_stays_within_bound(self) -> None:
        bound = json.loads(self.RECEIPT.read_text())["regression_bounds"]["semantic_court_real50_median_s"]
        samples = []
        for _ in range(3):
            start = time.perf_counter()
            proc = run_court("semantic", "--root", str(REPO))
            samples.append(time.perf_counter() - start)
            self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertLess(statistics.median(samples), bound)

    def test_pure_python_blake3_throughput_stays_within_bound(self) -> None:
        bound = json.loads(self.RECEIPT.read_text())["regression_bounds"]["pure_python_blake3_min_mib_per_s"]
        data = bytes(range(256)) * 1024  # 256 KiB
        start = time.perf_counter()
        blake3_digest.pure_python(data)
        mib_per_s = (len(data) / (1 << 20)) / (time.perf_counter() - start)
        self.assertGreater(mib_per_s, bound)


def _has_module(name: str) -> bool:
    try:
        __import__(name)
        return True
    except ImportError:
        return False


if __name__ == "__main__":
    unittest.main()
