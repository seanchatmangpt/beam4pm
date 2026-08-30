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

# Full operator chain: submodules -> sync -> test
verify: submodules sync test
