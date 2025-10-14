defmodule GitFoil.Commands.Unencrypt do
  @moduledoc """
  Remove all GitFoil encryption from the repository.

  This command decrypts all files, removes GitFoil configuration,
  and leaves you with a plain Git repository containing plaintext files.
  """

  alias GitFoil.Helpers.UIPrompts
  alias GitFoil.Infrastructure.Terminal

  @doc """
  Unencrypt all files and remove GitFoil from the repository.

  This will:
  1. Decrypt all encrypted files
  2. Remove GitFoil patterns from .gitattributes
  3. Remove Git filter configuration
  4. Remove the master encryption key

  This operation is IRREVERSIBLE. Once the master key is deleted,
  you cannot re-encrypt with the same key.
  """
  def run(opts \\ []) do
    IO.puts("🔓  Removing GitFoil encryption...")
    IO.puts("")

    keep_key = Keyword.get(opts, :keep_key, false)

    with :ok <- verify_git_repository(),
         :ok <- verify_gitfoil_initialized(),
         :ok <- confirm_unencrypt(keep_key),
         # Get list BEFORE removing .gitattributes
         {:ok, files_to_decrypt} <- get_encrypted_files(),
         :ok <- remove_gitattributes_patterns(),
         :ok <- disable_filters(),
         :ok <- decrypt_files(files_to_decrypt),
         :ok <- remove_filter_config(),
         :ok <- remove_master_key(keep_key) do
      {:ok, success_message(keep_key)}
    else
      {:error, reason} -> {:error, reason}
      {:ok, message} -> {:ok, message}
      :cancelled -> {:ok, ""}
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
      {:ok, "👋  GitFoil not initialized. Nothing to unencrypt."}
    end
  end

  defp confirm_unencrypt(keep_key) do
    IO.puts("⚠️  WAIT - Do you need this command?")
    IO.puts("")
    IO.puts("📋  Important: GitFoil decrypts files automatically!")
    IO.puts("")
    IO.puts("   When you run git commands, decryption happens automatically:")
    IO.puts("   • git checkout <file>    → File is decrypted to your working directory")
    IO.puts("   • git pull               → Files are decrypted automatically")
    IO.puts("")
    IO.puts("ℹ️  Your files on disk are already plaintext - you can read them right now!")
    IO.puts("ℹ️  Encryption only exists inside Git's database, not in your working files.")
    IO.puts("")
    IO.puts("💡  You probably DON'T need git-foil unencrypt unless:")
    IO.puts("")
    IO.puts("   • You want to permanently remove encryption from this repository")
    IO.puts("   • You want to stop using GitFoil entirely")
    IO.puts("")
    IO.puts("Most users never need this command!")
    IO.puts("")
    UIPrompts.print_separator()
    IO.puts("")

    answer =
      safe_gets("Do you want to continue and permanently remove encryption? [y/N]: ")
      |> String.downcase()

    case answer do
      "y" ->
        confirm_destructive_action(keep_key)

      "yes" ->
        confirm_destructive_action(keep_key)

      _ ->
        IO.puts("")
        IO.puts("✅  Good choice! Your files are already decrypted in your working directory.")
        IO.puts("   No action needed - just use git normally.")
        :cancelled
    end
  end

  defp confirm_destructive_action(keep_key) do
    IO.puts("")
    IO.puts("⚠️  WARNING: This will \e[31mPERMANENTLY\e[0m remove GitFoil encryption!")
    IO.puts("")
    IO.puts("📋  What will happen:")
    IO.puts("   1. Git's internal storage will be converted from encrypted to plaintext")
    IO.puts("      (Your working files are already plaintext and won't change)")
    IO.puts("   2. GitFoil patterns removed from .gitattributes")
    IO.puts("   3. Git filter configuration removed")

    if keep_key do
      IO.puts("   4. Master encryption key will be PRESERVED")
      IO.puts("      (You can re-encrypt later with the same key)")
    else
      IO.puts("   4. Master encryption key will be DELETED (CANNOT BE UNDONE)")
      IO.puts("      (You cannot re-encrypt with the same key)")
    end

    IO.puts("")
    UIPrompts.print_separator()
    IO.puts("")

    answer =
      safe_gets("Are you absolutely sure? Type 'yes' to proceed: ")
      |> String.downcase()

    case answer do
      "yes" ->
        :ok

      _ ->
        IO.puts("")
        IO.puts("👋  Cancelled. No changes made.")
        :cancelled
    end
  end

  defp get_encrypted_files do
    IO.puts("🔍  Analyzing repository...")
    :io.format(~c"")  # Flush output immediately

    # Get list of files that have the gitfoil filter attribute
    # This must be called BEFORE removing .gitattributes
    # Only get tracked files - untracked files aren't in Git's index and don't need conversion
    tracked_result = System.cmd("git", ["ls-files"], stderr_to_stdout: true)

    case tracked_result do
      {tracked_output, 0} ->
        tracked_files =
          tracked_output
          |> String.split("\n", trim: true)
          |> Enum.reject(&(&1 == ""))

        total_files = length(tracked_files)

        # Use batch check-attr for much faster processing (100 files at a time instead of 1)
        # Show spinner during processing
        spinner_frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

        case GitFoil.Infrastructure.Git.check_attr_batch("filter", tracked_files) do
          {:ok, results} ->
            # Process results in chunks of 100 to show activity with spinner
            encrypted_files =
              results
              |> Enum.chunk_every(100)
              |> Enum.with_index(0)
              |> Enum.reduce([], fn {chunk, batch_num}, acc ->
                # Show spinner frame that rotates with each batch
                spinner = Enum.at(spinner_frames, rem(batch_num, length(spinner_frames)))
                files_processed = min((batch_num + 1) * 100, total_files)
                IO.write("\r\e[K   #{spinner} Checking #{total_files} files for encryption patterns... (#{files_processed}/#{total_files})")
                :io.format(~c"")

                # Filter this batch for encrypted files
                batch_encrypted =
                  chunk
                  |> Enum.filter(fn {file, attr} ->
                    attr == "gitfoil" and file != ".gitattributes"
                  end)
                  |> Enum.map(fn {file, _attr} -> file end)

                acc ++ batch_encrypted
              end)

            IO.write("\r\e[K   ✓ Checked #{total_files} files for encryption patterns\n")
            {:ok, encrypted_files}

          {:error, reason} ->
            {:error, "Failed to check file attributes: #{reason}"}
        end

      {error, _} ->
        {:error, "Failed to list tracked files: #{String.trim(error)}"}
    end
  end

  defp disable_filters do
    # Replace filter commands with cat (passthrough) instead of unsetting
    # This ensures git doesn't try to run the old gitfoil filter
    with {_, 0} <-
           System.cmd("git", ["config", "filter.gitfoil.clean", "cat"], stderr_to_stdout: true),
         {_, 0} <-
           System.cmd("git", ["config", "filter.gitfoil.smudge", "cat"], stderr_to_stdout: true) do
      GitFoil.Legacy.Cleanup.cleanup_git_filter()
      :ok
    else
      {error, _} -> {:error, "Failed to disable filters: #{String.trim(error)}"}
    end
  end

  defp decrypt_files(files_to_decrypt) do
    total = length(files_to_decrypt)

    if total == 0 do
      IO.puts("🔓  No encrypted files found.\n")
      :ok
    else
      IO.puts("📝  Converting Git's internal storage to plaintext...")
      IO.puts("")
      IO.puts("   ⚠️   Your working files are SAFE and will NOT be modified!")
      IO.puts("   📂  We're only changing what Git stores internally.")
      IO.puts("   🔒  Currently: Git's database has #{total} files stored encrypted")
      IO.puts("   🔓  After: Git's database will store them as plaintext")
      IO.puts("")
      IO.puts("   Processing #{total} files in Git's storage...\n")
      decrypt_files_with_progress(files_to_decrypt, total)
    end
  end

  defp decrypt_files_with_progress(files, total) do
    files
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {file, index}, _acc ->
      # Show progress (overwrite same line using ANSI escape codes)
      # \r moves cursor to start of line, \e[K clears from cursor to end of line
      progress_bar = Terminal.progress_bar(index, total)
      IO.write("\r\e[K   #{progress_bar} #{index}/#{total} files")
      # Flush to ensure immediate display
      :io.format(~c"")

      # Remove from index, then re-add with disabled filters
      # This forces git to store the plaintext working directory version
      # Use -f to force removal even if there are staged/unstaged changes
      case System.cmd("git", ["rm", "--cached", "-f", file], stderr_to_stdout: true) do
        {_, 0} ->
          # Use -f to force add even if file is in .gitignore
          case System.cmd("git", ["add", "-f", file], stderr_to_stdout: true) do
            {_, 0} ->
              {:cont, :ok}

            {error, _} ->
              IO.write("\n")
              {:halt, {:error, "Failed to process #{file}: #{String.trim(error)}"}}
          end

        {error, _} ->
          IO.write("\n")
          {:halt, {:error, "Failed to remove #{file} from index: #{String.trim(error)}"}}
      end
    end)
    |> case do
      :ok ->
        IO.write("\n\n")
        :ok

      error ->
        error
    end
  end

  defp remove_gitattributes_patterns do
    IO.puts("🗑️  Removing GitFoil patterns from .gitattributes...")
    :io.format(~c"")  # Flush immediately

    if File.exists?(".gitattributes") do
      case File.read(".gitattributes") do
        {:ok, content} ->
          # Remove GitFoil-related lines and system file exclusions
          new_content =
            content
            |> String.split("\n")
            |> Enum.reject(fn line ->
              String.contains?(line, "filter=gitfoil") or
                String.contains?(line, "filter=gitveil") or
                String.contains?(line, "GitFoil") or
                String.trim(line) == ".gitattributes -filter" or
                String.trim(line) == ".DS_Store -filter" or
                String.trim(line) == "Thumbs.db -filter" or
                String.trim(line) == "desktop.ini -filter"
            end)
            |> Enum.join("\n")
            |> String.trim()

          # Write back or delete if empty
          if new_content == "" do
            File.rm(".gitattributes")
            IO.puts("   ✓ Removed empty .gitattributes file")
            :io.format(~c"")
            IO.puts("")
            :ok
          else
            case File.write(".gitattributes", new_content <> "\n") do
              :ok ->
                IO.puts("   ✓ Updated .gitattributes")
                :io.format(~c"")
                IO.puts("")
                :ok

              {:error, reason} ->
                {:error, "Failed to update .gitattributes: #{UIPrompts.format_error(reason)}"}
            end
          end

        {:error, reason} ->
          {:error, "Failed to read .gitattributes: #{UIPrompts.format_error(reason)}"}
      end
    else
      IO.puts("   ✓ No .gitattributes file found")
      :io.format(~c"")
      IO.puts("")
      :ok
    end
  end

  defp remove_filter_config do
    IO.puts("🗑️  Removing Git filter configuration...")
    :io.format(~c"")

    filters = [
      "filter.gitfoil.clean",
      "filter.gitfoil.smudge",
      "filter.gitfoil.required"
    ]

    Enum.each(filters, fn key ->
      System.cmd("git", ["config", "--unset", key], stderr_to_stdout: true)
      # Don't fail if key doesn't exist
    end)

    IO.puts("   ✓ Removed filter configuration")
    :io.format(~c"")
    IO.puts("")
    :ok
  end

  defp remove_master_key(keep_key) do
    if keep_key do
      IO.puts("🔑  Preserving master encryption key...")
      :io.format(~c"")
      IO.puts("   ✓ Key location: .git/git_foil/master.key")
      IO.puts("   You can encrypt files again later with: git-foil encrypt")
      IO.puts("")
      :ok
    else
      IO.puts("🗑️  Removing master encryption key...")
      :io.format(~c"")

      if File.exists?(".git/git_foil") do
        case File.rm_rf(".git/git_foil") do
          {:ok, _} ->
            IO.puts("   ✓ Deleted .git/git_foil directory")
            :io.format(~c"")
            IO.puts("")
            :ok

          {:error, reason, _} ->
            {:error, "Failed to remove master key: #{UIPrompts.format_error(reason)}"}
        end
      else
        IO.puts("   ✓ No master key found")
        :io.format(~c"")
        IO.puts("")
        :ok
      end
    end
  end

  defp success_message(keep_key) do
    if keep_key do
      """
      ✅  GitFoil encryption removed!

      📋  Current state:
         • Git's internal storage now contains plaintext (not encrypted)
         • GitFoil configuration removed
         • This is now a standard Git repository
         • Your encryption key is preserved at: .git/git_foil/master.key

      💡  What you can do now:
         • Use git normally - your repository works like any other Git repo
         • Your repository has uncommitted changes (converted files)
         • Commit them when you're ready
         • To re-enable encryption: run 'git-foil encrypt' (will use the same key)
         • To permanently remove the key: run 'git-foil unencrypt' without --keep-key

      📌  Note: Your encryption key is preserved.
         You can re-enable encryption at any time.
      """
    else
      """
      ✅  GitFoil encryption removed!

      📋  Current state:
         • Git's internal storage now contains plaintext (not encrypted)
         • GitFoil completely removed
         • This is now a standard Git repository
         • The encryption key has been permanently deleted

      💡  What you can do now:
         • Use git normally - your repository works like any other Git repo
         • Your repository has uncommitted changes (converted files)
         • Commit them when you're ready
         • To re-enable encryption: run 'git-foil init'

      📌  Note: GitFoil has been completely removed.
         Your repository is now a standard Git repository without encryption.
      """
    end
  end

  # Safe wrapper for IO.gets that handles EOF from piped input
  defp safe_gets(prompt, default \\ "") do
    case IO.gets(prompt) do
      :eof -> default
      input -> String.trim(input)
    end
  end
end
