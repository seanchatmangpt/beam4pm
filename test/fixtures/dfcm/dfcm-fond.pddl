(define (domain beam4pm-dfcm-fond)
  (:requirements :strips :typing :negative-preconditions :non-deterministic)

  (:types option observation)

  (:predicates
    (admitted ?o - option)
    (preserved ?o - option)
    (excluded ?o - option)
    (receipt ?o - option)
    (falsifier ?o - option)
    (requires-observation ?o - option ?x - observation)
    (observation-known ?x - observation)
    (observation-positive ?x - observation)
    (observation-negative ?x - observation)
    (observation-inconclusive ?x - observation)
    (enabled ?o - option)
    (selected ?o - option)
  )

  (:action preserve-option
    :parameters (?o - option)
    :precondition (and (admitted ?o) (not (excluded ?o)))
    :effect (preserved ?o))

  (:action resolve-observation
    :parameters (?x - observation)
    :precondition (not (observation-known ?x))
    :effect (oneof
      (and (observation-known ?x) (observation-positive ?x))
      (and (observation-known ?x) (observation-negative ?x))
      (observation-inconclusive ?x)))

  ;; An inconclusive result deliberately does not assert observation-known,
  ;; so a fair strong-cyclic policy may lawfully observe again.
  (:action clear-inconclusive
    :parameters (?x - observation)
    :precondition (observation-inconclusive ?x)
    :effect (not (observation-inconclusive ?x)))

  (:action receipt-exclusion
    :parameters (?o - option)
    :precondition (and (excluded ?o) (not (receipt ?o)))
    :effect (and (receipt ?o) (falsifier ?o)))

  (:action select-option
    :parameters (?o - option)
    :precondition (and
      (admitted ?o)
      (preserved ?o)
      (enabled ?o)
      (not (excluded ?o))
      (receipt-all-exclusions))
    :effect (selected ?o))

  ;; Marker predicate is kept zero-arity so the benchmark can require that all
  ;; exclusions have receipts before selection without granting DO authority.
  (:predicates (receipt-all-exclusions))
)
