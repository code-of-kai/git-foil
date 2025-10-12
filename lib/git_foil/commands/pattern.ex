defmodule GitFoil.Commands.Pattern do
  @moduledoc """
  Manage GitFoil encryption patterns in .gitattributes.

  This module provides commands to configure which files should be encrypted
  by adding, removing, and listing patterns in the .gitattributes file.
  """

  alias GitFoil.Helpers.UIPrompts

  @doc """
  Interactive pattern configuration (same as init pattern selection).
  """
  def configure do
    IO.puts("\nWhich files should be encrypted?")
    IO.puts("[1] Everything (encrypt all files)")
    IO.puts("[2] Secrets only (*.env, secrets/**, *.key, *.pem, credentials.json)")
    IO.puts("[3] Environment files (*.env, .env.*)")
    IO.puts("[4] Custom patterns (interactive)")
    IO.puts("[5] Exit")
    IO.puts("")
    UIPrompts.print_separator()

    choice = safe_gets("\nChoice [1]: ")

    case choice do
      "" -> apply_preset(:everything)
      "1" -> apply_preset(:everything)
      "2" -> apply_preset(:secrets)
      "3" -> apply_preset(:env_files)
      "4" -> custom_patterns()
      "5" ->
        IO.puts("\n👋  Exited pattern configuration.")
        {:ok, ""}
      _ -> {:error, UIPrompts.invalid_choice_message(1..5)}
    end
  end

  @doc """
  Add a pattern to .gitattributes.

  ## Examples

      iex> GitFoil.Commands.Pattern.add("*.env")
      {:ok, "Added pattern: *.env filter=gitfoil"}
  """
  def add(pattern) when is_binary(pattern) do
    full_pattern = pattern <> " filter=gitfoil"

    case read_gitattributes() do
      {:ok, existing_content} ->
        if String.contains?(existing_content, full_pattern) do
          {:ok, "Pattern already exists: #{pattern}"}
        else
          new_content = existing_content <> full_pattern <> "\n"

          case File.write(".gitattributes", new_content) do
            :ok ->
              {:ok, """
              ✅  Added encryption pattern

              📝  Updated .gitattributes:
                 🔒  #{pattern} filter=gitfoil

              Git will encrypt files matching this pattern when you run 'git add' or 'git commit'.

              💡  Next step - commit your changes:
                 git-foil commit

                 Or use git directly:
                    git add .gitattributes
                    git commit -m "Add GitFoil pattern: #{pattern}"
              """}

            {:error, reason} ->
              {:error, "Failed to write .gitattributes: #{UIPrompts.format_error(reason)}"}
          end
        end

      {:error, :enoent} ->
        # Create new .gitattributes
        content = "# GitFoil - Quantum-resistant Git encryption\n" <> full_pattern <> "\n.gitattributes -filter\n"

        case File.write(".gitattributes", content) do
          :ok ->
            {:ok, """
            ✅  Added encryption pattern

            📝  Created .gitattributes:
               🔒  #{pattern} filter=gitfoil

            Git will encrypt files matching this pattern when you run 'git add' or 'git commit'.

            💡  Next step - commit your changes:
               git-foil commit

               Or use git directly:
                  git add .gitattributes
                  git commit -m "Configure GitFoil encryption"
            """}

          {:error, reason} ->
            {:error, "Failed to write .gitattributes: #{UIPrompts.format_error(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
    end
  end

  @doc """
  Remove a pattern from .gitattributes.

  This safely removes encryption from files matching the pattern by:
  1. Finding files that currently match the pattern
  2. Converting them from encrypted to plaintext in Git's storage
  3. Removing the pattern from .gitattributes

  ## Examples

      iex> GitFoil.Commands.Pattern.remove("*.env")
      {:ok, "Removed pattern: *.env"}
  """
  def remove(pattern) when is_binary(pattern) do
    case read_gitattributes() do
      {:ok, content} ->
        lines = String.split(content, "\n")
        pattern_to_remove = pattern <> " filter=gitfoil"

        new_lines = Enum.reject(lines, fn line ->
          String.trim(line) == pattern_to_remove
        end)

        if length(new_lines) == length(lines) do
          {:ok, "Pattern not found: #{pattern}"}
        else
          # Before removing the pattern, decrypt any files currently matching it
          with :ok <- decrypt_pattern_files(pattern) do
            new_content = Enum.join(new_lines, "\n")

            case File.write(".gitattributes", new_content) do
              :ok ->
                {:ok, """
                ✅  Removed encryption pattern

                📝  Updated .gitattributes:
                   🔓  #{pattern} (no longer encrypted)

                Files that were encrypted under this pattern have been converted
                to plaintext in Git's storage. They're now safe to checkout.

                💡  Next step - commit your changes:
                   git-foil commit

                   Or use git directly:
                      git add .gitattributes
                      git commit -m "Remove GitFoil pattern: #{pattern}"
                """}

              {:error, reason} ->
                {:error, "Failed to write .gitattributes: #{UIPrompts.format_error(reason)}"}
            end
          end
        end

      {:error, :enoent} ->
        {:error, ".gitattributes file not found"}

      {:error, reason} ->
        {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
    end
  end

  @doc """
  List all GitFoil patterns in .gitattributes.
  """
  def list do
    case read_gitattributes() do
      {:ok, content} ->
        patterns =
          content
          |> String.split("\n")
          |> Enum.filter(fn line ->
            String.contains?(line, "filter=gitfoil") and not String.starts_with?(String.trim(line), "#")
          end)
          |> Enum.map(&String.trim/1)

        if Enum.empty?(patterns) do
          {:ok, """
          📋  No encryption patterns configured

          💡  Get started:
             git-foil configure              # Interactive menu
             git-foil add-pattern "*.env"    # Add specific pattern
          """}
        else
          pattern_list =
            patterns
            |> Enum.map(fn pattern -> "   🔒  #{pattern}" end)
            |> Enum.join("\n")

          {:ok, """
          📋  Current encryption patterns:

          #{pattern_list}

          💡  Manage patterns:
             git-foil add-pattern "<pattern>"     # Add pattern
             git-foil remove-pattern "<pattern>"  # Remove pattern
          """}
        end

      {:error, :enoent} ->
        {:ok, """
        📋  No .gitattributes file found

        💡  Get started:
           git-foil configure              # Interactive menu
           git-foil add-pattern "*.env"    # Add specific pattern
        """}

      {:error, reason} ->
        {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
    end
  end

  @doc """
  Show help text for pattern syntax.
  """
  def help do
    {:ok, help_text()}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp apply_preset(preset) do
    patterns = get_preset_patterns(preset)
    content = build_content_from_patterns(patterns)

    case File.exists?(".gitattributes") do
      true ->
        # Append to existing file
        case File.read(".gitattributes") do
          {:ok, existing} ->
            new_content = existing <> "\n" <> content
            write_gitattributes_with_message(new_content, preset, :appended)

          {:error, reason} ->
            {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
        end

      false ->
        # Create new file
        full_content = "# GitFoil - Quantum-resistant Git encryption\n" <> content <> ".gitattributes -filter\n"
        write_gitattributes_with_message(full_content, preset, :created)
    end
  end

  defp get_preset_patterns(:everything), do: ["** filter=gitfoil"]

  defp get_preset_patterns(:secrets) do
    [
      "*.env filter=gitfoil",
      ".env.* filter=gitfoil",
      "secrets/** filter=gitfoil",
      "*.key filter=gitfoil",
      "*.pem filter=gitfoil",
      "**/credentials.json filter=gitfoil"
    ]
  end

  defp get_preset_patterns(:env_files) do
    [
      "*.env filter=gitfoil",
      ".env.* filter=gitfoil"
    ]
  end

  defp custom_patterns do
    IO.puts("\nEnter file patterns to encrypt (one per line).")
    IO.puts("Common examples:")
    IO.puts("  *.env           - All .env files")
    IO.puts("  secrets/**      - Everything in secrets/ directory")
    IO.puts("  *.key           - All .key files")
    IO.puts("\nPress Enter on empty line when done.")
    IO.puts("")
    UIPrompts.print_separator()

    patterns = collect_patterns([])

    if Enum.empty?(patterns) do
      {:ok, "No patterns added."}
    else
      content = build_content_from_patterns(patterns)

      case File.exists?(".gitattributes") do
        true ->
          case File.read(".gitattributes") do
            {:ok, existing} ->
              new_content = existing <> "\n" <> content
              write_gitattributes(new_content, "Added #{length(patterns)} custom pattern(s)")

            {:error, reason} ->
              {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
          end

        false ->
          full_content = "# GitFoil - Quantum-resistant Git encryption\n" <> content <> ".gitattributes -filter\n"
          write_gitattributes(full_content, "Added #{length(patterns)} custom pattern(s)")
      end
    end
  end

  defp collect_patterns(acc) do
    pattern = safe_gets("\nPattern: ")

    case pattern do
      "" ->
        Enum.reverse(acc)

      _ ->
        full_pattern = pattern <> " filter=gitfoil"
        collect_patterns([full_pattern | acc])
    end
  end

  defp build_content_from_patterns(patterns) do
    Enum.join(patterns, "\n") <> "\n"
  end

  defp read_gitattributes do
    File.read(".gitattributes")
  end

  defp write_gitattributes(content, success_message) do
    case File.write(".gitattributes", content) do
      :ok ->
        {:ok, "✅  #{success_message}"}

      {:error, reason} ->
        {:error, "Failed to write .gitattributes: #{UIPrompts.format_error(reason)}"}
    end
  end

  defp write_gitattributes_with_message(content, preset, action) do
    case File.write(".gitattributes", content) do
      :ok ->
        message = format_preset_message(preset, action)
        {:ok, message}

      {:error, reason} ->
        {:error, "Failed to write .gitattributes: #{UIPrompts.format_error(reason)}"}
    end
  end

  defp format_preset_message(preset, action) do
    action_text = if action == :created, do: "Created", else: "Updated"

    {_description, patterns_display} = case preset do
      :everything ->
        {"all files", "🔒  All files will be encrypted."}

      :secrets ->
        {"secret files",
         """
         🔒  Environment files will be encrypted (*.env, .env.*).
            🔒  Secrets directory will be encrypted (secrets/**).
            🔒  Key files will be encrypted (*.key, *.pem).
            🔒  Credentials will be encrypted (credentials.json).
         """}

      :env_files ->
        {"environment files",
         """
         🔒  Environment files will be encrypted (*.env, .env.*).
         """}
    end

    """
    ✅  Applied #{preset} preset

    📝  #{action_text} .gitattributes:
       #{patterns_display}

    💡  Next step - commit your changes:
          git-foil commit

       Or use git directly:
          git add .gitattributes
          git commit -m "Configure GitFoil encryption"
    """
  end

  defp help_text do
    """
    GitFoil Pattern Syntax

    Patterns control which files are encrypted in your repository.
    Add patterns to .gitattributes using the commands below.

    COMMANDS:
      git-foil configure
        Interactive menu to configure encryption patterns

      git-foil add-pattern "<pattern>"
        Example: git-foil add-pattern "*.env"

      git-foil remove-pattern "<pattern>"
        Example: git-foil remove-pattern "secrets/**"

      git-foil list-patterns
        Show all configured encryption patterns

    PATTERN SYNTAX:
      *                   Matches any characters except /
      **                  Matches any characters including /
      ?                   Matches any single character
      [abc]               Matches a, b, or c

    COMMON PATTERNS:
      *.env               All .env files in any directory
      .env.*              Files like .env.local, .env.production
      secrets/**          Everything in secrets/ directory (recursive)
      **/*.key            All .key files anywhere in the repository
      config/*.json       JSON files in config/ directory only

    EXAMPLES:
      # Encrypt all environment files
      git-foil add-pattern "*.env"
      git-foil add-pattern ".env.*"

      # Encrypt everything in secrets/
      git-foil add-pattern "secrets/**"

      # Encrypt specific file types
      git-foil add-pattern "*.key"
      git-foil add-pattern "*.pem"

    For more information: https://git-scm.com/docs/gitattributes
    """
  end

  # Decrypt files matching a specific pattern before removing it from .gitattributes
  defp decrypt_pattern_files(pattern) do
    case find_files_matching_pattern(pattern) do
      {:ok, []} ->
        # No files match this pattern, nothing to decrypt
        :ok

      {:ok, files} ->
        IO.puts("\n🔓  Decrypting #{length(files)} file(s) matching pattern: #{pattern}")
        IO.puts("")

        with :ok <- disable_filters(),
             :ok <- decrypt_files_with_progress(files),
             :ok <- enable_filters() do
          IO.puts("")
          :ok
        end

      {:error, _} = error ->
        error
    end
  end

  defp find_files_matching_pattern(pattern) do
    # Get both tracked and untracked files
    tracked_result = System.cmd("git", ["ls-files"], stderr_to_stdout: true)
    untracked_result = System.cmd("git", ["ls-files", "--others", "--exclude-standard"], stderr_to_stdout: true)

    case {tracked_result, untracked_result} do
      {{tracked_output, 0}, {untracked_output, 0}} ->
        tracked_files = tracked_output
                       |> String.split("\n", trim: true)
                       |> Enum.reject(&(&1 == ""))

        untracked_files = untracked_output
                         |> String.split("\n", trim: true)
                         |> Enum.reject(&(&1 == ""))

        all_files = (tracked_files ++ untracked_files) |> Enum.uniq()

        # Filter to only files that have the gitfoil filter for this pattern
        matching_files = Enum.filter(all_files, fn file ->
          case System.cmd("git", ["check-attr", "filter", file], stderr_to_stdout: true) do
            {attr_output, 0} ->
              String.contains?(attr_output, "filter: gitfoil") and file_matches_pattern?(file, pattern)
            _ ->
              false
          end
        end)

        {:ok, matching_files}

      {{error, _}, _} ->
        {:error, "Failed to list tracked files: #{String.trim(error)}"}

      {_, {error, _}} ->
        {:error, "Failed to list untracked files: #{String.trim(error)}"}
    end
  end

  defp file_matches_pattern?(file, pattern) do
    # Convert gitattributes pattern to regex-like matching
    # This is a simplified version - gitattributes patterns are complex
    # For now, we'll use basic wildcard matching
    regex_pattern = pattern
                    |> String.replace(".", "\\.")
                    |> String.replace("**", ".*")
                    |> String.replace("*", "[^/]*")
                    |> then(&("^" <> &1 <> "$"))

    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, file)
      _ -> false
    end
  end

  defp disable_filters do
    case System.cmd("git", ["config", "filter.gitfoil.required", "false"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, "Failed to disable filters: #{String.trim(error)}"}
    end
  end

  defp enable_filters do
    case System.cmd("git", ["config", "filter.gitfoil.required", "true"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, "Failed to enable filters: #{String.trim(error)}"}
    end
  end

  defp decrypt_files_with_progress(files) do
    total = length(files)

    files
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {file, index}, _acc ->
      # Show progress
      progress_bar = build_progress_bar(index, total)
      IO.write("\r   #{progress_bar} #{index}/#{total} files")

      # Re-add the file in plaintext (filters are disabled)
      case System.cmd("git", ["add", file], stderr_to_stdout: true) do
        {_, 0} ->
          {:cont, :ok}

        {error, _} ->
          IO.write("\n")
          {:halt, {:error, "Failed to decrypt #{file}: #{String.trim(error)}"}}
      end
    end)
    |> case do
      :ok ->
        IO.write("\n")
        :ok

      error ->
        error
    end
  end

  defp build_progress_bar(current, total) do
    percentage = current / total
    filled = round(percentage * 20)
    empty = 20 - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    percent = :erlang.float_to_binary(percentage * 100, decimals: 0)

    "#{bar} #{percent}%"
  end

  # Safe wrapper for IO.gets that handles EOF from piped input
  defp safe_gets(prompt, default \\ "") do
    case IO.gets(prompt) do
      :eof -> default
      input -> String.trim(input)
    end
  end
end
