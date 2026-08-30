#!/usr/bin/env bash
set -euo pipefail
exec bash "$(dirname "$0")/ggen_ecosystem.sh" "$@"
