defmodule GitFoil.Commands.Rekey do
  @moduledoc """
  Rekey the repository by generating new encryption keys or refreshing with existing keys.

  This command allows you to:
  1. Generate new keys and re-encrypt all files (revoke access for team members)
  2. Re-apply encryption with existing keys (useful after changing .gitattributes patterns)

  Both operations re-encrypt all tracked files by forcing Git to re-run the clean filter.
  """

  alias GitFoil.Helpers.{FileEncryption, UIPrompts}

  @doc """
  Rekey the repository by removing files from the index and re-adding them.

  This forces Git to re-run the clean filter on all tracked files with either
  new or existing encryption keys (user's choice).
  """
  def run(opts \\ []) do
    IO.puts("🔑  Rekeying repository...")
    IO.puts("")

    force = Keyword.get(opts, :force, false)

    with :ok <- verify_git_repository(),
         :ok <- verify_gitfoil_initialized(),
         key_action <- check_key_and_prompt(force),
         :ok <- maybe_generate_new_key(key_action),
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
    if File.exists?(".git/git_foil/master.key") do
      :ok
    else
      {:error, "GitFoil not initialized. Run 'git-foil init' first."}
    end
  end

  defp check_key_and_prompt(force) do
    if force do
      IO.puts("⚠️     Creating new encryption key (--force flag)\n")
      {:generate_new}
    else
      prompt_key_choice()
    end
  end

  defp prompt_key_choice do
    case UIPrompts.prompt_key_choice(purpose: "rekey repository") do
      {:use_existing} ->
        IO.puts("\n✅  Using existing encryption key\n")
        {:use_existing}

      {:create_new} ->
        case backup_existing_key() do
          {:ok, backup_path} ->
            IO.puts(UIPrompts.format_key_backup_message(backup_path))
            {:generate_new}

          {:error, reason} ->
            {:error, UIPrompts.format_error_message(
              "Failed to backup existing key: #{UIPrompts.format_error(reason)}"
            )}
        end

      {:invalid, _message} ->
        IO.puts("\n❌  Invalid choice. Using existing key.\n")
        {:use_existing}
    end
  end

  defp backup_existing_key do
    timestamp = DateTime.utc_now()
                |> DateTime.to_iso8601()
                |> String.replace(":", "-")
                |> String.replace(".", "-")

    backup_filename = "master.key.backup.#{timestamp}"
    backup_path = ".git/git_foil/#{backup_filename}"

    case File.rename(".git/git_foil/master.key", backup_path) do
      :ok ->
        {:ok, backup_path}

      {:error, reason} ->
        {:error, UIPrompts.format_error(reason)}
    end
  end

  defp maybe_generate_new_key({:use_existing}), do: :ok
  defp maybe_generate_new_key({:generate_new}) do
    alias GitFoil.Adapters.FileKeyStorage

    with {:ok, keypair} <- FileKeyStorage.generate_keypair(),
         :ok <- FileKeyStorage.store_keypair(keypair) do
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to generate keypair: #{UIPrompts.format_error(reason)}"}
    end
  end
  defp maybe_generate_new_key({:error, reason}), do: {:error, reason}

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
    deleted_result = System.cmd("git", ["diff", "--name-only", "--cached", "--diff-filter=D"], stderr_to_stdout: true)
    # Untracked files that might now match encryption patterns
    untracked_result = System.cmd("git", ["ls-files", "--others", "--exclude-standard"], stderr_to_stdout: true)

    case {deleted_result, untracked_result} do
      {{deleted_output, 0}, {untracked_output, 0}} ->
        deleted_files = deleted_output
                       |> String.split("\n", trim: true)
                       |> Enum.reject(&(&1 == ""))

        untracked_files = untracked_output
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
    key_info = case key_action do
      {:use_existing} -> "Used existing encryption key (.git/git_foil/master.key)"
      {:generate_new} -> "Generated new encryption key (.git/git_foil/master.key)\n       Old key backed up with timestamp."
      _ -> "Used encryption key (.git/git_foil/master.key)"
    end

    key_rotation_note = case key_action do
      {:generate_new} -> """

    ⚠️  IMPORTANT - New keys generated:
       All team members need the NEW key file to decrypt files.
       Share the new .git/git_foil/master.key securely with your team.
       Old keys will no longer work after you push these changes.
"""
      _ -> ""
    end

    """
    ✅  Rekey complete!

    📋  What happened:
       #{key_info}
       Files rekeyed and now match your current .gitattributes patterns.

       🔍  What this did:
          git rm --cached -r .            # Remove all files from index
          git add <each-file>             # Re-add each file (triggers clean filter)
#{key_rotation_note}
    💡  Next step - commit the changes:
       git commit -m "Rekey repository with updated encryption"
       git push

    📌 Note: Files in your working directory are unchanged.
       Only the versions stored in Git have been rekeyed.
    """
  end

  # Safe wrapper for IO.gets that handles EOF from piped input
end
