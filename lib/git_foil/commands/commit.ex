defmodule GitFoil.Commands.Commit do
  @moduledoc """
  Commit GitFoil configuration changes.

  This is a convenience command that stages and commits .gitattributes
  with an appropriate commit message.
  """

  @doc """
  Commit .gitattributes changes.

  ## Options
  - `:message` - Custom commit message (optional)
  """
  def run(opts \\ []) do
    custom_message = Keyword.get(opts, :message)

    IO.puts("📝  Staging .gitattributes...")

    case System.cmd("git", ["add", ".gitattributes"], stderr_to_stdout: true) do
      {_, 0} ->
        commit_message = custom_message || "Configure GitFoil encryption"
        IO.puts("💾  Committing changes...")

        case System.cmd("git", ["commit", "-m", commit_message], stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, format_success(output, commit_message)}

          {error, _} ->
            # Check if it's just "nothing to commit" (git has multiple phrasings)
            nothing_to_commit? =
              String.contains?(error, "nothing to commit") or
              String.contains?(error, "no changes added to commit")

            if nothing_to_commit? do
              {:ok, """
              ✅  Nothing to commit

              .gitattributes is already committed or hasn't changed.
              """}
            else
              {:error, """
              Failed to commit:
              #{String.trim(error)}

              💡  Try committing manually:
                 git add .gitattributes
                 git commit -m "#{commit_message}"
              """}
            end
        end

      {error, _} ->
        {:error, """
        Failed to stage .gitattributes:
        #{String.trim(error)}

        💡  Make sure .gitattributes exists and you're in a git repository.
        """}
    end
  end

  defp format_success(git_output, _message) do
    output = String.trim(git_output)

    # Parse git output to extract summary and file list
    lines = String.split(output, "\n")

    # First line is commit summary: [branch hash] message
    {summary_line, file_lines} = case lines do
      [summary | rest] -> {summary, rest}
      [] -> {"", []}
    end

    # Count files and get stats line
    file_count = Enum.count(file_lines, &String.contains?(&1, "create mode"))
    stats_line = Enum.find(file_lines, &String.contains?(&1, "files changed"))

    # Format based on file count
    formatted_details = case file_count do
      0 ->
        # No files in output (might be just text changes)
        output

      n when n <= 10 ->
        # Show all files (concise)
        output

      n ->
        # Truncate file list, show summary
        truncated_files = file_lines
        |> Enum.filter(&String.contains?(&1, "create mode"))
        |> Enum.take(5)
        |> Enum.join("\n")

        remaining = n - 5

        """
        #{summary_line}
        #{stats_line}
        #{truncated_files}
         ... and #{remaining} more files

        💡  Run 'git show' to see all #{n} files
        """
    end

    """
    ✅  Committed successfully!

    #{String.trim(formatted_details)}

    Your encryption configuration is now tracked in git.
    """
  end
end
