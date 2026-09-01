# Justfile — Operator Surface for beam4pm

# Default recipe: print help / recipes
default:
    @just --list

# Initialize/update vendored submodules (vendor/ggen-marketplace)
submodules:
    git submodule update --init --recursive

# Regenerate ggen.lock from a clean slate, dry-run first, then run for real
sync:
    rm -f ggen.lock
    ggen sync run --dry-run
    ggen sync run

# Run the BEAM test suites: rebar3 eunit for Erlang, mix test for Elixir
test:
    rebar3 eunit
    mix test

# Static scan of hand-authored docs/source for banned overclaiming phrases
# (transplanted architecture from ex4pm's `mix ex4pm.lint.truth`).
lint_truth:
    bash scripts/gate_lint_truth.sh

# Audit every real mix.exs against the two known Igniter defect trigger
# shapes (B4PM-1701): inline deps: [...] vs defp deps do ... end, and any
# parenless zero-arity / guarded def inside mix.exs itself. Emits a
# machine-readable JSON report and self-tests its own detector against a
# real positive fixture before auditing.
mixexs_defect_audit:
    bash scripts/mixexs_defect_audit.sh

# Full operator chain: submodules -> sync -> lint_truth -> mixexs_defect_audit -> test
verify: submodules sync lint_truth mixexs_defect_audit test
