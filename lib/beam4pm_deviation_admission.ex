# Hand-authored (not ggen-generated). Admitted below via
# bap:hand_authored_lib_beam4pm_deviation_admission -- see ontology.ttl.
defmodule BeamPM.DeviationAdmission do
  @moduledoc """
  Closes the PPCX "conceptual center" gap: a `BeamPM.PowlConformance.check_conformance/3`
  result that reports `conforms: false` today terminates in an ExUnit assertion and
  touches nothing else -- the detected deviation is never admitted anywhere durable.

  This module takes a real `check_conformance/3` result map and, when
  `conforms` is `false`, appends ONE new `bpm:ProcessDeviation` RDF individual
  to `ontology.ttl` on disk -- a real file mutation, not an in-memory struct.

  Reuses the exact same admission shape already used for
  `bpm:HandAuthoredSource` / `bpm:Engine` facts in `ontology.ttl`: a single
  `bap:`-namespaced individual, `a <Class> ;` followed by `bpm:<predicate>
  "<literal>" ;` lines, terminated with `.`. Deliberately does NOT define a
  new `bpm:RecordType`/`bpm:Field` pair or run it through ggen -- the task
  scope is the minimal admitted fact, not a new manufactured projection.

  No RDF library dependency is added: this repo has none, and the existing
  admission blocks in `ontology.ttl` are themselves plain Turtle text, not
  library-constructed graphs, so a real, tested string-append is the
  in-repo-precedented approach (see `lib/mix/tasks/ggen_igniter.patch_field.ex`
  for the analogous precedent of a hand-authored codemod editing checked-in
  source via `File.read!/1` + `File.write!/2`, applied here to `ontology.ttl`
  instead of a generated `.ex` file).
  """

  @ontology_path "ontology.ttl"

  @typedoc "The subset of BeamPM.PowlConformance.conformance_result/0 this module consumes."
  @type conformance_result :: %{
          optional(any()) => any(),
          conforms: boolean(),
          deviations: [[String.t()]]
        }

  @doc """
  Given a real `check_conformance/3` result, a reference trace id, and a
  candidate trace id (both caller-supplied identifiers for the traces that
  were actually compared -- this module does not invent them), appends one
  `bpm:ProcessDeviation` individual to `ontology.ttl` when `conforms` is
  `false`. No-ops (returns `{:ok, :conforms}`) when the trace conformed --
  there is nothing to admit.

  The deviating activity/move is taken from the FIRST entry of the real
  `deviations` list (a real `[log_side, model_side]` alignment move pair,
  exactly as returned by `check_conformance/3` -- never invented). Returns
  `{:ok, individual_name}` on a successful write, `{:error, :no_deviation}`
  if `conforms: false` was asserted but `deviations` is empty (a contract
  violation this module refuses to admit a fact about), or `{:error,
  {:read_failed | :write_failed, reason}}` on a real file I/O failure.
  """
  @spec admit_deviation(conformance_result(), String.t(), String.t(), String.t()) ::
          {:ok, :conforms} | {:ok, String.t()} | {:error, term()}
  def admit_deviation(result, reference_trace_id, candidate_trace_id, ontology_path \\ @ontology_path)

  def admit_deviation(%{conforms: true}, _reference_trace_id, _candidate_trace_id, _ontology_path) do
    {:ok, :conforms}
  end

  def admit_deviation(%{conforms: false, deviations: []}, _reference_trace_id, _candidate_trace_id, _ontology_path) do
    {:error, :no_deviation}
  end

  def admit_deviation(
        %{conforms: false, deviations: [[log_side, model_side] | _rest]},
        reference_trace_id,
        candidate_trace_id,
        ontology_path
      )
      when is_binary(reference_trace_id) and is_binary(candidate_trace_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    deviating_move = "#{log_side}/#{model_side}"

    individual_name =
      "process_deviation_" <>
        (:crypto.hash(:sha256, reference_trace_id <> candidate_trace_id <> deviating_move <> timestamp)
         |> Base.encode16(case: :lower)
         |> binary_part(0, 16))

    turtle_block = build_turtle_block(individual_name, reference_trace_id, candidate_trace_id, deviating_move, timestamp)

    with {:ok, current} <- read_ontology(ontology_path),
         :ok <- write_ontology(ontology_path, append_block(current, turtle_block)) do
      {:ok, individual_name}
    end
  end

  @spec build_turtle_block(String.t(), String.t(), String.t(), String.t(), String.t()) :: String.t()
  defp build_turtle_block(individual_name, reference_trace_id, candidate_trace_id, deviating_move, timestamp) do
    """

    bap:#{individual_name} a bpm:ProcessDeviation ;
        bpm:deviationReferenceTrace "#{escape(reference_trace_id)}" ;
        bpm:deviationCandidateTrace "#{escape(candidate_trace_id)}" ;
        bpm:deviationActivity "#{escape(deviating_move)}" ;
        bpm:deviationTimestamp "#{escape(timestamp)}"^^xsd:dateTime ;
        bpm:deviationStatus "observed" .
    """
  end

  @spec escape(String.t()) :: String.t()
  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  @spec read_ontology(String.t()) :: {:ok, String.t()} | {:error, {:read_failed, term()}}
  defp read_ontology(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:read_failed, reason}}
    end
  end

  @spec append_block(String.t(), String.t()) :: String.t()
  defp append_block(current, block) do
    String.trim_trailing(current) <> "\n" <> block
  end

  @spec write_ontology(String.t(), String.t()) :: :ok | {:error, {:write_failed, term()}}
  defp write_ontology(path, contents) do
    case File.write(path, contents) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end
end
