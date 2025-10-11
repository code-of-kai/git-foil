defmodule GitFoil.Commands.Init do
  @moduledoc """
  Initialize GitFoil in a Git repository.

  This command:
  1. Verifies we're in a Git repository
  2. Generates a post-quantum keypair (Kyber1024 + classical)
  3. Saves keypair to .git/git_foil/master.key
  4. Configures Git clean/smudge filters
  5. Creates .gitattributes template (optional)
  """

  alias GitFoil.Adapters.FileKeyStorage
  alias GitFoil.Helpers.UIPrompts
  alias GitFoil.Infrastructure.{Git, Terminal}

  @doc """
  Run the initialization process.

  ## Options
  - `:force` - Overwrite existing keypair if present (default: false)
  - `:skip_patterns` - Skip pattern configuration (default: false)
  - `:repository` - Git repository adapter (default: GitFoil.Infrastructure.Git)
  - `:terminal` - Terminal UI adapter (default: GitFoil.Infrastructure.Terminal)

  ## Returns
  - `{:ok, message}` - Success with helpful message
  - `{:error, reason}` - Failure with error message
  """
  def run(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    skip_patterns = Keyword.get(opts, :skip_patterns, false)

    # Dependency injection - defaults to real implementations
    repository = Keyword.get(opts, :repository, Git)
    terminal = Keyword.get(opts, :terminal, Terminal)

    # Store in opts for passing to helper functions
    opts = Keyword.merge(opts, [repository: repository, terminal: terminal])

    with :ok <- verify_git_repository(opts),
         :ok <- check_already_fully_initialized(force, opts),
         {:ok, key_action} <- check_existing_initialization(force, opts),
         :ok <- confirm_initialization(key_action, force, opts),
         :ok <- generate_keypair_and_configure_filters(key_action, opts),
         {:ok, pattern_status} <- maybe_configure_patterns(skip_patterns, opts),
         {:ok, encrypted} <- maybe_encrypt_files(pattern_status, opts) do
      {:ok, success_message(pattern_status, encrypted, opts)}
    else
      {:error, reason} -> {:error, reason}
      :exited -> {:ok, ""}
    end
  end

  defp generate_keypair_and_configure_filters(:use_existing, opts) do
    configure_git_filters(opts)
  end

  defp generate_keypair_and_configure_filters(:generate_new, opts) do
    run_parallel_setup(opts)
  end

  defp maybe_configure_patterns(true, _opts), do: {:ok, :skipped}
  defp maybe_configure_patterns(false, opts), do: configure_patterns(opts)

  @doc """
  Interactive pattern configuration (can be called post-init).
  """
  def configure_patterns(opts \\ []) do
    terminal = Keyword.get(opts, :terminal, Terminal)

    IO.puts("\n🔐  GitFoil Setup - Pattern Configuration")
    IO.puts("")
    IO.puts("Which files should be encrypted?")
    IO.puts("[1] Everything (encrypt all files)")
    IO.puts("[2] Secrets only (*.env, secrets/**, *.key, *.pem, credentials.json)")
    IO.puts("[3] Environment files (*.env, .env.*)")
    IO.puts("[4] Custom patterns (interactive)")
    IO.puts("[5] Decide later (you can configure patterns anytime with 'git-foil configure')")
    IO.puts("")
    UIPrompts.print_separator()

    choice = terminal.safe_gets("\nChoice [1]: ")

    case choice do
      "" -> apply_pattern_preset(:everything, :everything)
      "1" -> apply_pattern_preset(:everything, :everything)
      "2" -> apply_pattern_preset(:secrets, :secrets)
      "3" -> apply_pattern_preset(:env_files, :env_files)
      "4" -> custom_patterns(opts)
      "5" -> decide_later()
      _ -> {:error, UIPrompts.invalid_choice_message(1..5)}
    end
  end

  # ============================================================================
  # Pattern Configuration
  # ============================================================================

  defp apply_pattern_preset(preset, status_label) do
    patterns = get_preset_patterns(preset)
    content = build_gitattributes_content(patterns)

    case write_and_commit_gitattributes(content) do
      :ok -> {:ok, status_label}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_preset_patterns(:everything) do
    ["** filter=gitfoil"]
  end

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

  defp custom_patterns(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)

    IO.puts("\nEnter file patterns to encrypt (one per line).")
    IO.puts("Common examples:")
    IO.puts("  *.env           - All .env files")
    IO.puts("  secrets/**      - Everything in secrets/ directory")
    IO.puts("  *.key           - All .key files")
    IO.puts("\nPress Enter on empty line when done.")
    IO.puts("")
    UIPrompts.print_separator()

    patterns = collect_patterns([], terminal)

    if Enum.empty?(patterns) do
      IO.puts("\nNo patterns entered. Skipping .gitattributes creation.")
      {:ok, :decided_later}
    else
      content = build_gitattributes_content(patterns)

      case write_and_commit_gitattributes(content) do
        :ok -> {:ok, :custom}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp collect_patterns(acc, terminal) do
    pattern = terminal.safe_gets("\nPattern: ")

    case pattern do
      "" ->
        Enum.reverse(acc)

      _ ->
        full_pattern = pattern <> " filter=gitfoil"
        collect_patterns([full_pattern | acc], terminal)
    end
  end

  defp decide_later do
    {:ok, :decided_later}
  end

  defp build_gitattributes_content(patterns) do
    header = "# GitFoil - Quantum-resistant Git encryption\n"
    pattern_lines = Enum.join(patterns, "\n")
    # .gitattributes must not be encrypted (Git needs to read it)
    # This MUST come after ** pattern (Git applies last matching pattern)
    exclusion = "\n.gitattributes -filter\n"
    header <> pattern_lines <> exclusion
  end

  defp write_and_commit_gitattributes(content) do
    # Write the .gitattributes file
    case File.write(".gitattributes", content) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, "Failed to create .gitattributes: #{UIPrompts.format_error(reason)}"}
    end
  end

  # ============================================================================
  # Verification Steps
  # ============================================================================

  defp verify_git_repository(opts) do
    repository = Keyword.get(opts, :repository, Git)

    case repository.verify_repository() do
      {:ok, _git_dir} ->
        :ok

      {:error, _} ->
        # No Git repository found - offer to create one
        offer_git_init(opts)
    end
  end

  defp offer_git_init(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)

    IO.puts("\nNo Git repository found in this directory.")
    IO.puts("GitFoil requires a Git repository to function.")
    IO.puts("")
    UIPrompts.print_separator()

    answer = terminal.safe_gets("\nWould you like to create one? [Y/n]: ") |> String.downcase()

    if affirmed?(answer) do
      initialize_git_repo(opts)
    else
      {:error, "GitFoil requires a Git repository. Run 'git init' first, then try again."}
    end
  end

  defp initialize_git_repo(opts) do
    repository = Keyword.get(opts, :repository, Git)

    case repository.init_repository() do
      {:ok, output} ->
        IO.puts("\n✅  " <> output)
        :ok

      {:error, error} ->
        {:error, "Failed to initialize Git repository: #{error}"}
    end
  end

  defp check_already_fully_initialized(true = _force, _opts), do: :ok

  defp check_already_fully_initialized(false = _force, _opts) do
    has_key? = File.exists?(".git/git_foil/master.key")
    {has_patterns?, pattern_count} = check_gitattributes_patterns()

    case {has_key?, has_patterns?} do
      {true, true} ->
        pattern_text = if pattern_count == 1, do: "1 pattern", else: "#{pattern_count} patterns"

        message = """
        ✅  GitFoil is already initialized in this repository.

           🔑  Encryption key: .git/git_foil/master.key
           📝  Patterns: #{pattern_text} configured in .gitattributes

        💡  Need to make changes?

           • To change which files are encrypted:
             git-foil configure

           • To create a new encryption key:
             git-foil init --force
             (Your old key will be backed up automatically)

           • To see all available commands:
             git-foil help
        """

        {:error, message}

      _ ->
        :ok
    end
  end

  defp check_gitattributes_patterns do
    case File.read(".gitattributes") do
      {:ok, content} ->
        has_patterns? = String.contains?(content, "filter=gitfoil")
        pattern_count = content
                       |> String.split("\n")
                       |> Enum.count(&String.contains?(&1, "filter=gitfoil"))
        {has_patterns?, pattern_count}

      {:error, _} ->
        {false, 0}
    end
  end

  defp check_existing_initialization(force, opts) do
    case FileKeyStorage.initialized?() do
      false ->
        {:ok, :generate_new}

      true when force ->
        IO.puts("⚠️     Overwriting existing encryption key (--force flag)\n")
        {:ok, :generate_new}

      true ->
        prompt_key_choice(opts)
    end
  end

  defp prompt_key_choice(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)

    case UIPrompts.prompt_key_choice(terminal: terminal, purpose: "initialize GitFoil") do
      {:use_existing} ->
        IO.puts("\n✅  Using existing encryption key\n")
        {:ok, :use_existing}

      {:create_new} ->
        case backup_existing_key() do
          {:ok, backup_path} ->
            IO.puts(UIPrompts.format_key_backup_message(backup_path))
            {:ok, :generate_new}

          {:error, reason} ->
            {:error, UIPrompts.format_error_message(
              "Failed to backup existing key: #{UIPrompts.format_error(reason)}"
            )}
        end

      {:invalid, message} ->
        IO.puts("\n❌  #{message}. Please run init again.\n")
        {:error, message}
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

  defp confirm_initialization(key_action, force, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    repository = Keyword.get(opts, :repository, Git)
    IO.puts("")
    IO.puts("🔐  GitFoil Initialization")
    IO.puts("")
    IO.puts("This will:")
    IO.puts("")

    # Show what will happen with encryption keys
    case key_action do
      :generate_new when force ->
        IO.puts("   🔑  Generate new encryption keys (--force flag)")
        IO.puts("      → Creates quantum-resistant keypair (Kyber1024)")
        IO.puts("      → Old key will be backed up automatically")

      :generate_new ->
        IO.puts("   🔑  Generate encryption keys")
        IO.puts("      → Creates quantum-resistant keypair (Kyber1024)")
        IO.puts("      → Stored securely in .git/git_foil/master.key")

      :use_existing ->
        IO.puts("   🔑  Use existing encryption key")
        IO.puts("      → Located at .git/git_foil/master.key")
    end

    IO.puts("")

    # Show what will happen with Git configuration
    filters_configured? = git_filters_configured?(repository)

    if filters_configured? do
      IO.puts("   🔒  Git already configured for automatic encryption")
      IO.puts("      → Files encrypt automatically when you git add or git commit")
      IO.puts("      → Files decrypt automatically when you git checkout or git pull")
    else
      IO.puts("   🔒  Configure Git for automatic encryption")
      IO.puts("      → Files will encrypt automatically when you git add or git commit")
      IO.puts("      → Files will decrypt automatically when you git checkout or git pull")
      IO.puts("      → Only Git's internal storage is encrypted, not your working files")
    end

    IO.puts("")
    UIPrompts.print_separator()

    answer = terminal.safe_gets("\nProceed with initialization? [Y/n]: ") |> String.downcase()

    if affirmed?(answer) do
      IO.puts("")
      :ok
    else
      IO.puts("")
      IO.puts("👋  Exited initialization.")
      :exited
    end
  end

  defp git_filters_configured?(repository) do
    repository.config_exists?("filter.gitfoil.clean")
  end

  # ============================================================================
  # Parallel Setup
  # ============================================================================

  defp run_parallel_setup(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    repository = Keyword.get(opts, :repository, Git)

    # First step: Generate keypair
    keypair_result = terminal.with_spinner(
      "Generating quantum-resistant encryption keys",
      fn -> do_generate_keypair(3000) end
    )

    case keypair_result do
      {:ok, _} ->
        IO.puts("✅  Generated quantum-resistant encryption keys")

        # Second step: Configure filters
        filter_result = terminal.with_spinner(
          "Configuring Git filters for automatic encryption/decryption",
          fn -> do_configure_filters(3000, repository) end
        )

        case filter_result do
          :ok ->
            IO.puts("✅  Configured Git filters for automatic encryption/decryption")
            :ok
          error -> error
        end

      {:error, _} = error -> error
    end
  end

  defp do_generate_keypair(min_duration) do
    start_time = System.monotonic_time(:millisecond)

    result = with {:ok, keypair} <- FileKeyStorage.generate_keypair(),
                  :ok <- FileKeyStorage.store_keypair(keypair) do
      {:ok, keypair}
    else
      {:error, reason} ->
        {:error, "Failed to generate keypair: #{UIPrompts.format_error(reason)}"}
    end

    # Ensure minimum duration
    elapsed = System.monotonic_time(:millisecond) - start_time
    if elapsed < min_duration do
      Process.sleep(min_duration - elapsed)
    end

    result
  end

  defp do_configure_filters(min_duration, repository) do
    start_time = System.monotonic_time(:millisecond)

    executable_path = get_executable_path()

    filters = [
      {"filter.gitfoil.clean", "#{executable_path} clean %f"},
      {"filter.gitfoil.smudge", "#{executable_path} smudge %f"},
      {"filter.gitfoil.required", "true"}
    ]

    results =
      Enum.map(filters, fn {key, value} ->
        repository.set_config(key, value)
      end)

    # Ensure minimum duration
    elapsed = System.monotonic_time(:millisecond) - start_time
    if elapsed < min_duration do
      Process.sleep(min_duration - elapsed)
    end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  # ============================================================================
  # Git Configuration
  # ============================================================================

  defp configure_git_filters(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    repository = Keyword.get(opts, :repository, Git)

    result = terminal.with_spinner(
      "   Configuring Git filters for automatic encryption/decryption",
      fn ->
        # Determine the correct path to git-foil executable
        executable_path = get_executable_path()

        filters = [
          {"filter.gitfoil.clean", "#{executable_path} clean %f"},
          {"filter.gitfoil.smudge", "#{executable_path} smudge %f"},
          {"filter.gitfoil.required", "true"}
        ]

        results =
          Enum.map(filters, fn {key, value} ->
            repository.set_config(key, value)
          end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> :ok
          error -> error
        end
      end,
      min_duration: 10_000
    )

    case result do
      :ok ->
        IO.puts("✅  Configured Git filters for automatic encryption/decryption")
        :ok
      error ->
        error
    end
  end

  # ============================================================================
  # Executable Path Detection
  # ============================================================================

  defp get_executable_path do
    # Detect the path to the currently running git-foil executable
    case System.fetch_env("_") do
      {:ok, path} when path != "" ->
        # Use the path that was used to invoke this command
        path

      :error ->
        # Fallback: try to find git-foil in PATH
        case System.find_executable("git-foil") do
          nil -> "git-foil"  # Last resort: assume it's in PATH
          path -> path
        end
    end
  end

  # ============================================================================
  # File Encryption
  # ============================================================================

  defp maybe_encrypt_files(:skipped, _opts), do: {:ok, false}

  defp maybe_encrypt_files(_pattern_status, opts) do
    # Count only files matching the configured encryption patterns
    case count_files_matching_patterns(opts) do
      {:ok, 0} ->
        {:ok, false}

      {:ok, count} ->
        offer_encryption(count, opts)

      {:error, _} ->
        {:ok, false}
    end
  end

  defp count_files_matching_patterns(opts) do
    with {:ok, all_files} <- get_all_repository_files(opts),
         {:ok, matching_files} <- get_files_matching_patterns(all_files, opts) do
      {:ok, length(matching_files)}
    end
  end

  defp get_all_repository_files(opts) do
    repository = Keyword.get(opts, :repository, Git)
    repository.list_all_files()
  end

  defp offer_encryption(count, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    many_files = count > 100

    IO.puts("")
    IO.puts("💡  Encrypt existing files now?")
    IO.puts("")
    IO.puts("   Found #{terminal.format_number(count)} #{terminal.pluralize("file", count)} matching your patterns.")
    IO.puts("")
    IO.puts("   [Y] Yes - Encrypt files now (recommended)")
    IO.puts("       → Shows progress as files are encrypted")
    IO.puts("       → Files ready to commit immediately")
    if many_files do
      IO.puts("       → Note: Encryption will take longer with many files")
    end
    IO.puts("")
    IO.puts("   [n] No - I'll encrypt them later")
    IO.puts("       → Use git-foil encrypt (shows progress, all at once)")
    IO.puts("       → Or just use git normally: git add / git commit")
    IO.puts("       → Either way, files encrypt automatically")
    if many_files do
      IO.puts("       → Note: git add/commit will take longer with many files")
    end
    IO.puts("")
    UIPrompts.print_separator()

    answer = terminal.safe_gets("\nEncrypt now? [Y/n]: ") |> String.downcase()

    if affirmed?(answer) do
      encrypt_files_with_progress(count, opts)
    else
      IO.puts("")
      {:ok, false}
    end
  end

  defp encrypt_files_with_progress(_count, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    IO.puts("")

    # Get only files that match the configured encryption patterns
    with {:ok, all_files} <- get_all_repository_files(opts),
         {:ok, matching_files} <- get_files_matching_patterns(all_files, opts) do

      actual_count = length(matching_files)

      if actual_count == 0 do
        IO.puts("🔒  No files match your encryption patterns.")
        IO.puts("    Files will be encrypted as you add them with git add/commit.")
        IO.puts("")
        {:ok, false}
      else
        IO.puts("🔒  Encrypting #{terminal.format_number(actual_count)} #{terminal.pluralize("file", actual_count)} matching your patterns...")
        IO.puts("")

        with :ok <- add_files_with_progress(matching_files, actual_count, opts) do
          {:ok, true}
        end
      end
    end
  end

  defp get_files_matching_patterns(all_files, opts) do
    repository = Keyword.get(opts, :repository, Git)

    # Batch check all files at once instead of one-by-one to avoid spawning too many processes
    case repository.check_attr_batch("filter", all_files) do
      {:ok, results} ->
        # Use comprehension for single-pass filter+map (more idiomatic)
        matching_files = for {file, attr} <- results,
                             String.contains?(attr, "filter: gitfoil"),
                             do: file
        {:ok, matching_files}

      {:error, _reason} ->
        # Fallback to individual checks if batch fails
        matching_files = Enum.filter(all_files, fn file ->
          case repository.check_attr("filter", file) do
            {:ok, attr_output} ->
              String.contains?(attr_output, "filter: gitfoil")
            _ ->
              false
          end
        end)
        {:ok, matching_files}
    end
  end

  defp add_files_with_progress(files, total, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    repository = Keyword.get(opts, :repository, Git)

    files
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {file, index}, _acc ->
      progress_bar = terminal.progress_bar(index, total)
      IO.write("\r   #{progress_bar} #{index}/#{total} files")

      # Add the file (triggers clean filter for encryption)
      case repository.add_file(file) do
        :ok -> {:cont, :ok}
        {:error, reason} ->
          IO.write("\n")
          {:halt, {:error, "Failed to encrypt #{file}: #{reason}"}}
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

  # ============================================================================
  # Messages
  # ============================================================================

  defp success_message(pattern_status, encrypted, opts) do
    repository = Keyword.get(opts, :repository, Git)

    # Get absolute path to master.key for easy copying
    key_path = case repository.repository_root() do
      {:ok, repo_root} ->
        Path.join([repo_root, ".git", "git_foil", "master.key"])
      _ ->
        # Fallback to relative path if git command fails
        Path.expand(".git/git_foil/master.key")
    end

    base_config = """
    ✅  GitFoil setup complete!

    🔐  Quantum-resistant encryption initialized:
       Generated Kyber1024 post-quantum keypair.
       Enabled automatic encryption.
       Files will encrypt when you git add or git commit.
       Files will decrypt when you git checkout or git pull.

    🔑  Your encryption key:
       Location: .git/git_foil/master.key (permissions: 0600)
    """

    pattern_message = get_pattern_message(pattern_status, encrypted)

    warning = """

    ⚠️  IMPORTANT: Back up your master.key!
       Without this key, you cannot decrypt your files.
       Store it securely in a password manager or encrypted backup.

       Your key can be found here:
       #{key_path}
    """

    base_config <> pattern_message <> warning
  end

  defp get_pattern_message(:decided_later, _encrypted) do
    """

    📋  What was completed:
       ✅  Encryption keys generated and stored securely
       ✅  Git filters configured for automatic encryption/decryption
       ⏸️   Pattern configuration postponed

    💡  Next step - Configure which files to encrypt:
       git-foil configure              # Interactive menu to choose patterns
       git-foil add-pattern "*.env"    # Add specific patterns manually
       git-foil help patterns          # Learn about pattern syntax

    📝  Important: Files will NOT be encrypted until you configure patterns.
       Your repository works normally, but encryption is not active yet.
    """
  end

  defp get_pattern_message(:skipped, _encrypted) do
    """

    📝  Pattern configuration was skipped.

    💡  To configure which files to encrypt:
       git-foil configure
    """
  end

  defp get_pattern_message(:everything, true) do
    """

    🔒  Encryption complete!
       📋  All files are encrypted and staged.

    💡  Next step - commit the encrypted files:
       git-foil commit

       🔍  What this does:
          git commit -m "Add encrypted files"

    📌 Note: Files in your working directory remain plaintext.
       Only the versions stored in Git are encrypted.
    """
  end

  defp get_pattern_message(:everything, false) do
    """

    🔒  Encryption is active!
       📋  All files will be encrypted.

    💡  Try it out - create a test file:
       echo "IT'S A SECRET TO EVERYBODY." > test.txt

       Use git-foil commands:
          git-foil encrypt    # Encrypts and stages test.txt
          git-foil commit     # Commits encrypted file

       Or use git directly (git-foil wraps these):
          git add test.txt    # Encrypts and stages test.txt
          git commit -m "Add test file"

       Files are encrypted when committed and decrypted when checked out.
    """
  end

  defp get_pattern_message(:secrets, true) do
    """

    🔒  Encryption complete!
       📋  Patterns configured:
          • Environment files (*.env, .env.*)
          • Secrets directory (secrets/**)
          • Key files (*.key, *.pem)
          • Credentials (credentials.json)

       All matching files are encrypted and staged.

    💡  Next step - commit the encrypted files:
       git-foil commit

       🔍  What this does:
          git commit -m "Add encrypted files"

    📌 Note: Files in your working directory remain plaintext.
       Only the versions stored in Git are encrypted.
    """
  end

  defp get_pattern_message(:secrets, false) do
    """

    🔒  Encryption is active!
       📋  Patterns configured:
          • Environment files will be encrypted (*.env, .env.*)
          • Secrets directory will be encrypted (secrets/**)
          • Key files will be encrypted (*.key, *.pem)
          • Credentials will be encrypted (credentials.json)

    💡  Try it out - create a secret file:
       echo "API_KEY=secret123" > .env

       Use git-foil commands:
          git-foil encrypt    # Encrypts and stages .env
          git-foil commit     # Commits encrypted file

       Or use git directly (git-foil wraps these):
          git add .env        # Encrypts and stages .env
          git commit -m "Add environment variables"

       Files are encrypted when committed and decrypted when checked out.
    """
  end

  defp get_pattern_message(:env_files, true) do
    """

    🔒  Encryption complete!
       📋  Environment files (*.env, .env.*) are encrypted and staged.

    💡  Next step - commit the encrypted files:
       git-foil commit

       🔍  What this does:
          git commit -m "Add encrypted files"

    📌 Note: Files in your working directory remain plaintext.
       Only the versions stored in Git are encrypted.
    """
  end

  defp get_pattern_message(:env_files, false) do
    """

    🔒  Encryption is active!
       📋  Environment files will be encrypted (*.env, .env.*).

    💡  Try it out - create an environment file:
       echo "DATABASE_URL=postgresql://localhost" > .env.local

       Use git-foil commands:
          git-foil encrypt    # Encrypts and stages .env.local
          git-foil commit     # Commits encrypted file

       Or use git directly (git-foil wraps these):
          git add .env.local  # Encrypts and stages .env.local
          git commit -m "Add local environment config"

       Files are encrypted when committed and decrypted when checked out.
    """
  end

  defp get_pattern_message(:custom, true) do
    """

    🔒  Encryption complete!
       Custom patterns added to .gitattributes.
       All matching files are encrypted and staged.

    💡  Next step - commit the encrypted files:
       git-foil commit

       🔍  What this does:
          git commit -m "Add encrypted files"

    📌 Note: Files in your working directory remain plaintext.
       Only the versions stored in Git are encrypted.
    """
  end

  defp get_pattern_message(:custom, false) do
    """

    🔒  Encryption is active!
       Custom patterns added to .gitattributes.
       Git will encrypt matching files when you run 'git add' or 'git commit'.
       Git will decrypt them when you run 'git checkout'.

    💡  Try it out:
       cat .gitattributes              # View your patterns
       git add <matching-file>
       git commit -m "Add encrypted file"
       # Matching files will be encrypted automatically!
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Check if user answered affirmatively (y, yes, or empty for default yes)
  defp affirmed?(answer) when answer in ["", "y", "yes"], do: true
  defp affirmed?(_answer), do: false
end
