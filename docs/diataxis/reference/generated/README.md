# GENERATED — doc-hdit scaffolded reference skeletons

This directory is **generated documentation**, not a hand-maintained source.
`reference.md`, `how_to.md`, and `explanation.md` are rendered from the
beam4pm code surface by the `rust-doc-hdit-pack` scaffolder
(ggen-marketplace).

## Regeneration

```sh
# From the ggen-marketplace checkout:
python3 scripts/gen_doc_surface.py code /Users/sac/beam4pm \
  > /tmp/hdit/beam4pm.code.v3.json
# Scope to beam4pm's own surface (exclude vendor/deps modules):
python3 - <<'EOF'
import json
code = json.load(open('/tmp/hdit/beam4pm.code.v3.json'))
nv = [m for m in code['modules']
      if not m['file'].startswith(('vendor/', 'deps/'))]
json.dump({"repo": code['repo'], "modules": nv},
          open('/tmp/hdit/beam4pm.code.v3.nonvendor.json', 'w'))
EOF
target/release/doc-hdit scaffold \
  --code /tmp/hdit/beam4pm.code.v3.nonvendor.json \
  --templates templates \
  --out /Users/sac/beam4pm/docs/diataxis/reference/generated
```

Re-runs are byte-identical unless the code surface changed; agent commentary
slots (between `AGENT-COMMENTARY` markers) survive re-scaffolding via
marker-based merge.

## Hand-edit fence

- The reference body between `AGENT-FORBIDDEN-BEGIN`/`END` is RIGID: rows are
  rendered from the code surface. Agents MUST NOT add, edit, reorder, or
  remove rows or table cells.
- The ONLY agent-writable region is between `AGENT-COMMENTARY-BEGIN`/`END`
  markers (bounds stated in-file). Everything outside those markers in the
  three scaffolded files is generated.
- This `README.md` is the only hand-maintained file in this directory.

## Scope

Code surface: beam4pm's own modules (1552 modules, 6680 public items) —
`vendor/` and `deps/` modules are excluded from the denominator (vendored
third-party surface is out of this repo's documentation scope).
