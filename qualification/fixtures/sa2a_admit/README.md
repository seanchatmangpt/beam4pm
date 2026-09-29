# sa2a admit parity candidate fixtures (b4p-p4)

Candidate assertions cross-validated through the autofde-lab §64 admission
court (`autofde sa2a admit`) and beam4pm's `BeamPM.DeviationAdmission`
(`admit_deviation/4`). Positive controls are real admitted facts copied from
the repo's `ontology.ttl` (read-only source; samples copied here). Negative
controls are deliberately forged variants. Provenance and observed verdicts:
`WAVE-RECEIPT.md` at the worktree root.

Files:
- `positive_c1_ocel_event_rt.assertion` — real `bpm:ocel_event_rt` RecordType fact (ontology.ttl line 24).
- `positive_c2_conformance_result_rt.assertion` — real `bpm:conformance_result_rt` RecordType fact (ontology.ttl line 489).
- `negative_c3_unknown_type.assertion` — forged: subject class admitted nowhere.
- `negative_c4_dangling_ref.assertion` — forged: real subject, field ref admitted nowhere.
- `negative_c5_empty.assertion` — forged: empty assertion.
- `negative_c6_no_provenance.assertion` — real fact text, but submitted with empty evidence payload (missing admission provenance).
- `negative_c7_error_evidence.assertion` — real fact text, but evidence payload reports its own discovery failure.
