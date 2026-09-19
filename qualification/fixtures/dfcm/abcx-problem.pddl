(define (problem beam4pm-dfcm-abcx)
  (:domain beam4pm-dfcm-fond)

  (:objects
    a b c - option
    x - observation)

  (:init
    (admitted a)
    (admitted b)
    (admitted c)
    (enabled a)
    (enabled b)
    (requires-observation c x)
    (depends-positive c x)
    (receipt-all-exclusions))

  ;; The FOND problem ends when a lawful option has been SELECTed. Execution
  ;; is intentionally outside this domain and remains a downstream BRCE act.
  (:goal (selection-complete))
)
