defmodule GitFoil.Commands.Doctor do
  @moduledoc """
  Diagnostics for an existing GitFoil-managed repository.

  Currently checks for the `.gitignore`-encryption bug (GitFoil ≤1.0.8):
  if `.gitattributes` applies the gitfoil filter to `.gitignore` files,
  git silently parses ciphertext as plaintext and applies zero ignore
  rules, producing massive untracked-file counts and slow `git status`.

  Run with: `git-foil doctor`

  Exits 0 if healthy, 1 if any check failed, with a remediation note.
  """

  @gitignore_excl ".gitignore -filter"
  @nested_gitignore_excl "**/.gitignore -filter"

  def run(_opts \\ []) do
    case File.read(".gitattributes") do
      {:ok, content} ->
        diagnose(content)

      {:error, :enoent} ->
        {:ok,
         """
         ℹ️  No .gitattributes in the current directory.

         If this isn't a GitFoil-managed repo, that's expected. Otherwise
         run 'git-foil init' first.
         """}

      {:error, reason} ->
        {:error, "Failed to read .gitattributes: #{inspect(reason)}"}
    end
  end

  defp diagnose(content) do
    has_filter? = String.contains?(content, "filter=gitfoil")
    has_gitignore_excl? = content_has_line?(content, @gitignore_excl)
    has_nested_excl? = content_has_line?(content, @nested_gitignore_excl)

    cond do
      not has_filter? ->
        {:ok, "✅  No GitFoil filter configured in .gitattributes — nothing to check."}

      has_gitignore_excl? and has_nested_excl? ->
        {:ok, "✅  .gitattributes correctly excludes .gitignore from the GitFoil filter."}

      true ->
        missing =
          []
          |> maybe_add(not has_gitignore_excl?, @gitignore_excl)
          |> maybe_add(not has_nested_excl?, @nested_gitignore_excl)
          |> Enum.join("\n    ")

        {:error,
         """
         ❌  .gitattributes is missing .gitignore exclusion(s).

         GitFoil's filter is applied to .gitignore files, which encrypts
         them in the working tree. Git's ignore-rule parser reads
         .gitignore as plain text, so this silently disables all ignore
         rules — every build artifact will appear as untracked.

         Add the following line(s) after your existing exclusions, before
         any catch-all `** filter=gitfoil` pattern wins:

             #{missing}

         Then decrypt the affected .gitignore files (`git-foil smudge`
         on each) and commit the result.
         """}
    end
  end

  defp content_has_line?(content, expected) do
    content
    |> String.split("\n")
    |> Enum.any?(fn line -> String.trim(line) == expected end)
  end

  defp maybe_add(list, true, line), do: list ++ [line]
  defp maybe_add(list, false, _line), do: list
end
