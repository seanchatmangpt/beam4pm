#!/usr/bin/env bash
#
# bench.sh — wall-clock timing benchmark for `ggen sync run --dry-run`
#
# Runs the command N times (default 20, override with --runs), timing each
# invocation's real wall-clock elapsed time using bash's own `time` reserved
# word + TIMEFORMAT (portable: works on macOS's stock bash 3.2, no GNU-only
# date/time flags, no external timing dependency). Prints per-run timings
# plus min/max/mean at the end.
#
# Usage:
#   scripts/bench.sh [--runs N]
#
# Examples:
#   scripts/bench.sh              # 20 runs (default)
#   scripts/bench.sh --runs 50    # 50 runs
#   scripts/bench.sh --runs=5     # 5 runs
#
set -uo pipefail

RUNS=20
CMD=(ggen sync run --dry-run)

usage() {
  cat <<EOF
Usage: $(basename "$0") [--runs N]

Times '${CMD[*]}' wall-clock over N runs and prints min/max/mean.

Options:
  --runs N       Number of iterations to run (default: $RUNS)
  --runs=N       Same as above, '=' form
  -h, --help     Show this help and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      if [[ $# -lt 2 ]]; then
        echo "error: --runs requires a value" >&2
        exit 1
      fi
      RUNS="$2"
      shift 2
      ;;
    --runs=*)
      RUNS="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -lt 1 ]]; then
  echo "error: --runs must be a positive integer (got: '$RUNS')" >&2
  exit 1
fi

if ! command -v ggen >/dev/null 2>&1; then
  echo "error: 'ggen' not found on PATH" >&2
  exit 1
fi

echo "Benchmark: ${CMD[*]}"
echo "Runs:      $RUNS"
echo

# bash's builtin `time` reserved word + TIMEFORMAT is the portable choice
# here: $EPOCHREALTIME requires bash >= 5 (not present in macOS's stock
# /bin/bash, which is 3.2), and BSD `date`/`/usr/bin/time` on macOS lack
# GNU's sub-second %N / -f formatting. `time` + TIMEFORMAT works identically
# on bash 3.2+ everywhere, with no external tools required.
#
# TIMEFORMAT='%R' makes the `time` builtin print just the real elapsed
# seconds (e.g. "0.042"), with no minutes component and no "real/user/sys"
# labels, straight to stderr of the timed compound command.
TIMEFORMAT='%R'

declare -a elapsed=()
failures=0

for ((i = 1; i <= RUNS; i++)); do
  run_time="$( { time "${CMD[@]}" >/dev/null 2>&1; } 2>&1 )"
  status=$?
  elapsed+=("$run_time")
  if [[ $status -ne 0 ]]; then
    failures=$((failures + 1))
    printf 'run %3d: %ss  (exit %d)\n' "$i" "$run_time" "$status"
  else
    printf 'run %3d: %ss\n' "$i" "$run_time"
  fi
done

echo

# min/max/mean via awk — present on macOS by default, no GNU coreutils needed.
printf '%s\n' "${elapsed[@]}" | awk -v runs="$RUNS" -v failures="$failures" '
  {
    if (NR == 1 || $1 < min) min = $1
    if (NR == 1 || $1 > max) max = $1
    sum += $1
    n++
  }
  END {
    if (n == 0) {
      print "no timing data collected"
      exit 1
    }
    mean = sum / n
    printf "Summary (%d runs, %d failed)\n", n, failures
    printf "  min:  %.4fs\n", min
    printf "  max:  %.4fs\n", max
    printf "  mean: %.4fs\n", mean
  }
'
