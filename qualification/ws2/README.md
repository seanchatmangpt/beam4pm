# qualification/ws2 — bench receipt fixture

`bench-receipt-ws2-court.json` is a **committed benchmark fixture**, not a live measurement.

## Generation command

```bash
python3 qualification/ws2/bench_ws2_court.py --out qualification/ws2/bench-receipt-ws2-court.json
```

(`--runs`/`--synthetic`/`--post-sync-root`/`--evidence` are optional; the committed
fixture used defaults.)

## Machine specificity

Timing numbers (`blake3_mib_per_s`, `receipt_first_real_*`, `regression_bounds`,
`synthetic_*`) are host-specific (arm64, macOS, Python 3.14) and were captured under
heavy host load (see `measured_on`). Do not compare them against other hosts or treat
them as portable absolute numbers — the bounds are relative regression gates against
re-runs on the same host class.

## Role: RegressionBound input

The committed `regression_bounds` in this file are consumed by
`test_ws2_manufacture_court.py` as RegressionBound inputs — the fixture defines the
envelope the court asserts against, so regenerating it changes court acceptance.
Regenerate deliberately, with the court run before and after, never casually.
