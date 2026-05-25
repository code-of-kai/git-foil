defmodule GitFoil.Commands.GitattributesExclusionsTest do
  @moduledoc """
  Regression test for the `.gitignore`-encryption bug (fixed in 1.0.9).

  Background: GitFoil emits a `.gitattributes` that wires its clean/smudge
  filter onto file patterns. Git reads `.gitignore` from the working tree as
  plain text — if the filter applies to `.gitignore`, the working-tree copy
  ends up ciphertext, and git's ignore-rule parser sees zero rules. This
  silently disables all gitignore rules in the repo, producing tens of
  thousands of "untracked" build artifacts.

  The fix is to always exclude `.gitignore` (and nested `**/.gitignore`)
  from the filter — same pattern as the existing `.gitattributes -filter`
  exclusion. This test pins that behaviour so it can't regress.
  """

  use ExUnit.Case, async: true

  alias GitFoil.Commands.Init

  describe "build_gitattributes_content/1 — .gitignore exclusions" do
    test "excludes .gitignore from the filter" do
      content = Init.build_gitattributes_content(["** filter=gitfoil"])
      assert content =~ ~r/^\.gitignore -filter$/m
    end

    test "excludes nested **/.gitignore from the filter" do
      content = Init.build_gitattributes_content(["** filter=gitfoil"])
      assert content =~ ~r/^\*\*\/\.gitignore -filter$/m
    end

    test ".gitattributes is also excluded (sanity check on existing behaviour)" do
      content = Init.build_gitattributes_content(["** filter=gitfoil"])
      assert content =~ ~r/^\.gitattributes -filter$/m
    end

    test "exclusions come after the pattern lines so they win precedence" do
      content = Init.build_gitattributes_content(["** filter=gitfoil"])

      pattern_idx = :binary.match(content, "** filter=gitfoil") |> elem(0)
      gitignore_excl_idx = :binary.match(content, ".gitignore -filter") |> elem(0)

      assert gitignore_excl_idx > pattern_idx,
             "exclusions must appear after patterns so git applies them last"
    end

    test "works with the :everything preset" do
      content = Init.build_gitattributes_content(["** filter=gitfoil"])
      assert content =~ ".gitignore -filter"
      assert content =~ "**/.gitignore -filter"
    end

    test "works with the :secrets preset" do
      patterns = [
        "*.env filter=gitfoil",
        "secrets/** filter=gitfoil",
        "*.key filter=gitfoil"
      ]

      content = Init.build_gitattributes_content(patterns)
      assert content =~ ".gitignore -filter"
      assert content =~ "**/.gitignore -filter"
    end
  end
end
