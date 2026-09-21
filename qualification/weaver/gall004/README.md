# GALL-004 Weaver qualification fixture

This directory is a **qualification fixture**, not beam4pm semantic authority.

The canonical direction remains:

`beam4pm ontology / admitted work-order graph -> generated semconv projection -> Weaver`.

The local registry here exists only to execute the real Weaver v0.26.1 semantic court before the generated registry projection is wired into the repository's ggen manufacturing path. A PASS here proves Weaver integration mechanics and OTLP round-trip validation for the declared correlation attributes. It does **not** prove that this fixture is the runtime registry, that process/postcondition evidence is valid, or that any action is authorized.

Run:

```bash
bash scripts/gall_checkpoint_004_weaver.sh
```

The court validates the registry, starts real Weaver Live-check, uses `weaver registry emit` to send real OTLP/gRPC signals through the listener, stops it through the admin API, requires non-zero observed entities and zero violation findings, and then proves an undeclared authority-token attribute is rejected.
