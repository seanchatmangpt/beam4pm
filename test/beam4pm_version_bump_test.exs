defmodule Beam4pmVersionBumpTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project/1` seeded with beam4pm's own
  real `mix.exs` and `src/beam4pm.app.src` content read straight off disk,
  driving `Mix.Tasks.Beam4pm.VersionBump.igniter/1` directly. Every assertion
  reads the real resulting file content back (`Rewrite.Source.get(:content)`),
  never "was `Igniter.Project.MixProject.update/4` called."

  Implements story B4PM-1703's acceptance bullets:
    1. running the task with a target version updates both files, verified by
       reading actual post-run content;
    2. the target version chosen ("26.8.28") is the same two-dot-plus string
       proven in docs/jira/v26.8.31/03-known-defects-and-mitigations.md
       (defect #2) to break the library's own undocumented `{:code,
       new_version}` example against `Sourceror.parse_string!/1`;
    3. a regression test asserts removing the `inspect/1` wrap reproduces that
       documented crash against this same real fixture;
    4. the task refuses (typed `VersionMismatchError`, not a silent no-op) if
       the two files' versions do not already match before the bump.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Beam4pm.VersionBump

  @mix_exs_real File.read!(Path.join(File.cwd!(), "mix.exs"))
  @app_src_real File.read!(Path.join(File.cwd!(), "src/beam4pm.app.src"))

  defp test_igniter(files, new_version) do
    igniter = Igniter.Test.test_project(files: files)
    %{igniter | args: %Igniter.Mix.Task.Args{positional: [new_version: new_version]}}
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  describe "mix beam4pm.version_bump (real beam4pm mix.exs + app.src fixtures)" do
    test "bumps both mix.exs's version: and app.src's {vsn, ...} in the same invocation" do
      # "0.1.1" as a sanity-check target -- a normal two-dot semver bump.
      igniter =
        %{"mix.exs" => @mix_exs_real, "src/beam4pm.app.src" => @app_src_real}
        |> test_igniter("0.1.1")
        |> VersionBump.igniter()

      mix_exs = content(igniter, "mix.exs")
      app_src = content(igniter, "src/beam4pm.app.src")

      assert mix_exs =~ ~s(version: "0.1.1")
      refute mix_exs =~ ~s(version: "0.1.0")
      assert app_src =~ ~s({vsn, "0.1.1"})
      refute app_src =~ ~s({vsn, "0.1.0"})
    end

    test "bumps to a three-component target version that reproduces defect #2 if inspect/1 were omitted" do
      # "26.8.28" is the exact string docs/jira/v26.8.31/03-known-defects-and-mitigations.md
      # names as proven to break `Sourceror.parse_string!/1` against the
      # library's own undocumented `{:code, new_version}` example -- chosen
      # here specifically because it exercises that path, not an arbitrary
      # bump target.
      igniter =
        %{"mix.exs" => @mix_exs_real, "src/beam4pm.app.src" => @app_src_real}
        |> test_igniter("26.8.28")
        |> VersionBump.igniter()

      mix_exs = content(igniter, "mix.exs")
      app_src = content(igniter, "src/beam4pm.app.src")

      assert mix_exs =~ ~s(version: "26.8.28")
      assert app_src =~ ~s({vsn, "26.8.28"})
    end

    test "refuses (typed VersionMismatchError, not a silent no-op) when mix.exs and app.src have already drifted apart" do
      # Derive the drift from whatever app.src's real current {vsn, ...} is
      # (a literal "0.1.0" target goes silently inert -- and the refute
      # below then passes vacuously -- the moment the real repo's version
      # moves past that literal, as it has since this test was authored).
      [_, real_vsn] = Regex.run(~r/\{vsn,\s*"([^"]+)"\}/, @app_src_real)
      drifted_app_src = String.replace(@app_src_real, ~s({vsn, "#{real_vsn}"}), ~s({vsn, "0.0.0-drifted"}))
      refute drifted_app_src == @app_src_real

      igniter = test_igniter(%{"mix.exs" => @mix_exs_real, "src/beam4pm.app.src" => drifted_app_src}, "0.1.1")

      assert_raise VersionBump.VersionMismatchError, ~r/do not already match/, fn ->
        VersionBump.igniter(igniter)
      end
    end
  end

  describe "regression: reproduces defect #2 when the inspect/1 wrap is removed" do
    test "un-wrapped {:code, new_version} against real beam4pm mix.exs raises the documented Sourceror.parse_string!/1 crash" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => @mix_exs_real})

      # Same two-dot-plus target version as the passing test above, same real
      # fixture, only the inspect/1 wrap removed -- the documented base
      # library example (`{:ok, {:code, new_version}}`, no inspect/1) run
      # against beam4pm's real "0.1.0"-shaped mix.exs.
      new_version = "26.8.28"

      assert_raise SyntaxError, fn ->
        Igniter.Project.MixProject.update(igniter, :project, [:version], fn _zipper ->
          {:ok, {:code, new_version}}
        end)
      end
    end
  end
end
