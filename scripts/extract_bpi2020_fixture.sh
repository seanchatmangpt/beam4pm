#!/usr/bin/env bash
# extract_bpi2020_fixture.sh -- deterministic, stratified BPI-2020 fixture extraction.
#
# Derives a SMALL committed XES fixture from a full BPI-2020 log by copying the
# log header and the first-N-in-file-order complete <trace> blocks per revenue
# stratum, byte-for-byte (no re-serialization). Deterministic: same input file
# -> same output file, always (file order + fixed quotas; no randomness).
#
# Revenue strata (classified per trace on event concept:name values):
#   paid_clean    -- has "Payment Handled", no "REJECTED"    (happy revenue path)
#   rework_paid   -- has "REJECTED" and "Payment Handled"    (rejection loop -> rework cost, still paid)
#   rejected_only -- has "REJECTED", no "Payment Handled"    (lost/abandoned after rework)
#   no_payment    -- neither                                  (saved/abandoned, no money outcome)
#
# Usage:
#   scripts/extract_bpi2020_fixture.sh INPUT.xes OUTPUT.xes [PAID CLEAN=20] [REWORK=15] [REJECTED=10] [NOPAY=5]
#
# Example (the committed fixtures):
#   scripts/extract_bpi2020_fixture.sh \
#     /Users/sac/wasm4pm/data/InternationalDeclarations.xes \
#     qualification/fixtures/bpi2020/international_50.xes
set -euo pipefail

IN="${1:?input .xes}"
OUT="${2:?output .xes}"
Q_PAID="${3:-20}"
Q_REWORK="${4:-15}"
Q_REJECT="${5:-10}"
Q_NOPAY="${6:-5}"

mkdir -p "$(dirname "$OUT")"

awk -v q_paid="$Q_PAID" -v q_rework="$Q_REWORK" -v q_reject="$Q_REJECT" -v q_nopay="$Q_NOPAY" '
  BEGIN { in_trace=0; n_paid=0; n_rework=0; n_reject=0; n_nopay=0; header_done=0 }
  /<trace>/ { in_trace=1; buf=""; has_pay=0; has_rej=0; header_done=1 }
  {
    if (!header_done && !in_trace) { print; next }   # log header, extensions, log attrs
    if (in_trace) {
      buf = buf $0 "\n"
      if ($0 ~ /key="concept:name" value="Payment Handled"/) has_pay=1
      if ($0 ~ /key="concept:name" value="[^"]*REJECTED/)    has_rej=1
      if ($0 ~ /<\/trace>/) {
        in_trace=0
        if      (has_pay && !has_rej && n_paid   < q_paid)   { printf "%s", buf; n_paid++ }
        else if (has_pay &&  has_rej && n_rework < q_rework) { printf "%s", buf; n_rework++ }
        else if (!has_pay && has_rej && n_reject < q_reject) { printf "%s", buf; n_reject++ }
        else if (!has_pay && !has_rej && n_nopay < q_nopay)  { printf "%s", buf; n_nopay++ }
        if (n_paid==q_paid && n_rework==q_rework && n_reject==q_reject && n_nopay==q_nopay) exit
      }
    }
  }
  END {
    printf "strata: paid_clean=%d rework_paid=%d rejected_only=%d no_payment=%d\n", n_paid, n_rework, n_reject, n_nopay > "/dev/stderr"
  }
' "$IN" > "$OUT.tmp"

printf "</log>\n" >> "$OUT.tmp"
mv "$OUT.tmp" "$OUT"

echo "wrote $OUT ($(grep -c "<trace>" "$OUT") traces, $(grep -c "<event>" "$OUT") events, $(wc -c < "$OUT" | tr -d " ") bytes)" >&2
