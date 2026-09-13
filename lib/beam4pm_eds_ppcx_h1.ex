# Hand-authored (not ggen-generated). Admitted below via
# bap:hand_authored_lib_beam4pm_eds_ppcx_h1 -- see ontology.ttl.
defmodule BeamPM.EDS.PPCXH1 do
  @moduledoc """
  The first concrete Executable Research Claim (ERC) under `BeamPM.EDS`,
  operationalizing the EDS paper's Section 16 example:

      H1: a system that feeds verified conformance deviations back into its
      planning model will encounter fewer previously observed unhandled
      execution states than a system that logs deviations but does not
      update its planning model.

  This module implements the FIRST HALF of H1's real artifact -- the "feeds
  deviations back" condition -- by driving a real `BeamPM.EDS.Claim` through
  its full, enforced evidence ladder against the real, already-built
  pipeline: `BeamPM.PowlConformance.check_conformance/3` (DETECT) ->
  `BeamPM.DeviationAdmission.admit_deviation/4` (REVISE, the paper's own
  "conceptual center" gap, closed earlier this branch).

  ## Honest scope

  This is `H1`'s artifact for the DEVIATION-FEEDBACK condition only. It does
  NOT yet implement or run the CONTROL condition (a system that logs but
  does not revise) or the comparative measurement
  (`Unhandled_PPCX < Unhandled_Control`) the paper's falsifier requires --
  that is real, disclosed future work, not claimed here. What this module
  DOES really demonstrate: every stage of H1's artifact -- construct
  reference model, detect a real deviation, admit it to the ontology -- goes
  through `BeamPM.EDS`'s enforced `:proposed -> :implemented -> :executable
  -> :observed -> :verified` ladder with a REAL receipt at every hop, so the
  claim's own evidence trail is independently replayable
  (`BeamPM.EDS.verify/2`) -- not asserted once in a test and forgotten.
  """

  alias BeamPM.EDS
  alias BeamPM.EDS.Claim
  alias BeamPM.DeviationAdmission

  @claim_id "ppcx-h1-deviation-feedback"
  @hypothesis "A system that admits detected conformance deviations into its ontology " <>
                "(rather than only logging them) accumulates a growing, inspectable record " <>
                "of previously observed unhandled execution states -- a real precondition for " <>
                "the paper's full H1 comparative claim (Unhandled_PPCX < Unhandled_Control), " <>
                "which itself remains future work, not claimed here."
  @artifact "BeamPM.PowlConformance.check_conformance/3 -> BeamPM.DeviationAdmission.admit_deviation/4"
  @falsifier "check_conformance/3 reports conforms: false but admit_deviation/4 either fails to " <>
               "write a real bpm:ProcessDeviation individual, or the individual is not present " <>
               "when ontology.ttl is read back -- either observation falsifies this claim's artifact."

  @doc """
  Runs the full ladder for real: PROPOSED -> IMPLEMENTED (the artifact
  functions exist and are callable) -> EXECUTABLE (a real `check_conformance/3`
  call over a real, caller-supplied deviant OCEL result) -> OBSERVED (the
  real returned `conforms`/`deviations` are captured as evidence) ->
  VERIFIED (a real `admit_deviation/4` call against `ontology_path`, with
  the resulting `ontology.ttl` bytes read back and confirmed to contain the
  new individual -- not merely trusting the `{:ok, name}` return value).

  `conformance_result` must be a real `check_conformance/3` result with
  `conforms: false` (a real deviating trace) -- this function refuses to
  claim VERIFIED evidence for a conforming trace (there would be nothing to
  admit, and the falsifier above would be vacuous).
  """
  @spec run(map(), String.t(), String.t(), String.t()) ::
          {:ok, Claim.t()} | {:error, term()}
  def run(conformance_result, reference_trace_id, candidate_trace_id, ontology_path)
      when is_map(conformance_result) and is_binary(reference_trace_id) and
             is_binary(candidate_trace_id) and is_binary(ontology_path) do
    with claim <- EDS.new_claim(@claim_id, @hypothesis, @artifact, @falsifier),
         {:ok, claim} <- EDS.transition(claim, :implemented, %{
           check_conformance_mfa: "BeamPM.PowlConformance.check_conformance/3",
           admit_deviation_mfa: "BeamPM.DeviationAdmission.admit_deviation/4"
         }),
         {:ok, claim} <- EDS.transition(claim, :executable, %{
           conformance_result_conforms: Map.fetch!(conformance_result, :conforms),
           conformance_result_deviation_count: length(Map.get(conformance_result, :deviations, []))
         }),
         %Claim{} = claim <- reject_conforming(conformance_result, claim),
         {:ok, claim} <- EDS.transition(claim, :observed, %{
           real_deviations: Map.fetch!(conformance_result, :deviations),
           real_fitness: Map.get(conformance_result, :fitness)
         }),
         {:ok, individual_name} <-
           DeviationAdmission.admit_deviation(conformance_result, reference_trace_id, candidate_trace_id, ontology_path),
         {:ok, on_disk} <- File.read(ontology_path),
         true <- String.contains?(on_disk, individual_name) do
      EDS.transition(claim, :verified, %{
        admitted_individual: individual_name,
        ontology_path: ontology_path,
        ontology_bytes_after_admission: byte_size(on_disk)
      })
    else
      {:conforming, claim} ->
        EDS.transition(claim, :blocked, %{
          reason: "conformance_result reported conforms: true -- nothing to admit; " <>
            "this artifact run's falsifier is only meaningful against a real deviation"
        })

      false ->
        {:error, :admitted_individual_not_found_on_readback}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Small local helper so `with`'s clause list stays readable: routes a
  # conforming result to a real :blocked transition (a legal terminal state
  # from any non-terminal state per EDS.legal_transition?/2) instead of
  # silently proceeding to fabricate a VERIFIED claim over nothing.
  defp reject_conforming(%{conforms: false}, claim), do: claim
  defp reject_conforming(%{conforms: true}, claim), do: {:conforming, claim}
end
