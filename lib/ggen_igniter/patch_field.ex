# B4PM-1702: single-record-patch codemod. Hand-authored manufacturing input
# (this file is NOT itself ggen output -- it IS the alternative manufacturing
# path to a full EEx re-render, so it carries no provenance marker header and
# is a legitimate hand-edit surface per CLAUDE.md's source-authority
# doctrine). NOTE: never spell out that marker's own exact phrase inside
# this file's first 3 lines -- scripts/gate_m2_check.sh's find_manufactured
# does a case-insensitive substring match on those lines and would (and once
# did, in exactly this file) misclassify this hand-authored module as
# manufactured output, deleting it mid-regeneration.
defmodule GgenIgniter.PatchField do
  @moduledoc """
  Single-record-patch codemod: an alternative manufacturing path to a full
  `ggen sync run` re-render, scoped to exactly ONE admitted `bpm:RecordType`
  (here: `dfg_edge`, module `BeamPM.Types.DfgEdge` in `lib/beam4pm_types.ex`,
  the file ggen's `beam4pm_types.ex.tmpl` manufactures from the ontology's
  admitted `bpm:RecordType` / `bpm:Field` graph).

  Given one field addition on that single record type, this module:

    1. Locates the existing generated module via
       `Igniter.Code.Module.move_to_defmodule/2`.
    2. Locates the target function (`def new/1`) within that module via
       `Igniter.Code.Function.move_to_def/2` (the generic, name-unconstrained
       form -- `BeamPM.Types.DfgEdge` has exactly one `def`, so this
       unambiguously anchors on it) -- this proves the codemod is AST-aware
       (it fails loudly if the module or its `def` ever goes missing) rather
       than a blind string-splice.
    3. Applies a targeted AST patch: replaces the whole `defmodule ... end`
       node's source span with a freshly-rendered module body that mirrors
       `beam4pm_types.ex.tmpl`'s exact Tera-template field-rendering rules
       for `defstruct`, `@type`, and the `new/1` `cond` clauses/map, with the
       new field's line spliced into each of those three field-driven
       sections. Mirroring the template (rather than trying to express
       Tera's per-field, per-loop-position joining/comma logic as three
       separate fine-grained Sourceror sub-edits) is what makes the codemod
       output byte-identical to a full `ggen sync run` re-render for the
       touched module -- both paths compute the same deterministic string
       from the same `(record, fields)` shape.

  Every OTHER `defmodule BeamPM.Types.*` block in the file is left
  byte-for-byte untouched -- the codemod's Sourceror-node span replacement
  only ever rewrites the exact span the located `defmodule` occupied.
  """

  alias Sourceror.Zipper

  @type field :: %{
          name: String.t(),
          type: String.t(),
          required?: boolean(),
          order: pos_integer()
        }

  @doc """
  Adds `new_field` to the `module` found in `source` (the full text of
  `lib/beam4pm_types.ex`), returning the patched full source text.

  `existing_fields` must be given in the same field-order the module's
  current `defstruct`/`@type`/`new/1` already reflect (i.e. the fields the
  ontology already admits for this record, BEFORE `new_field`), so the
  freshly-rendered replacement body is a legitimate 1:1 splice, not a guess.
  """
  @spec patch(String.t(), module(), [field()], field()) ::
          {:ok, String.t()} | {:error, term()}
  def patch(source, module, existing_fields, new_field) when is_binary(source) do
    zipper = source |> Sourceror.parse_string!() |> Zipper.zip()

    with {:ok, defmodule_zipper} <- Igniter.Code.Module.move_to_defmodule(zipper, module),
         {:ok, _def_zipper} <-
           Igniter.Code.Function.move_to_def(defmodule_zipper, target: :at),
         {:ok, range} <- get_range(defmodule_zipper.node),
         {:ok, moduledoc} <- extract_moduledoc(source, range) do
      all_fields = Enum.sort_by(existing_fields ++ [new_field], & &1.order)
      rendered = render_module(module, moduledoc, all_fields)
      {:ok, splice(source, range, rendered)}
    else
      :error -> {:error, :module_or_function_not_found}
      other -> other
    end
  end

  # Sourceror.get_range/1 returns %{start: [line: _, column: _], end: [line: _, column: _]}
  # (keyword lists, not maps) -- normalize to plain %{line:, column:} maps here
  # so every downstream function works with one consistent shape.
  defp get_range(node) do
    case Sourceror.get_range(node) do
      %{start: start, end: fin} ->
        {:ok, %{start: %{line: start[:line], column: start[:column]}, end: %{line: fin[:line], column: fin[:column]}}}

      _ ->
        {:error, :no_range}
    end
  end

  # The moduledoc string isn't reachable off the defmodule zipper as plain
  # text without re-walking to the @moduledoc attribute's literal argument;
  # simplest robust extraction is a direct regex over the located span's
  # own source text (still Igniter/Sourceror-located -- range comes from the
  # real AST node, not a blind file-wide grep).
  defp extract_moduledoc(source, %{start: start, end: fin}) do
    span = source_span(source, start, fin)

    case Regex.run(~r/@moduledoc\s+"((?:[^"\\]|\\.)*)"/s, span) do
      [_, doc] -> {:ok, doc}
      nil -> {:error, :no_moduledoc}
    end
  end

  defp source_span(source, %{line: l1, column: c1}, %{line: l2, column: c2}) do
    lines = String.split(source, "\n")

    lines
    |> Enum.slice((l1 - 1)..(l2 - 1))
    |> case do
      [only] ->
        String.slice(only, (c1 - 1)..(c2 - 2)//1)

      [first | rest] ->
        {last_but_one, [last]} = Enum.split(rest, -1)
        first_part = String.slice(first, (c1 - 1)..-1//1)
        last_part = String.slice(last, 0..(c2 - 2)//1)
        Enum.join([first_part | last_but_one] ++ [last_part], "\n")
    end
  end

  defp splice(source, %{start: %{line: l1, column: c1}, end: %{line: l2, column: c2}}, replacement) do
    lines = String.split(source, "\n")
    before_lines = Enum.slice(lines, 0, l1 - 1)
    after_lines = Enum.slice(lines, l2, length(lines))

    first_line = Enum.at(lines, l1 - 1)
    last_line = Enum.at(lines, l2 - 1)
    prefix = String.slice(first_line, 0, c1 - 1)
    suffix = String.slice(last_line, (c2 - 1)..-1//1)

    Enum.join(before_lines ++ [prefix <> replacement <> suffix] ++ after_lines, "\n")
  end

  # Mirrors vendor/ggen-marketplace/packs/beam4pm-process-model-pack/
  # templates/beam4pm_types.ex.tmpl's per-record Tera block EXACTLY (same
  # field-order iteration, same defstruct/@type/cond/map join rules).
  defp render_module(module, doc, fields) do
    defstruct_line =
      "defstruct [" <> Enum.map_join(fields, ", ", &(":" <> &1.name)) <> "]"

    type_lines =
      fields
      |> Enum.map(fn f ->
        "    #{f.name}: #{elixir_type(f.type)} | nil"
      end)
      |> Enum.join(",\n")

    missing_clauses =
      fields
      |> Enum.filter(& &1.required?)
      |> Enum.map_join("", fn f ->
        "      not Map.has_key?(attrs, :#{f.name}) -> {:error, {:missing_field, :#{f.name}}}\n"
      end)

    map_lines =
      fields
      |> Enum.map(fn f -> "          #{f.name}: Map.get(attrs, :#{f.name})" end)
      |> Enum.join(",\n")

    """
    defmodule #{module_string(module)} do
      @moduledoc "#{doc}"

      #{defstruct_line}

      @type t :: %__MODULE__{
    #{type_lines}
      }

      @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, atom()}}
      def new(attrs) when is_map(attrs) do
        cond do
    #{missing_clauses}      true ->
            {:ok, %__MODULE__{
    #{map_lines}
            }}
        end
      end
    end\
    """
  end

  defp module_string(module), do: "BeamPM.Types." <> (module |> Module.split() |> List.last())

  defp elixir_type("string"), do: "String.t()"
  defp elixir_type("integer"), do: "integer()"
  defp elixir_type("float"), do: "float()"
  defp elixir_type("boolean"), do: "boolean()"
  defp elixir_type("datetime"), do: "String.t()"
  defp elixir_type("atom"), do: "atom()"
  defp elixir_type("list_string"), do: "[String.t()]"
  defp elixir_type("map"), do: "map()"
end
