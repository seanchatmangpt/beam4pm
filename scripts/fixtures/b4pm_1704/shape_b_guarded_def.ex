defmodule B4pm1704Fixtures.ShapeBGuardedDef do
  @moduledoc """
  Fixture reproducing known-bad shape (b) from
  docs/jira/v26.8.31/03-known-defects-and-mitigations.md Defect 4 root
  cause (b): a guarded `def`. Elixir represents this definition's AST as
  `{:def, _, [{:when, _, [{name, _, args}, guard]}, body]}` -- the function
  name sits one level deeper than `Igniter.Refactors.Rename`'s
  `{^old_function, _, args}` pattern matches, so the definition itself is
  silently left unrenamed while call sites ARE renamed (a partial,
  inconsistent rename with no error surfaced).
  """

  def read(id) when is_atom(id) do
    {:ok, id}
  end

  def caller(id) do
    with {:ok, value} <- read(id) do
      value
    end
  end
end
