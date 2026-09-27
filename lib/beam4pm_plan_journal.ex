# Hand-authored (not ggen-generated). Lane W3 (docs/jira/v26.9.25/_LANES-strategic-loop.md):
# first real writers for the generated PlanLineage / PlanMemory Ash
# resources — derivation/supersession linkage across plan generations and
# archival of superseded plans as historical evidence.
defmodule BeamPM.PlanJournal do
  @moduledoc """
  Plan lineage + plan memory journal.

  `record_lineage/2` records that `new_plan_ref` supersedes/derives from
  `old_plan_ref`: one `BeamPM.Ash.Resources.PlanLineage` row with
  `plan_id = new_plan_ref`, `parent_plan_id = old_plan_ref`, and
  `lineage_hash = sha256(old_plan_ref <> "->" <> new_plan_ref)` as full
  lowercase hex (this repo's lineage formula for this module; pinned here
  and tested against its exact value).

  `archive/2` archives a superseded plan into
  `BeamPM.Ash.Resources.PlanMemory` as historical evidence, with
  `memory_hash = sha256(plan_ref <> ":" <> evidence_hash)` full lowercase
  hex. NO authority semantics — mirroring the PlanMemory moduledoc guard:
  archived evidence is reusable history, never converted into current
  authority for the plan that produced it.

  Both return `{:ok, record}` | `{:error, reason}`; empty or non-binary
  refs refuse typed (`{:error, {:invalid_argument, key}}`).
  """

  @spec record_lineage(term(), term()) ::
          {:ok, BeamPM.Ash.Resources.PlanLineage.t()} | {:error, term()}
  def record_lineage(old_plan_ref, new_plan_ref) do
    with :ok <- valid_ref(old_plan_ref, :old_plan_ref),
         :ok <- valid_ref(new_plan_ref, :new_plan_ref) do
      BeamPM.Ash.Resources.PlanLineage
      |> Ash.Changeset.for_create(:create, %{
        plan_id: new_plan_ref,
        parent_plan_id: old_plan_ref,
        lineage_hash: lineage_hash(old_plan_ref, new_plan_ref)
      })
      |> Ash.create()
      |> case do
        {:ok, record} -> {:ok, record}
        {:error, error} -> {:error, {:create_failed, error}}
      end
    end
  end

  @doc "Pinned lineage formula: sha256(old <> \"->\" <> new), lowercase hex."
  @spec lineage_hash(String.t(), String.t()) :: String.t()
  def lineage_hash(old_plan_ref, new_plan_ref)
      when is_binary(old_plan_ref) and is_binary(new_plan_ref) do
    :crypto.hash(:sha256, old_plan_ref <> "->" <> new_plan_ref)
    |> Base.encode16(case: :lower)
  end

  @spec archive(term(), term()) ::
          {:ok, BeamPM.Ash.Resources.PlanMemory.t()} | {:error, term()}
  def archive(plan_ref, evidence_hash) do
    with :ok <- valid_ref(plan_ref, :plan_ref),
         :ok <- valid_ref(evidence_hash, :evidence_hash) do
      BeamPM.Ash.Resources.PlanMemory
      |> Ash.Changeset.for_create(:create, %{
        plan_id: plan_ref,
        evidence_hash: evidence_hash,
        memory_hash: memory_hash(plan_ref, evidence_hash)
      })
      |> Ash.create()
      |> case do
        {:ok, record} -> {:ok, record}
        {:error, error} -> {:error, {:create_failed, error}}
      end
    end
  end

  @doc "Pinned memory formula: sha256(plan_ref <> \":\" <> evidence_hash), lowercase hex."
  @spec memory_hash(String.t(), String.t()) :: String.t()
  def memory_hash(plan_ref, evidence_hash)
      when is_binary(plan_ref) and is_binary(evidence_hash) do
    :crypto.hash(:sha256, plan_ref <> ":" <> evidence_hash)
    |> Base.encode16(case: :lower)
  end

  defp valid_ref(value, _key) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp valid_ref(_other, key), do: {:error, {:invalid_argument, key}}
end
