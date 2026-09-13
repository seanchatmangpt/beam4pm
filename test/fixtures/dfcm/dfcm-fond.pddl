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
    (depends-positive ?o - option ?x - observation)
    (observation-known ?x - observation)
    (observation-positive ?x - observation)
    (observation-negative ?x - observation)
    (observation-inconclusive ?x - observation)
    (enabled ?o - option)
    (decision-observations-resolved)
    (receipt-all-exclusions)
    (selected ?o - option)
    (selection-complete)
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
  ;; so a fair strong-cyclic policy may lawfully clear it and observe again.
  (:action clear-inconclusive
    :parameters (?x - observation)
    :precondition (observation-inconclusive ?x)
    :effect (not (observation-inconclusive ?x)))

  (:action enable-positive-option
    :parameters (?o - option ?x - observation)
    :precondition (and
      (observation-known ?x)
      (observation-positive ?x)
      (depends-positive ?o ?x))
    :effect (enabled ?o))

  (:action close-positive-observation
    :parameters (?x - observation)
    :precondition (and
      (observation-known ?x)
      (observation-positive ?x))
    :effect (decision-observations-resolved))

  (:action close-negative-observation
    :parameters (?x - observation)
    :precondition (and
      (observation-known ?x)
      (observation-negative ?x))
    :effect (decision-observations-resolved))

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
      (decision-observations-resolved)
      (receipt-all-exclusions))
    :effect (and
      (selected ?o)
      (selection-complete)))

  ;; Deliberately absent: execute, actuate, write, or any other DO primitive.
)
