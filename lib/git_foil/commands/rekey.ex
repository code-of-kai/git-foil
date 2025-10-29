defmodule GitFoil.Commands.Rekey do
  @moduledoc """
  Rekey the repository by generating new encryption keys or refreshing with existing keys.

  This command allows you to:
  1. Generate new keys and re-encrypt all files (revoke access for team members)
  2. Re-apply encryption with existing keys (useful after changing .gitattributes patterns)

  Both operations re-encrypt all tracked files by forcing Git to re-run the clean filter.
  """

  alias GitFoil.Adapters.{FileKeyStorage, PasswordProtectedKeyStorage}
  alias GitFoil.CLI.PasswordPrompt
  alias GitFoil.Core.{KeyManager, KeyMigration}
  alias GitFoil.Helpers.{FileEncryption, UIPrompts}
  alias GitFoil.Infrastructure.Terminal

  @doc """
  Rekey the repository by removing files from the index and re-adding them.

  This forces Git to re-run the clean filter on all tracked files with either
  new or existing encryption keys (user's choice).
  """
  def run(opts \\ []) do
    IO.puts("🔑  Rekeying repository...")
    IO.puts("")

    force = Keyword.get(opts, :force, false)
    terminal = Keyword.get(opts, :terminal, Terminal)
    opts = Keyword.put(opts, :terminal, terminal)

    with :ok <- verify_git_repository(),
         :ok <- verify_gitfoil_initialized(),
         key_action <- check_key_and_prompt(force, opts),
         :ok <- maybe_generate_new_key(key_action, opts),
         :ok <- remove_from_index(),
         :ok <- re_add_files() do
      {:ok, success_message(key_action)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_git_repository do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {_error, _} ->
        {:error, "Not a Git repository. Run this command inside a Git repository."}
    end
  end

  defp verify_gitfoil_initialized do
    if FileKeyStorage.initialized?() or PasswordProtectedKeyStorage.initialized?() do
      :ok
    else
      {:error, "GitFoil not initialized. Run 'git-foil init' first."}
    end
  end

  defp check_key_and_prompt(force, opts) do
    if force do
      IO.puts("⚠️     Creating new encryption key (--force flag)\n")
      {:generate_new}
    else
      prompt_key_choice(opts)
    end
  end

  defp prompt_key_choice(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)

    case UIPrompts.prompt_key_choice(purpose: "rekey repository", terminal: terminal) do
      {:use_existing} ->
        IO.puts("\n✅  Using existing encryption key\n")
        {:use_existing}

      {:create_new} ->
        case backup_existing_key() do
          {:ok, backup_path} ->
            IO.puts(UIPrompts.format_key_backup_message(backup_path))
            {:generate_new}

          {:error, reason} ->
            {:error,
             UIPrompts.format_error_message(
               "Failed to backup existing key: #{UIPrompts.format_error(reason)}"
             )}
        end

      {:invalid, _message} ->
        IO.puts("\n❌  Invalid choice. Using existing key.\n")
        {:use_existing}
    end
  end

  defp backup_existing_key do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601()
      |> String.replace(":", "-")
      |> String.replace(".", "-")

    {source_path, backup_prefix} = current_key_paths()
    backup_filename = "#{backup_prefix}.backup.#{timestamp}"
    backup_path = ".git/git_foil/#{backup_filename}"

    case File.rename(source_path, backup_path) do
      :ok ->
        {:ok, backup_path}

      {:error, reason} ->
        {:error, UIPrompts.format_error(reason)}
    end
  end

  # Grouped clauses for maybe_generate_new_key/2
  defp maybe_generate_new_key({:use_existing}, _opts), do: :ok
  defp maybe_generate_new_key({:error, reason}, _opts), do: {:error, reason}

  defp maybe_generate_new_key({:generate_new}, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)

    choice =
      case Keyword.fetch(opts, :password) do
        {:ok, value} ->
          notify_password_selection(value, :flag)
          value

        :error ->
          default =
            if PasswordProtectedKeyStorage.initialized?() do
              :password
            else
              :no_password
            end

          {:ok, selected} =
            UIPrompts.prompt_password_protection(terminal: terminal, default: default)

          notify_password_selection(selected, :prompt)
          selected
      end

    if choice do
      # Friendly requirements before prompting
      IO.puts("")
      UIPrompts.print_password_requirements()
      prompt_password_and_init_key()
    else
      case KeyManager.init_without_password() do
        {:ok, _keypair} ->
          :ok

        {:error, reason} ->
          {:error, "Failed to generate keypair: #{UIPrompts.format_error(reason)}"}
      end
    end
  end
  
  # Re-prompts until a valid password is provided or the user cancels (Ctrl-C)
  defp prompt_password_and_init_key do
    case PasswordPrompt.get_password("New password for master key (min 8 chars): ", confirm: true) do
      {:ok, password} ->
        case KeyManager.init_with_password(password) do
          {:ok, _keypair} -> :ok
          {:error, reason} -> {:error, "Failed to generate keypair: #{UIPrompts.format_error(reason)}"}
        end

      {:error, :password_mismatch} ->
        IO.puts("\nError: Passwords do not match. Please try again.\n")
        prompt_password_and_init_key()

      {:error, {:password_too_short, min}} ->
        IO.puts("\nError: Password must be at least #{min} characters. Please try again.\n")
        prompt_password_and_init_key()

      {:error, :password_empty} ->
        IO.puts("\nError: Password cannot be empty. Please try again.\n")
        prompt_password_and_init_key()

      {:error, reason} ->
        {:error, "Password prompt failed: #{PasswordPrompt.format_error(reason)}"}
    end
  end

  # end grouped clauses

  defp notify_password_selection(true, source) do
    message =
      case source do
        :flag -> "🔐  Password protection enabled (--password flag)."
        :prompt -> "🔐  Password protection enabled."
      end

    IO.puts(message)
  end

  defp notify_password_selection(false, source) do
    message =
      case source do
        :flag -> "🔓  Storing master key without password (--no-password flag)."
        :prompt -> "🔓  Storing master key without password."
      end

    IO.puts(message)
  end

  defp remove_from_index do
    IO.puts("⚙️     Removing files from Git index...")

    case System.cmd("git", ["rm", "--cached", "-r", "."], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {error, _} ->
        # Check if it's just a "no files" error
        if String.contains?(error, "did not match any files") do
          {:error, "No files found in repository."}
        else
          {:error, "Failed to remove files from index: #{String.trim(error)}"}
        end
    end
  end

  defp re_add_files do
    # Get both tracked (now deleted from index) and untracked files
    # Tracked files were deleted by git rm --cached, so use git diff
    deleted_result =
      System.cmd("git", ["diff", "--name-only", "--cached", "--diff-filter=D"],
        stderr_to_stdout: true
      )

    # Untracked files that might now match encryption patterns
    untracked_result =
      System.cmd("git", ["ls-files", "--others", "--exclude-standard"], stderr_to_stdout: true)

    case {deleted_result, untracked_result} do
      {{deleted_output, 0}, {untracked_output, 0}} ->
        deleted_files =
          deleted_output
          |> String.split("\n", trim: true)
          |> Enum.reject(&(&1 == ""))

        untracked_files =
          untracked_output
          |> String.split("\n", trim: true)
          |> Enum.reject(&(&1 == ""))

        all_files = (deleted_files ++ untracked_files) |> Enum.uniq()
        total = length(all_files)

        if total == 0 do
          {:error, "No files to rekey."}
        else
          IO.puts("🔒  Rekeying #{total} files...\n")
          run_encrypted_add(all_files, total)
        end

      {{error, _}, _} ->
        {:error, "Failed to list deleted files: #{String.trim(error)}"}

      {_, {error, _}} ->
        {:error, "Failed to list untracked files: #{String.trim(error)}"}
    end
  end

  defp run_encrypted_add(files, total) do
    FileEncryption.add_files_with_progress(files, total)
  end

  defp success_message(key_action) do
    storage = current_storage_details()

    key_info =
      case key_action do
        {:use_existing} ->
          "Used existing encryption key.\n       #{storage.description}"

        {:generate_new} ->
          "Generated new encryption key.\n       #{storage.description}\n       Old key backed up with timestamp."

        _ ->
          "Used encryption key.\n       #{storage.description}"
      end

    key_rotation_note =
      case key_action do
        {:generate_new} -> storage.share_hint
        _ -> ""
      end

    """
    ✅  Rekey complete!

    📋  #{key_info}
       Files rekeyed and now match your current .gitattributes patterns.
    #{key_rotation_note}
    💡  Next step - commit the changes:
       git-foil commit

       Or use git directly:
          git commit -m "Rekey repository with updated encryption"
          git push
    """
  end

  defp current_storage_details do
    cond do
      PasswordProtectedKeyStorage.initialized?() ->
        %{
          description:
            "Encrypted key stored at .git/git_foil/master.key.enc (password required).",
          share_hint: """

              ⚠️  IMPORTANT - New keys generated:
                 All team members need the NEW encrypted key (.git/git_foil/master.key.enc)
                 and the password to decrypt files.
                 Share both securely with your team.
          """
        }

      FileKeyStorage.initialized?() ->
        %{
          description: "Key stored at .git/git_foil/master.key.",
          share_hint: """

              ⚠️  IMPORTANT - New keys generated:
                 All team members need the NEW key file (.git/git_foil/master.key) to decrypt files.
                 Share it securely with your team.
          """
        }

      true ->
        %{
          description: "Key stored in .git/git_foil/.",
          share_hint: ""
        }
    end
  end

  defp current_key_paths do
    encrypted = KeyMigration.encrypted_path()
    plaintext = KeyMigration.plaintext_path()

    cond do
      File.exists?(encrypted) ->
        {encrypted, Path.basename(encrypted)}

      File.exists?(plaintext) ->
        {plaintext, Path.basename(plaintext)}

      true ->
        {plaintext, Path.basename(plaintext)}
    end
  end
end
