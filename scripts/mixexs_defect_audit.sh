#!/usr/bin/env bash
# mixexs_defect_audit.sh -- B4PM-1701
#
# Audits every real mix.exs in this repo against the two known Igniter
# defect trigger shapes documented in
# docs/jira/v26.8.31/03-known-defects-and-mitigations.md:
#
#   (a) Defect #1 trigger: `Igniter.Project.Deps.add_dep/2,3` crashes with
#       an uncaught CaseClauseError when the target mix.exs declares its
#       dependency list inline (`deps: [...]`) inside `project/0` instead
#       of via a separate `defp deps do [...] end` function.
#   (b) Any parenless zero-arity `def`/`defp` (e.g. `def application do`,
#       `def foo, do: ...`) or guarded `def`/`defp ... when ... do` inside
#       the mix.exs file itself -- these are the shapes that make
#       Igniter.Code.Function zipper navigation (move_to_defp/3,
#       move_to_def/3) fragile against real-world mix.exs files.
#
# Emits one machine-readable JSON object per mix.exs (one row per file,
# with a nested array of trigger-shape matches/non-matches) to stdout.
#
# Exit code: 0 if the audit ran and its embedded self-test (proving the
# script actually detects the positive/inline-deps case against a real
# fixture) passed; non-zero otherwise. This script does NOT fail the
# build because a mix.exs matches a trigger shape -- matching is a
# reportable fact, not itself a defect in beam4pm's own code. It fails
# only if the detector itself is broken (self-test failure) or if no
# mix.exs files were found to audit.
#
# Wired into `just verify` (see justfile) as a standing check.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Classifier: given a mix.exs path, emit one JSON object describing its
# trigger-shape matches. Pure function of file content -- no side effects.
# ---------------------------------------------------------------------------
classify_mixexs() {
    local file="$1"
    local rel="$2"

    # --- Trigger (a): inline deps: [...] in project/0 vs defp deps do ---
    # A "separate defp deps" convention is present if `defp deps do` (any
    # arity-0 defp named deps) exists anywhere in the file.
    local defp_deps_line
    defp_deps_line="$(grep -nE '^[[:space:]]*defp[[:space:]]+deps[[:space:]]+do[[:space:]]*$' "$file" | head -1 | cut -d: -f1 || true)"

    # An inline `deps: [` list-literal assignment (as opposed to
    # `deps: deps()` referencing the separate function) anywhere in the
    # file -- this is what Igniter's defect-#1 trigger condition requires
    # when there is no separate defp deps do.
    local inline_deps_line
    inline_deps_line="$(grep -nE '(^|[^:_])deps:[[:space:]]*\[' "$file" | head -1 | cut -d: -f1 || true)"

    local trigger_a_matched="false"
    local trigger_a_note=""
    if [ -n "$inline_deps_line" ] && [ -z "$defp_deps_line" ]; then
        trigger_a_matched="true"
        trigger_a_note="inline deps: [...] at line ${inline_deps_line}, no separate defp deps do found"
    elif [ -n "$defp_deps_line" ]; then
        trigger_a_matched="false"
        trigger_a_note="uses separate defp deps do ... end at line ${defp_deps_line} (Igniter's expected convention); not the inline-deps defect-#1 trigger shape"
    else
        trigger_a_matched="false"
        trigger_a_note="no deps: [...] and no defp deps do found (no deps declared, or deps declared via an uninspected shape)"
    fi

    # --- Trigger (b): parenless zero-arity or guarded def/defp ---
    # Parenless zero-arity forms:
    #   def name do            (block form, no parens)
    #   def name, do: ...      (keyword-list form, no parens)
    # Guarded forms:
    #   def name when <guard> do
    #   def name(...) when <guard> do
    local -a b_matches=()
    while IFS=: read -r lineno content; do
        [ -z "$lineno" ] && continue
        local kind="parenless-zero-arity"
        if echo "$content" | grep -qE '[[:space:]]when[[:space:]]'; then
            kind="guarded"
        fi
        local trimmed
        trimmed="$(echo "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/"/\\"/g')"
        b_matches+=("{\"line\": ${lineno}, \"kind\": \"${kind}\", \"code\": \"${trimmed}\"}")
    done < <(grep -nE '^[[:space:]]*def[p]?[[:space:]]+[A-Za-z_][A-Za-z0-9_?!]*([[:space:]]+when[[:space:]]+.*)?[[:space:]]+do[[:space:]]*$|^[[:space:]]*def[p]?[[:space:]]+[A-Za-z_][A-Za-z0-9_?!]*[[:space:]]*,[[:space:]]*do:' "$file")

    local b_json="[]"
    if [ "${#b_matches[@]}" -gt 0 ]; then
        b_json="[$(IFS=,; echo "${b_matches[*]}")]"
    fi

    local trigger_b_matched="false"
    [ "${#b_matches[@]}" -gt 0 ] && trigger_b_matched="true"

    printf '{"file": "%s", "trigger_a_inline_deps": {"matched": %s, "note": "%s"}, "trigger_b_parenless_or_guarded_def": {"matched": %s, "matches": %s}}\n' \
        "$rel" "$trigger_a_matched" "$trigger_a_note" "$trigger_b_matched" "$b_json"
}

