#!/usr/bin/env bash
set -euo pipefail

# Focused repository-native court for the hand-authored GALL -> OCEL bridge.
# This does not replace ggen sync, the generated-code authorship court, or the
# independent Weaver/OCEL conformance court.
mix run scripts/gall_semantic_work_observer.exs --self-test
