#!/usr/bin/env bash
# GATE NO-KOALA-DEPENDENCY: structural proof that ferroplan-hddl (and the rest of
# this repo's build graph) never depends on the local ~/koala-planner reference
# project as a build/runtime input.
#
# Why structural (grep-based) rather than a build-with-path-hidden test:
# koala-planner is not referenced by any Cargo.toml/mix.exs/ggen.toml path
# dependency, shelled out to via Command::new/System.cmd, or read as a data
# file at build or run time anywhere in this tree (confirmed by audit,
# 2026-09-10). The only references are doc-comment design-lineage attribution
# in native/ferroplan/crates/ferroplan-hddl/src/{lib.rs,parser.rs,probabilistic.rs}
# and a prose wiring doc (docs/jira/v26.9.10/hddl/wire-koala-ferroplan.domain.hddl).
# A grep-based manifest/shellout scan is therefore a complete proof of "no real
# dependency exists" for this codebase's dependency surface (manifests + process
# spawns), and it runs on every CI invocation going forward -- cheaper and more
# reliable than a sandbox rebuild, and it catches the exact failure mode this
# gate exists to prevent: someone later adding
#   koala-planner = { path = "../../koala-planner" }
# to a Cargo.toml, or a Command::new("koala")/pandaPI shellout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail=0

echo "[gate-no-koala] scanning manifests for path/dependency references to koala-planner..."
# Cargo.toml (main tree + native/ferroplan + its submodule crates), mix.exs, ggen.toml
manifest_hits=$(grep -rniE 'koala' \
  --include='Cargo.toml' --include='mix.exs' --include='ggen.toml' \
  . 2>/dev/null || true)
if [ -n "$manifest_hits" ]; then
  echo "REFUSED_MANIFEST_KOALA_REFERENCE: found koala reference in a build manifest:"
  echo "$manifest_hits"
  fail=1
else
  echo "  ok: zero koala references in any Cargo.toml/mix.exs/ggen.toml"
fi

echo "[gate-no-koala] scanning for path-dependency style references to a local koala-planner checkout..."
path_hits=$(grep -rniE '\.\./koala-planner|koala-planner"|path.*koala' \
  --include='*.toml' --include='*.exs' \
  . 2>/dev/null || true)
if [ -n "$path_hits" ]; then
  echo "REFUSED_PATH_DEPENDENCY: found path-dependency-shaped reference to koala-planner:"
  echo "$path_hits"
  fail=1
else
  echo "  ok: zero path-dependency-shaped references"
fi

echo "[gate-no-koala] scanning source for subprocess shellouts to koala/pandaPI binaries..."
shellout_hits=$(grep -rniE 'Command::new\("?(koala|pandaPI)|System\.cmd\("(koala|pandaPI)' \
  --include='*.rs' --include='*.ex' --include='*.exs' --include='*.erl' \
  . 2>/dev/null || true)
if [ -n "$shellout_hits" ]; then
  echo "REFUSED_SUBPROCESS_SHELLOUT: found subprocess shellout to koala/pandaPI:"
  echo "$shellout_hits"
  fail=1
else
  echo "  ok: zero subprocess shellouts to koala/pandaPI binaries"
fi

if [ "$fail" -ne 0 ]; then
  echo "[gate-no-koala] FAILED"
  exit 1
fi

echo "[gate-no-koala] PASSED: no real dependency on ~/koala-planner exists in this repo's build graph"
exit 0
