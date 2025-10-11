defmodule GitFoil.Helpers.UIPrompts do
  @moduledoc """
  Shared UI prompts and error formatting used across GitFoil commands.

  This module provides consistent user-facing messages, error formatting,
  and interactive prompts to avoid code duplication and maintain a
  cohesive user experience.
  """

  import Bitwise, only: [band: 2]
  alias GitFoil.Infrastructure.Git

  @doc """
  Formats common file system and Elixir errors into user-friendly messages.

  ## Examples

      iex> format_error(:enoent)
      "File not found"

      iex> format_error(:eacces)
      "Permission denied"

      iex> format_error({:posix, :enospc})
      "Disk full"
  """
  def format_error(:enoent), do: "File not found"
  def format_error(:eacces), do: "Permission denied"
  def format_error(:enospc), do: "Disk full"
  def format_error(:eisdir), do: "Expected file but found directory"
  def format_error(:enotdir), do: "Expected directory but found file"
  def format_error(:eexist), do: "File already exists"
  def format_error(:enomem), do: "Out of memory"
  def format_error(:emfile), do: "Too many open files"
  def format_error(:erofs), do: "Read-only file system"

  # Handle tuple errors like {:posix, :enospc}
  def format_error({:posix, reason}), do: format_error(reason)
  def format_error({:file_error, reason}), do: format_error(reason)

  # Fallback for unknown errors - still show inspect but at least it's consistent
  def format_error(reason), do: "#{inspect(reason)}"

  @doc """
  Prompts user to choose between using existing encryption key or creating a new one.

  Returns:
  - `{:use_existing}` - User wants to use the current key
  - `{:create_new}` - User wants to generate a new key
  - `{:invalid, message}` - Invalid choice with error message

  ## Options

  - `:terminal` - Terminal module to use (default: GitFoil.Adapters.Terminal)
  - `:purpose` - What the key will be used for (default: "encrypt files")
  """
  def prompt_key_choice(opts \\ []) do
    terminal = Keyword.get(opts, :terminal, GitFoil.Adapters.Terminal)
    purpose = Keyword.get(opts, :purpose, "encrypt files")

    IO.puts("🔑  Existing encryption key found!")
    IO.puts("")
    IO.puts(master_key_prompt_line(opts))
    IO.puts("")
    IO.puts("Choose an option:")
    IO.puts("")
    IO.puts("   [1] Use existing key (recommended)")
    IO.puts("       → #{capitalize_first(purpose)} with current key")
    IO.puts("")
    IO.puts("   [2] Create new key")
    IO.puts("       → Generates new encryption key")
    IO.puts("       → Old key will be backed up")
    IO.puts("       → ⚠️  Files encrypted with old key need the backup to decrypt")
    IO.puts("")

    answer = terminal.safe_gets("Choice [1]: ") |> String.trim()

    case answer do
      "" -> {:use_existing}
      "1" -> {:use_existing}
      "2" -> {:create_new}
      _ -> {:invalid, "Invalid choice. Please enter 1 or 2."}
    end
  end

  def master_key_info(opts \\ []) do
    repository = Keyword.get(opts, :repository, Git)

    path =
      case repository.repository_root() do
        {:ok, root} ->
          Path.join([root, ".git", "git_foil", "master.key"])

        {:error, _} ->
          Path.expand(".git/git_foil/master.key")
      end

    permissions =
      case File.stat(path) do
        {:ok, %File.Stat{mode: mode}} ->
          mode
          |> band(0o777)
          |> Integer.to_string(8)
          |> String.pad_leading(4, "0")

        {:error, _} ->
          nil
      end

    %{path: path, permissions: permissions}
  end

  def master_key_prompt_line(opts \\ []) do
    info = master_key_info(opts)
    "📍  Location: #{info.path}#{format_permissions_suffix(info.permissions)}"
  end

  def master_key_location_line(opts \\ []) do
    info = master_key_info(opts)
    "   Location: #{info.path}#{format_permissions_suffix(info.permissions)}"
  end

  def master_key_summary(opts \\ []) do
    info = master_key_info(opts)
    info.path <> format_permissions_suffix(info.permissions)
  end

  def master_key_path(opts \\ []) do
    master_key_info(opts).path
  end

  defp format_permissions_suffix(nil), do: ""
  defp format_permissions_suffix(perm), do: " (permissions: #{perm})"

  @doc """
  Formats a key backup confirmation message.
  """
  def format_key_backup_message(backup_path) do
    """

    ✅  Old key preserved (NOT deleted)

    📍  Renamed to: #{backup_path}

    💡  Design decision:
       GitFoil never deletes encryption keys automatically.
       This preserves access to files encrypted with the old key.

    🔄  Creating new encryption key...
    """
  end

  @doc """
  Formats a standardized error message with optional help text.

  ## Examples

      iex> format_error_message("File not found", "Run 'git-foil init' first")
      "Error: File not found\\n\\n💡 How to fix:\\n   Run 'git-foil init' first"

      iex> format_error_message("Permission denied")
      "Error: Permission denied"
  """
  def format_error_message(error, help_text \\ nil) do
    base = "Error: #{error}"

    if help_text do
      """
      #{base}

      💡 How to fix:
         #{help_text}
      """
      |> String.trim()
    else
      base
    end
  end

  @doc """
  Prompts user to confirm an action with Yes/No.

  Returns:
  - `:yes` - User confirmed (y/Y/yes/YES/Enter if default_yes is true)
  - `:no` - User declined (n/N/no/NO/Enter if default_yes is false)

  ## Options

  - `:default_yes` - Whether pressing Enter means yes (default: true)
  - `:terminal` - Terminal module to use (default: GitFoil.Adapters.Terminal)
  """
  def confirm?(prompt, opts \\ []) do
    terminal = Keyword.get(opts, :terminal, GitFoil.Adapters.Terminal)
    default_yes = Keyword.get(opts, :default_yes, true)

    answer = terminal.safe_gets(prompt) |> String.trim() |> String.downcase()

    case answer do
      "" -> if default_yes, do: :yes, else: :no
      "y" -> :yes
      "yes" -> :yes
      "n" -> :no
      "no" -> :no
      _ -> if default_yes, do: :no, else: :no
    end
  end

  @doc """
  Improves "Invalid choice" errors by telling user what the valid options are.

  ## Examples

      iex> invalid_choice_message(1..5)
      "Invalid choice. Please enter a number from 1 to 5."

      iex> invalid_choice_message(["y", "n"])
      "Invalid choice. Please enter: y, n"
  """
  def invalid_choice_message(valid_range) when is_struct(valid_range, Range) do
    "Invalid choice. Please enter a number from #{valid_range.first} to #{valid_range.last}."
  end

  def invalid_choice_message(valid_options) when is_list(valid_options) do
    "Invalid choice. Please enter: #{Enum.join(valid_options, ", ")}"
  end

  @doc """
  Prints a visual separator line to divide sections.

  Use this before prompts to create clear visual breaks between
  information display and user input sections.
  """
  def print_separator do
    IO.puts("────────────────────────────────────────")
  end

  # Private helpers

  defp capitalize_first(str) do
    String.capitalize(str)
  end
end
