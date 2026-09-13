# Hand-authored (not ggen-generated). Admitted below via
# bap:hand_authored_lib_beam4pm_eds -- see ontology.ttl.
defmodule BeamPM.EDS do
  @moduledoc """
  Executable Design Science (EDS) core: an `ExecutableResearchClaim`
  (`BeamPM.EDS.Claim`) whose evidence state can only advance through a real,
  enforced ladder -- `PROPOSED -> IMPLEMENTED -> EXECUTABLE -> OBSERVED ->
  VERIFIED` (plus the terminal `FALSIFIED`/`BLOCKED`/`UNSUPPORTED` states
  reachable from any non-terminal state) -- never collapsed or skipped.
  Every transition is recorded as a real `beam4pm-brce/v1`-shaped receipt,
  chained via the already-real `BeamPM.ReceiptChain` linkage primitives
  (`link_fields/3`, `hash_file!/1`) under a `chain_id` scoped to the claim,
  so a claim's evidence history is independently replayable the same way
  every other beam4pm receipt chain already is -- no new receipt format,
  no new chaining logic, pure reuse.

  This directly operationalizes the EDS paper's central rule:

      implemented != executed != observed != verified != reproduced

  by making an illegal state transition (e.g. `PROPOSED` straight to
  `VERIFIED`, skipping real execution and observation) a real, refused
  `{:error, {:illegal_transition, from, to}}` -- not merely a documentation
  convention.

  ## Evidence states

  `t:state/0` intentionally omits `REPRODUCIBLE`/`REPRODUCED` from the
  paper's full vocabulary for this first slice: this module tracks ONE
  claim's own evidence lifecycle (single-investigator, single-environment),
  not independent third-party reproduction, which is a real, disclosed,
  separate capability this module does not yet implement.

  ## Reuse, not invention

  This module does not add a new receipt directory convention, a new hash
  algorithm, or a new chain-index format -- every receipt this module
  writes lives in the same `receipts/` tree, under the same
  `beam4pm-brce/v1` schema, linked via the exact same `BeamPM.ReceiptChain`
  functions every other engine-op receipt in this repo already uses.
  """

  alias BeamPM.ReceiptChain

  @states ~w(proposed implemented executable observed verified falsified blocked unsupported)a

  @typedoc "One of the 8 EDS evidence states this module enforces."
  @type state ::
          :proposed | :implemented | :executable | :observed | :verified
          | :falsified | :blocked | :unsupported

  @typedoc "An Executable Research Claim: hypothesis, artifact, falsifier, and its evidence history."
  @type t :: %__MODULE__.Claim{
          id: String.t(),
          hypothesis: String.t(),
          artifact: String.t(),
          falsifier: String.t(),
          state: state(),
          history: [%{state: state(), recorded_at: String.t(), receipt_path: String.t()}]
        }

  defmodule Claim do
    @moduledoc "The `ExecutableResearchClaim` struct. See `BeamPM.EDS` for the enforced state ladder."
    @enforce_keys [:id, :hypothesis, :artifact, :falsifier]
    defstruct [:id, :hypothesis, :artifact, :falsifier, state: :proposed, history: []]
  end

  @doc """
  Starts a new claim in the `:proposed` state. `id` is a caller-supplied,
  stable identifier (e.g. `"ppcx-h1-deviation-feedback"`) used as the
  receipt chain's `chain_id` (prefixed `"eds."`) -- never invented here.
  """
  @spec new_claim(String.t(), String.t(), String.t(), String.t()) :: t()
  def new_claim(id, hypothesis, artifact, falsifier)
      when is_binary(id) and is_binary(hypothesis) and is_binary(artifact) and is_binary(falsifier) do
    %Claim{id: id, hypothesis: hypothesis, artifact: artifact, falsifier: falsifier}
  end

  @doc "The full, ordered evidence-state ladder this module enforces (excluding terminal states)."
  @spec ladder() :: [state()]
  def ladder, do: [:proposed, :implemented, :executable, :observed, :verified]

  @terminal ~w(falsified blocked unsupported)a

  @doc """
  Advances `claim` to `to_state`, given real `evidence` (a plain map --
  caller-supplied, e.g. `%{command: "...", output: "..."}` or
  `%{deviation_admission: {:ok, individual_name}}` -- never fabricated by
  this module). Refuses (`{:error, {:illegal_transition, from, to}}`)
  unless `to_state` is:

    * the next state after `claim.state` on `ladder/0` (no skipping), OR
    * one of the terminal states (`:falsified`/`:blocked`/`:unsupported`),
      reachable from any non-terminal state at any point -- a real
      falsification, block, or unsupported finding can occur at any stage,
      per the EDS paper's own falsifier discipline (Section 9/19: negative
      evidence must remain representable, not just forward progress).

  On success, writes one real `beam4pm-brce/v1` receipt to
  `receipts/eds/<id>-<chain_seq>.json` (chained via
  `BeamPM.ReceiptChain.link_fields/3`, `standing` defaulted per
  `BeamPM.ReceiptChain.default_standing/0`), and returns `{:ok, claim}`
  with the new state and an appended history entry.
  """
  @spec transition(t(), state(), map(), String.t()) :: {:ok, t()} | {:error, term()}
  def transition(claim, to_state, evidence \\ %{}, receipts_dir \\ "receipts/eds")

  def transition(%Claim{} = claim, to_state, evidence, receipts_dir)
      when to_state in @states and is_map(evidence) and is_binary(receipts_dir) do
    if legal_transition?(claim.state, to_state) do
      do_transition(claim, to_state, evidence, receipts_dir)
    else
      {:error, {:illegal_transition, claim.state, to_state}}
    end
  end

  @spec legal_transition?(state(), state()) :: boolean()
  defp legal_transition?(from, to) when to in @terminal, do: from not in @terminal

  defp legal_transition?(from, to) do
    ladder = ladder()
    from_idx = Enum.find_index(ladder, &(&1 == from))
    to_idx = Enum.find_index(ladder, &(&1 == to))
    is_integer(from_idx) and is_integer(to_idx) and to_idx == from_idx + 1
  end

  @spec do_transition(t(), state(), map(), String.t()) :: {:ok, t()}
  defp do_transition(%Claim{} = claim, to_state, evidence, receipts_dir) do
    File.mkdir_p!(receipts_dir)
    chain_id = "eds." <> claim.id
    recorded_at = DateTime.utc_now() |> DateTime.to_iso8601()

    # chain_seq is not known until link_fields/3 runs, so the receipt path
    # is provisional (uses a monotonic-enough discriminator: history length
    # + 1) and link_fields/3's own returned chain_seq is what actually gets
    # written into the receipt body -- the path itself need not be exact,
    # only unique and stable once written (matches the existing engine-op
    # receipt naming convention's own loose path/chain_seq coupling).
    provisional_seq = length(claim.history) + 1
    receipt_path = Path.join(receipts_dir, "#{claim.id}-#{provisional_seq}.json")

    link = ReceiptChain.link_fields(receipts_dir, chain_id, receipt_path)

    receipt = %{
      "receipt_schema" => "beam4pm-brce/v1",
      "run_id" => "#{claim.id}-#{link.chain_seq}",
      "chain_id" => chain_id,
      "chain_seq" => link.chain_seq,
      "prev_receipt_path" => link.prev_receipt_path,
      "prev_receipt_hash" => link.prev_receipt_hash,
      "op" => "eds.transition",
      "op_iri" => "https://ggen.dev/ontology/beam-process-model#eds/transition",
      "engine" => "eds",
      "outcome" => if(to_state in @terminal, do: to_string(to_state), else: "ok"),
      "refusal_reason" => nil,
      "invocation_id" => claim.id,
      "recorded_at" => recorded_at,
      "duration_ms" => 0,
      "args_digest" => "",
      "verification_class" => "eds_claim_transition",
      "standing" => ReceiptChain.default_standing(),
      "eds_claim_id" => claim.id,
      "eds_hypothesis" => claim.hypothesis,
      "eds_artifact" => claim.artifact,
      "eds_falsifier" => claim.falsifier,
      "eds_from_state" => to_string(claim.state),
      "eds_to_state" => to_string(to_state),
      "eds_evidence" => evidence
    }

    File.write!(receipt_path, Jason.encode!(receipt, pretty: true))

    history_entry = %{state: to_state, recorded_at: recorded_at, receipt_path: receipt_path}
    {:ok, %Claim{claim | state: to_state, history: claim.history ++ [history_entry]}}
  end

  @doc """
  Real, independent replay verification for a claim's own evidence chain --
  thin wrapper over `BeamPM.ReceiptChain.verify/2` scoped to this claim's
  `chain_id`. Returns whatever `ReceiptChain.verify/2` returns (walks every
  receipt, recomputes every hash link, reports the first break if any).
  """
  @spec verify(t(), String.t()) :: term()
  def verify(%Claim{} = claim, receipts_dir \\ "receipts/eds") do
    ReceiptChain.verify(receipts_dir, "eds." <> claim.id)
  end
end
