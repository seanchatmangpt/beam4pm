defmodule B4pm1704Fixtures.ShapeOkNormalDef do
  @moduledoc """
  Fixture matching neither known-bad shape: a normal parenthesized,
  unguarded `def name(x) do ... end`. `Igniter.Refactors.Rename`'s
  `{^old_function, _, args}` pattern matches this directly, so
  `rename_function/4` renames it correctly and the pre-flight guard must
  permit it.
  """

  def read(id) do
    {:ok, id}
  end
end
