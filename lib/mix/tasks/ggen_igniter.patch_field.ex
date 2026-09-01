# Hand-authored manufacturing-time mix task (not ggen output). Deliberately
# NOT folded into scripts/igniter_sync.sh -- this is the alternative,
# single-record codemod manufacturing path B4PM-1702 adds alongside the
# existing full-EEx-re-render path (`mix ggen_igniter.sync`), not a
# replacement for it.
defmodule Mix.Tasks.GgenIgniter.PatchField do
  @moduledoc """
  `mix ggen_igniter.patch_field` -- B4PM-1702 single-record-patch codemod.

  Scoped to exactly one admitted `bpm:RecordType` (`dfg_edge`, module
  `BeamPM.Types.DfgEdge`, file `lib/beam4pm_types.ex`). Adds the
  `edge_weight` field (float, required, order 4 -- see the `bpm:dfg_edge_rt`
  admission in `ontology.ttl`) to that ONE module via
  `GgenIgniter.PatchField.patch/4` (`Igniter.Code.Module.move_to_defmodule/2`
  + `Igniter.Code.Function.move_to_def/2` under the hood), leaving every
  other admitted record type's module in the file untouched.

  Run with no args -- this task's field/module scope is fixed to the one
  record this story picked, matching the acceptance criteria's "scoped to
  exactly one admitted bpm:RecordType" requirement.
  """
  use Mix.Task

  @shortdoc "B4PM-1702: patch the dfg_edge record's edge_weight field via Igniter codemod"

  @target_file "lib/beam4pm_types.ex"

  @existing_fields [
    %{name: "source_activity", type: "string", required?: true, order: 1},
    %{name: "target_activity", type: "string", required?: true, order: 2},
    %{name: "frequency", type: "integer", required?: true, order: 3}
  ]

  @new_field %{name: "edge_weight", type: "float", required?: true, order: 4}

  @impl Mix.Task
  def run(_argv) do
    source = File.read!(@target_file)

    case GgenIgniter.PatchField.patch(
           source,
           BeamPM.Types.DfgEdge,
           @existing_fields,
           @new_field
         ) do
      {:ok, patched} ->
        File.write!(@target_file, patched)
        Mix.shell().info("ggen_igniter.patch_field: patched #{@target_file} (BeamPM.Types.DfgEdge, +edge_weight)")

      {:error, reason} ->
        Mix.raise("ggen_igniter.patch_field: codemod failed: #{inspect(reason)}")
    end
  end
end
