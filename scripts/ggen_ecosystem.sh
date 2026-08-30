#!/usr/bin/env bash
# Run only the Rust GGen executable inside the exact ggen-ecosystem image.
# The caller remains on the host so BEAM/Mix/ggen_igniter and Rust oracle
# binaries continue to execute in the environment they were installed in.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
IMAGE="${GGEN_ECOSYSTEM_IMAGE:-ghcr.io/seanchatmangpt/ggen-ecosystem@sha256:c9ff7e414e0a176df2045c1ea84bd75b6b2fabc7227510b68e6044de067610c8}"

exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$ROOT:/workspace" \
  -w /workspace \
  "$IMAGE" \
  ggen "$@"
