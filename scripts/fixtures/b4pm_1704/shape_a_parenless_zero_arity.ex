defmodule B4pm1704Fixtures.ShapeAParenlessZeroArity do
  @moduledoc """
  Fixture reproducing known-bad shape (a) from
  docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4 root
  cause (a): a parenless zero-arity `def`. Elixir represents this
  definition's AST `args` as `nil`, not `[]`, which crashes
  `Igniter.Refactors.Rename.rename_function/4`'s `length(args) == arity`
  guard with an `ArgumentError`.
  """

  def verify do
    :ok
  end
end
