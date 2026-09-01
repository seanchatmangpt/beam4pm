#!/usr/bin/env elixir
# rename_function_preflight_guard.exs -- B4PM-1704
#
# Pre-flight AST guard for `Igniter.Refactors.Rename.rename_function/4`
# (invoked via `mix igniter.refactor.rename_function`). Per
# docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4,
# `rename_function/4` has two real, reproduced bugs against idiomatically
# styled Elixir source:
#
#   (a) parenless zero-arity def (`def name do ... end`) -- Elixir
#       represents this definition's AST `args` as `nil`, not `[]`, which
#       crashes the library's `length(args) == arity` guard with an
#       uncaught `ArgumentError` (BUILD_BROKEN).
#
#   (b) guarded def (`def name(x) when guard do ... end`) -- the function
#       name sits one level deeper, inside a `:when`-wrapper AST node, than
#       the library's `{^old_function, _, args}` pattern matches. The
#       definition itself is silently left unrenamed while internal call
#       sites referencing the same name ARE renamed -- a real, silent
#       partial rename with no error surfaced (PARTIAL_ALIVE).
#
# This script inspects the real AST of a target function's definition in a
# given source file BEFORE any `rename_function`-based automation is
# permitted to run against it, and refuses (non-zero exit, typed message
# naming the matched shape) if either known-bad shape is present. It is a
# read-only static check: it never invokes `mix igniter.refactor.*` and
# never modifies the target file.
#
# Usage:
#   elixir scripts/rename_function_preflight_guard.exs <file> <Module> <function_name> <arity>
#
# Example:
#   elixir scripts/rename_function_preflight_guard.exs \
#     lib/beam4pm_process_governor.ex Beam4pmProcessGovernor contracts 0
#
# Exit codes:
#   0 -- permitted: target def matches neither known-bad shape (or was not
#        found in the file at all -- nothing for rename_function to break).
#   1 -- refused: shape (a), parenless zero-arity def, matched.
#   2 -- refused: shape (b), guarded def, matched.
#   64 -- usage error (bad arguments / unreadable / unparsable file).

defmodule B4pm1704.RenameFunctionPreflightGuard do
  @moduledoc false

  def main(argv) do
    case argv do
      [file, module_str, function_str, arity_str] ->
        run(file, module_str, function_str, arity_str)

      _ ->
        usage_error("expected exactly 4 arguments: <file> <Module> <function_name> <arity>")
    end
  end

  defp run(file, module_str, function_str, arity_str) do
    target_function = String.to_atom(function_str)

    target_arity =
      case Integer.parse(arity_str) do
        {n, ""} when n >= 0 -> n
        _ -> usage_error("arity must be a non-negative integer, got: #{inspect(arity_str)}")
      end

    source =
      case File.read(file) do
        {:ok, contents} -> contents
        {:error, reason} -> usage_error("could not read file #{inspect(file)}: #{inspect(reason)}")
      end

    ast =
      try do
        Code.string_to_quoted!(source, file: file)
      rescue
        e -> usage_error("could not parse #{inspect(file)} as Elixir source: #{Exception.message(e)}")
      end

    defs = find_matching_defs(ast, target_function, target_arity)

    case classify(defs) do
      :shape_a ->
        IO.puts(:stderr, """
        REFUSED [shape (a): parenless zero-arity def]
        Target: #{module_str}.#{function_str}/#{target_arity}
        File:   #{file}

        The target function is defined with Elixir's parenless zero-arity
        form (`def #{function_str} do ... end`). Elixir represents this
        definition's AST `args` as `nil`, not `[]`, which crashes
        `Igniter.Refactors.Rename.rename_function/4`'s `length(args) ==
        arity` guard with an uncaught `ArgumentError` -- BUILD_BROKEN per
        docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4,
        root cause (a). rename_function-based automation is refused
        against this target. Rewrite the definition with explicit
        parentheses (`def #{function_str}() do ... end`) before retrying,
        or perform the rename by hand.
        """)

        System.halt(1)

      :shape_b ->
        IO.puts(:stderr, """
        REFUSED [shape (b): guarded def]
        Target: #{module_str}.#{function_str}/#{target_arity}
        File:   #{file}

        The target function's definition carries a `when` guard clause
        (`def #{function_str}(...) when ... do ... end`). Elixir represents
        this as `{:def, _, [{:when, _, [{name, _, args}, guard]}, body]}`
        -- the function name sits one level deeper than
        `Igniter.Refactors.Rename`'s `{^old_function, _, args}` pattern
        matches. The definition itself is left completely untouched while
        internal call sites referencing the same name ARE renamed: a real,
        silent, inconsistent partial rename with no error surfaced --
        PARTIAL_ALIVE per
        docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4,
        root cause (b). rename_function-based automation is refused
        against this target. Rename by hand, or restructure the guard out
        of the def head before retrying.
        """)

        System.halt(2)

      :ok ->
        IO.puts("""
        PERMITTED
        Target: #{module_str}.#{function_str}/#{target_arity}
        File:   #{file}
        Matches neither known-bad shape (a) nor (b).
        """)

        System.halt(0)
    end
  end

  # Walks the AST collecting every `def`/`defp` signature node whose name
  # and (best-effort) arity match the target, returning the raw signature
  # AST nodes so `classify/1` can distinguish the two known-bad shapes from
  # a normal, guard-free, parenthesized definition.
  defp find_matching_defs(ast, target_function, target_arity) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {def_kind, _meta, [signature, _body]} = node, acc when def_kind in [:def, :defp] ->
          if matches?(signature, target_function, target_arity) do
            {node, [signature | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  # Guarded def: `def name(x) when guard do ... end`.
  defp matches?({:when, _, [{name, _, args}, _guard]}, target_function, target_arity) do
    name == target_function and arity_of(args) == target_arity
  end

  # Parenless zero-arity def: `def name do ... end` -- args is `nil`.
  defp matches?({name, _, nil}, target_function, target_arity) do
    name == target_function and target_arity == 0
  end

  # Normal def: `def name(a, b) do ... end` (including zero-arity `def
  # name() do ... end`, whose args is `[]`, not `nil`).
  defp matches?({name, _, args}, target_function, target_arity) when is_list(args) do
    name == target_function and length(args) == target_arity
  end

  defp matches?(_signature, _target_function, _target_arity), do: false

  defp arity_of(nil), do: 0
  defp arity_of(args) when is_list(args), do: length(args)

  defp classify(defs) do
    cond do
      Enum.any?(defs, &parenless_zero_arity?/1) -> :shape_a
      Enum.any?(defs, &guarded?/1) -> :shape_b
      true -> :ok
    end
  end

  defp parenless_zero_arity?({_name, _, nil}), do: true
  defp parenless_zero_arity?(_), do: false

  defp guarded?({:when, _, [_head, _guard]}), do: true
  defp guarded?(_), do: false

  defp usage_error(message) do
    IO.puts(:stderr, "USAGE ERROR: #{message}")

    IO.puts(:stderr, """
    Usage: elixir scripts/rename_function_preflight_guard.exs <file> <Module> <function_name> <arity>
    """)

    System.halt(64)
  end
end

B4pm1704.RenameFunctionPreflightGuard.main(System.argv())