# ---------------------------------------------------------------------------
# Self-test: prove the classifier actually detects the positive case
# (an inlined deps: [...] mix.exs with no separate defp deps do),
# reproducing ~/ex4pm/apps/ex4pm_contracts/mix.exs's real shape, embedded
# here so the proof does not depend on ~/ex4pm existing on this machine.
# ---------------------------------------------------------------------------
self_test() {
    local tmp
    tmp="$(mktemp -d)"

    cat > "$tmp/positive_fixture_mix.exs" <<'EOF'
defmodule Ex4pmContracts.MixProject do
  use Mix.Project

  @version "26.8.22"
  @source_url "https://github.com/seanchatmangpt/ex4pm"

  def project do
    [
      app: :ex4pm_contracts,
      version: @version,
      description: "Executable ontology, WIT, SHACL and receipt contracts for ex4pm",
      source_url: @source_url,
      package: package(),
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      deps: [{:ex4pm_core, "~> 26.8.22", in_umbrella: true}]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp package,
    do: [licenses: ["MIT"], links: %{"GitHub" => @source_url}, files: ["lib", "priv", "mix.exs"]]
end
EOF

    local result
    result="$(classify_mixexs "$tmp/positive_fixture_mix.exs" "self-test/positive_fixture_mix.exs")"

    if ! echo "$result" | grep -q '"trigger_a_inline_deps": {"matched": true'; then
        echo "SELF-TEST FAILED: positive fixture (inline deps:[...], no defp deps) did not classify as trigger (a) MATCHED" >&2
        echo "Got: $result" >&2
        rm -rf "$tmp"
        return 1
    fi

    # The fixture's `def application, do: [...]` and `defp package, do:
    # [...]` are both parenless zero-arity forms -- confirm trigger (b)
    # also fires on this fixture (double-checks the detector isn't
    # accidentally vacuous).
    if ! echo "$result" | grep -q '"trigger_b_parenless_or_guarded_def": {"matched": true'; then
        echo "SELF-TEST FAILED: positive fixture's parenless defs (def application, do: ...) were not detected as trigger (b)" >&2
        echo "Got: $result" >&2
        rm -rf "$tmp"
        return 1
    fi

    echo "SELF-TEST PASSED: positive fixture (reproducing ~/ex4pm/apps/ex4pm_contracts/mix.exs's inline-deps shape) correctly classified as trigger (a) MATCHED, trigger (b) MATCHED" >&2
    rm -rf "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# Main: run self-test, then audit every real mix.exs in this repo.
# ---------------------------------------------------------------------------
main() {
    self_test || exit 1

    # Real mix.exs files only: exclude deps/_build (fetched dependency
    # sources, not this repo's own), .claude/worktrees (nested worktree
    # checkouts, not distinct project files), and vendor/ (the vendored
    # ggen-marketplace submodule, a separate project with its own audit
    # surface, not beam4pm's own mix.exs).
    local -a files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$REPO_ROOT" \
        -name mix.exs \
        -not -path '*/deps/*' \
        -not -path '*/_build/*' \
        -not -path '*/.claude/worktrees/*' \
        -not -path '*/vendor/*' \
        -print0)

    if [ "${#files[@]}" -eq 0 ]; then
        echo "ERROR: no mix.exs files found under $REPO_ROOT" >&2
        exit 1
    fi

    echo "["
    local first=true
    for f in "${files[@]}"; do
        local rel="${f#"$REPO_ROOT"/}"
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        classify_mixexs "$f" "$rel"
    done
    echo "]"
}

main "$@"
