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

  alias GitFoil.Adapters.{FileKeyStorage, PasswordProtectedKeyStorage}
  alias GitFoil.Core.{KeyManager, KeyMigration}
  alias GitFoil.CLI.PasswordInput
  alias GitFoil.Helpers.{FileEncryption, UIPrompts}
  alias GitFoil.Infrastructure.{Git, Terminal}

  @doc """
  Run the initialization process.

  ## Options
  - `:force` - Overwrite existing keypair if present (default: false)
  - `:skip_patterns` - Skip pattern configuration (default: false)
  - `:password` - Enable password protection for master key (default: false)
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
    opts =
      Keyword.merge(opts,
        repository: repository,
        terminal: terminal
      )

    with :ok <- verify_git_repository(opts),
         :ok <- check_already_fully_initialized(force, opts),
         {:ok, key_action} <- check_existing_initialization(force, opts),
         {:ok, opts} <- ensure_password_choice(key_action, opts),
         :ok <- confirm_initialization(key_action, force, opts),
         {:ok, opts} <- maybe_update_existing_key_storage(key_action, opts),
         :ok <- generate_keypair_and_configure_filters(key_action, opts),
         {:ok, pattern_status} <- maybe_configure_patterns(skip_patterns, opts),
         {:ok, encrypted} <- maybe_process_existing_files(key_action, pattern_status, opts) do
      {:ok, success_message(pattern_status, encrypted, opts)}
    else
      {:ok, message} -> {:ok, message}
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

    IO.puts("")
    IO.puts("🔐  GitFoil Setup - Pattern Configuration")
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
    # Exclusions must not be encrypted
    # .gitattributes - Git needs to read it
    # System files - should be in .gitignore, not encrypted
    # These MUST come after ** pattern (Git applies last matching pattern)
    exclusions = """

    .gitattributes -filter
    .DS_Store -filter
    Thumbs.db -filter
    desktop.ini -filter
    """

    header <> pattern_lines <> exclusions
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

  defp check_already_fully_initialized(false = _force, opts) do
    repository = Keyword.get(opts, :repository, Git)

    has_key? =
      File.exists?(".git/git_foil/master.key") or
        File.exists?(".git/git_foil/master.key.enc")

    {has_patterns?, pattern_count} = check_gitattributes_patterns()

    filters_configured? =
      repository.config_exists?("filter.gitfoil.clean") and
        repository.config_exists?("filter.gitfoil.smudge")

    case {has_key?, has_patterns?, filters_configured?} do
      {true, true, true} ->
        pattern_text = if pattern_count == 1, do: "1 pattern", else: "#{pattern_count} patterns"
        key_summary = UIPrompts.master_key_summary()
        encrypted_count = count_encrypted_candidates(opts)

        IO.puts("""
🔍  GitFoil detected an existing encrypted repository.

   • Encryption key stored at: #{key_summary}
   • Patterns configured: #{pattern_text}
   • Encrypted tracked files detected: #{encrypted_count}

Run continues so the working tree can be decrypted and made readable.
(Use `git-foil init --force` if you actually want to replace the encryption key.)
""")

        :ok

      _ ->
        :ok
    end
  end

  defp check_gitattributes_patterns do
    case File.read(".gitattributes") do
      {:ok, content} ->
        has_patterns? = String.contains?(content, "filter=gitfoil")

        pattern_count =
          content
          |> String.split("\n")
          |> Enum.count(&String.contains?(&1, "filter=gitfoil"))

        {has_patterns?, pattern_count}

      {:error, _} ->
        {false, 0}
    end
  end

  defp check_existing_initialization(force, _opts) do
    # Check both plaintext and password-protected storage
    has_plaintext = FileKeyStorage.initialized?()
    has_password_protected = PasswordProtectedKeyStorage.initialized?()

    case {has_plaintext, has_password_protected, force} do
      {false, false, _} ->
        {:ok, :generate_new}

      {_, _, true} ->
        IO.puts("⚠️     Overwriting existing encryption key (--force flag)\n")
        {:ok, :generate_new}

      _ ->
        IO.puts("\n✅  Using existing encryption key\n")
        {:ok, :use_existing}
    end
  end

  defp ensure_password_choice(:generate_new, opts) do
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
      IO.puts("")
      IO.puts("🔒  The master key will be encrypted with your password.")

      password_opts =
        password_prompt_opts(opts,
          confirm: true,
          min_length: 8
        )

      case PasswordInput.new_password("Password for master key: ", password_opts) do
        {:ok, password} ->
          IO.puts("")

          {:ok,
           opts
           |> Keyword.put(:use_password, true)
           |> Keyword.put(:password_value, password)}

        {:error, error} ->
          {:error, error}
      end
    else
      {:ok, Keyword.put(opts, :use_password, false)}
    end
  end

  defp ensure_password_choice(:use_existing, opts) do
    with {:ok, current_state, desired_state} <- current_and_desired_storage(opts) do
      cond do
        desired_state == current_state ->
          {:ok,
           opts
           |> Keyword.delete(:password_migration)
           |> Keyword.put(:use_password, current_state)}

        desired_state ->
          prepare_password_migration(:encrypt, opts)

        true ->
          prepare_password_migration(:unencrypt, opts)
      end
    end
  end

  defp current_and_desired_storage(opts) do
    case KeyManager.initialization_status() do
      {:initialized, :plaintext} ->
        {:ok, false, desired_state(false, opts)}

      {:initialized, :password_protected} ->
        {:ok, true, desired_state(true, opts)}

      :not_initialized ->
        {:error, "GitFoil not initialized. Run 'git-foil init' first."}
    end
  end

  defp desired_state(current_state, opts) do
    case Keyword.fetch(opts, :password) do
      {:ok, value} -> value
      :error -> current_state
    end
  end

  defp prepare_password_migration(:encrypt, opts) do
    IO.puts("")
    IO.puts("🔐  Encrypting existing master key with a password.")

    password_opts =
      password_prompt_opts(opts,
        confirm: true,
        min_length: 8
      )

    case PasswordInput.new_password("Password for master key: ", password_opts) do
      {:ok, password} ->
        {:ok,
         opts
         |> Keyword.put(:use_password, true)
         |> Keyword.put(:password_migration, {:encrypt, password})}

      {:error, error} ->
        {:error, error}
    end
  end

  defp prepare_password_migration(:unencrypt, opts) do
    IO.puts("")
    IO.puts("🔓  Removing password protection from existing master key.")

    password_opts = password_prompt_opts(opts)

    case PasswordInput.existing_password("Current master key password: ", password_opts) do
      {:ok, password} ->
        {:ok,
         opts
         |> Keyword.put(:use_password, false)
         |> Keyword.put(:password_migration, {:unencrypt, password})}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_update_existing_key_storage(:use_existing, opts) do
    case Keyword.get(opts, :password_migration) do
      nil ->
        {:ok, cleanup_password_opts(opts)}

      {:encrypt, password} ->
        case KeyMigration.encrypt_plaintext_key(password) do
          {:ok, %{backup_path: backup_path}} ->
            print_migration_success(:encrypt, backup_path)
            {:ok, cleanup_password_opts(opts, [:password_value])}

          {:error, :already_encrypted} ->
            {:ok, cleanup_password_opts(opts)}

          {:error, reason} ->
            {:error, format_storage_change_error(reason)}
        end

      {:unencrypt, password} ->
        case KeyMigration.unencrypt_key(password) do
          {:ok, %{backup_path: backup_path}} ->
            print_migration_success(:unencrypt, backup_path)
            {:ok, cleanup_password_opts(opts, [:password_value])}

          {:error, :already_plaintext} ->
            {:ok, cleanup_password_opts(opts)}

          {:error, :invalid_password} ->
            {:error, {1, "Error: Invalid password."}}

          {:error, reason} ->
            {:error, format_storage_change_error(reason)}
        end
    end
  end

  defp maybe_update_existing_key_storage(_key_action, opts) do
    {:ok, cleanup_password_opts(opts)}
  end

  defp password_prompt_opts(opts, overrides \\ []) do
    base = Keyword.take(opts, [:password_source, :password_no_confirm])

    base
    |> Keyword.merge(overrides, fn _key, _existing, override -> override end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp cleanup_password_opts(opts, extra_keys \\ []) do
    ([:password_migration] ++ extra_keys)
    |> Enum.reduce(opts, fn key, acc -> Keyword.delete(acc, key) end)
  end

  defp print_migration_success(:encrypt, backup_path) do
    IO.puts("")
    IO.puts("✅  Master key is now password protected.")
    IO.puts("   Encrypted key: #{KeyMigration.encrypted_path()}")
    IO.puts("   Plaintext backup saved to: #{backup_path}")
    IO.puts("")
  end

  defp print_migration_success(:unencrypt, backup_path) do
    IO.puts("")
    IO.puts("✅  Master key stored without password.")
    IO.puts("   Plaintext key: #{KeyMigration.plaintext_path()}")
    IO.puts("   Encrypted backup saved to: #{backup_path}")
    IO.puts("")
  end

  defp format_storage_change_error({:backup_failed, reason}) do
    "Failed to create key backup: #{UIPrompts.format_error(reason)}"
  end

  defp format_storage_change_error({:remove_failed, reason}) do
    """
    Key migration completed, but failed to remove old key: #{UIPrompts.format_error(reason)}
    """
    |> String.trim()
  end

  defp format_storage_change_error(:no_plaintext_key) do
    "Plaintext master key not found at #{KeyMigration.plaintext_path()}."
  end

  defp format_storage_change_error(:no_encrypted_key) do
    "Encrypted master key not found at #{KeyMigration.encrypted_path()}."
  end

  defp format_storage_change_error(other) when is_binary(other), do: other
  defp format_storage_change_error(other), do: UIPrompts.format_error(other)

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

  defp confirm_initialization(key_action, force, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    repository = Keyword.get(opts, :repository, Git)
    use_password = Keyword.get(opts, :use_password, false)
    plaintext_path = UIPrompts.master_key_info(repository: repository).path
    encrypted_path = encrypted_key_path(repository)
    filters_configured? = git_filters_configured?(repository)

    {existing_location_line, new_storage_line} =
      if use_password do
        {
          "      → Encrypted key located at #{encrypted_path}",
          "      → Stored encrypted in #{encrypted_path} (password required)"
        }
      else
        {
          "      → Located at #{plaintext_path}",
          "      → Stored in #{plaintext_path}"
        }
      end

    IO.puts("")

    if key_action == :use_existing and filters_configured? do
      IO.puts("🔓  Prepare working tree for plaintext")
      IO.puts("")
      IO.puts("GitFoil will refresh tracked files so they decrypt locally.")
      IO.puts("This does not modify your encryption key or patterns.")
      IO.puts("")
      IO.puts("Actions:")
      IO.puts("")
    else
      IO.puts("🔐  GitFoil Initialization")
      IO.puts("")
      IO.puts("This will:")
      IO.puts("")
    end

    # Show what will happen with encryption keys
    case key_action do
      :generate_new when force ->
        IO.puts("   🔑  Generate new encryption keys (--force flag)")
        IO.puts("      → Creates quantum-resistant keypair (Kyber1024)")
        IO.puts("      → Old key will be backed up automatically")
        IO.puts(new_storage_line)

      :generate_new ->
        IO.puts("   🔑  Generate encryption keys")
        IO.puts("      → Creates quantum-resistant keypair (Kyber1024)")
        IO.puts(new_storage_line)

      :use_existing when filters_configured? ->
        IO.puts("   🔑  Keep existing encryption key in place")
        IO.puts("      → Key already stored at #{plaintext_path}")
      :use_existing ->
        IO.puts("   🔑  Use existing encryption key")
        IO.puts(existing_location_line)
    end

    IO.puts("")

    if key_action == :use_existing and filters_configured? do
      IO.puts("   🔓  Decrypt working tree")
      IO.puts("      → Runs 'git checkout -- .' to rewrite tracked files locally")
      IO.puts("      → You can cancel if you prefer to decrypt later")
    else
      IO.puts("   🔒  Configure Git for automatic encryption")
      IO.puts("      → Files will encrypt automatically when you git add or git commit")
      IO.puts("      → Files will decrypt automatically when you git checkout or git pull")
      IO.puts("      → Only Git's internal storage is encrypted, not your working files")
    end

    IO.puts("")
    UIPrompts.print_separator()

    prompt_label =
      if key_action == :use_existing and filters_configured? do
        "Decrypt working tree now? [Y/n]: "
      else
        "Proceed with initialization? [Y/n]: "
      end

    answer = terminal.safe_gets("\n" <> prompt_label) |> String.downcase()

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
    keypair_result =
      terminal.with_spinner(
        "Generating quantum-resistant encryption keys",
        fn -> do_generate_keypair(3000, opts) end
      )

    case keypair_result do
      {:ok, _} ->
        IO.puts("✅  Generated quantum-resistant encryption keys")
        IO.puts("")

        # Second step: Configure filters
        filter_result =
          terminal.with_spinner(
            "Configuring Git filters for automatic encryption/decryption",
            fn -> do_configure_filters(3000, repository) end
          )

        case filter_result do
          :ok ->
            IO.puts("✅  Configured Git filters for automatic encryption/decryption")
            :ok

          error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp do_generate_keypair(min_duration, opts) do
    start_time = System.monotonic_time(:millisecond)
    use_password = Keyword.get(opts, :use_password, false)
    provided_password = Keyword.get(opts, :password_value)

    result =
      if use_password do
        password_result =
          case provided_password do
            nil ->
              password_opts =
                password_prompt_opts(opts,
                  confirm: true,
                  min_length: 8,
                  show_requirements: false
                )

              PasswordInput.new_password("Password for master key: ", password_opts)

            value ->
              {:ok, value}
          end

        case password_result do
          {:ok, pwd} ->
            case KeyManager.init_with_password(pwd) do
              {:ok, keypair} ->
                {:ok, keypair}

              {:error, reason} ->
                {:error, "Failed to initialize with password: #{UIPrompts.format_error(reason)}"}
            end

          {:error, error} ->
            {:error, error}
        end
      else
        # No password protection - use plaintext storage
        with {:ok, keypair} <- FileKeyStorage.generate_keypair(),
             :ok <- FileKeyStorage.store_keypair(keypair) do
          {:ok, keypair}
        else
          {:error, reason} ->
            {:error, "Failed to generate keypair: #{UIPrompts.format_error(reason)}"}
        end
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

    result =
      terminal.with_spinner(
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
    project_root = Path.expand("../../..", __DIR__)

    cond do
      running_from_source?(project_root) ->
        "cd '#{project_root}' && mix run -e 'GitFoil.CLI.main(System.argv())' --"

      exec_path = current_exec_path() ->
        exec_path

      executable = System.find_executable("git-foil") ->
        executable

      executable = System.find_executable("git-foil-dev") ->
        executable

      true ->
        "git-foil"
    end
  end

  defp running_from_source?(project_root) do
    case {maybe_mix_env(), File.exists?(Path.join(project_root, "mix.exs"))} do
      {{:ok, env}, true} when env in [:dev, :test] -> true
      _ -> false
    end
  end

  defp maybe_mix_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      {:ok, Mix.env()}
    else
      :error
    end
  end

  defp current_exec_path do
    case System.fetch_env("_") do
      {:ok, path} when path not in ["", "mix"] -> path
      _ -> nil
    end
  end

  # ============================================================================
  # File Encryption
  # ============================================================================

  defp maybe_encrypt_files(:skipped, _opts), do: {:ok, false}

  defp maybe_encrypt_files(_pattern_status, opts) do
    # Discover files and cache the list to avoid re-scanning
    case discover_files_to_encrypt(opts) do
      {:ok, []} ->
        IO.puts("")
        IO.puts("📝  No existing files found in repository.")
        IO.puts("    Files will be encrypted as you add them with git add/commit.")
        IO.puts("")
        {:ok, false}

      {:ok, files} ->
        # Pass the discovered files to avoid re-scanning
        offer_encryption(length(files), files, opts)

      {:error, reason} ->
        IO.puts("")
        IO.puts("⚠️   Warning: Could not check for files to encrypt.")
        IO.puts("    Reason: #{UIPrompts.format_error(reason)}")
        IO.puts("    Files will be encrypted as you add them with git add/commit.")
        IO.puts("")
        {:ok, false}
    end
  end

  defp maybe_process_existing_files(:use_existing, pattern_status, opts) do
    case maybe_refresh_working_tree(pattern_status, false, opts) do
      {:ok, _} -> {:ok, false}
    end
  end

  defp maybe_process_existing_files(_key_action, pattern_status, opts) do
    with {:ok, encrypted} <- maybe_encrypt_files(pattern_status, opts),
         {:ok, _} <- maybe_refresh_working_tree(pattern_status, encrypted, opts) do
      {:ok, encrypted}
    end
  end

  defp maybe_refresh_working_tree(:skipped, _encrypted, _opts), do: {:ok, false}
  defp maybe_refresh_working_tree(_pattern_status, true, _opts), do: {:ok, false}

  defp maybe_refresh_working_tree(_pattern_status, _encrypted, opts) do
    repository = Keyword.get(opts, :repository, Git)
    terminal = Keyword.get(opts, :terminal, Terminal)

    with {:ok, all_files} <- get_all_repository_files(opts),
         {:ok, matching_files} <- get_files_matching_patterns(all_files, opts),
         true <- matching_files != [] do
      prompt_refresh_working_tree(repository, terminal, length(matching_files))
    else
      _ -> {:ok, false}
    end
  end

  defp discover_files_to_encrypt(opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    repository = Keyword.get(opts, :repository, Git)

    with {:ok, all_files} <- get_all_repository_files(opts),
         {:ok, matching_files} <- get_files_matching_patterns(all_files, opts) do
      count = length(matching_files)
      show_progress? = count > 0

      if show_progress? do
        IO.puts("🔍  Searching for files to encrypt...")
        IO.write("   ")
      end

      case filter_addable_files(matching_files, repository,
             terminal: terminal,
             show_progress: show_progress?,
             total: count
           ) do
        {:ok, eligible_files, skipped} ->
          finish_progress(show_progress?)
          maybe_warn_skipped_files(skipped)

          if eligible_files != [] do
            IO.puts(
              "✅  Found #{terminal.format_number(length(eligible_files))} #{terminal.pluralize("file", length(eligible_files))} to encrypt"
            )
          end

          {:ok, eligible_files}

        {:error, reason} ->
          finish_progress(show_progress?)
          {:error, reason}
      end
    end
  end

  defp filter_addable_files(files, Git, opts) do
    show_progress? = Keyword.get(opts, :show_progress, false)
    total = Keyword.get(opts, :total, 1)
    terminal = Keyword.get(opts, :terminal, Terminal)
    chunk_size = Keyword.get(opts, :chunk_size, 200)

    files
    |> Enum.chunk_every(chunk_size, chunk_size, [])
    |> Enum.reduce_while({:ok, [], [], 0}, fn chunk, {:ok, acc, skipped, processed} ->
      {candidates, _non_candidates} = Enum.split_with(chunk, &file_addition_candidate?/1)
      new_processed = processed + length(chunk)
      render_progress(show_progress?, terminal, new_processed, total)

      case fetch_ignored_files(candidates) do
        {:ok, ignored_set} ->
          kept =
            Enum.reject(candidates, fn file -> MapSet.member?(ignored_set, file) end)

          updated_acc = Enum.reduce(Enum.reverse(kept), acc, fn file, list -> [file | list] end)

          updated_skipped =
            Enum.reduce(ignored_set, skipped, fn file, list -> [{file, :ignored} | list] end)

          {:cont, {:ok, updated_acc, updated_skipped, new_processed}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc, skipped, processed} ->
        render_progress(show_progress?, terminal, processed, total)
        {:ok, Enum.reverse(acc), Enum.reverse(skipped)}

      {:error, reason} ->
        finish_progress(show_progress?)
        {:error, reason}
    end
  end

  defp filter_addable_files(files, _mock_repository, _opts) do
    {:ok, files, []}
  end

  defp file_addition_candidate?(file) do
    File.exists?(file) && File.regular?(file)
  end

  defp render_progress(false, _terminal, _current, _total), do: :ok

  defp render_progress(true, terminal, current, total) do
    current = min(current, total)
    progress_bar = terminal.progress_bar(current, total)
    IO.write("\r\e[K   #{progress_bar} #{current}/#{total} files")
  end

  defp finish_progress(false), do: :ok
  defp finish_progress(true), do: IO.write("\n")

  defp maybe_warn_skipped_files([]), do: :ok

  defp maybe_warn_skipped_files(skipped) do
    count = length(skipped)

    IO.puts("")

    IO.puts(
      "⚠️  Skipping #{count} #{if count == 1, do: "file", else: "files"} ignored by Git patterns:"
    )

    skipped
    |> Enum.reverse()
    |> Enum.take(5)
    |> Enum.each(fn {file, _message} ->
      IO.puts("   • #{file}")
    end)

    if count > 5 do
      IO.puts("   • ...")
    end

    IO.puts("    (Use `git add -f <path>` if you intentionally want to include ignored files.)")
    IO.puts("")
  end

  defp fetch_ignored_files([]), do: {:ok, MapSet.new()}

  defp fetch_ignored_files(files) do
    files
    |> Enum.chunk_every(100)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn chunk, {:ok, acc} ->
      case System.cmd("git", ["check-ignore"] ++ chunk, stderr_to_stdout: true) do
        {output, status} when status in [0, 1] ->
          ignored =
            output
            |> String.split("\n", trim: true)
            |> MapSet.new()

          {:cont, {:ok, MapSet.union(acc, ignored)}}

        {error_output, status} ->
          message = "git check-ignore failed (status #{status}): #{String.trim(error_output)}"
          {:halt, {:error, message}}
      end
    end)
  end

  defp get_all_repository_files(opts) do
    repository = Keyword.get(opts, :repository, Git)
    repository.list_all_files()
  end

  defp offer_encryption(count, files, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    many_files = count > 100

    IO.puts("")
    IO.puts("💡  Encrypt existing files now?")
    IO.puts("")

    IO.puts(
      "   Found #{terminal.format_number(count)} #{terminal.pluralize("file", count)} matching your patterns."
    )

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
      encrypt_files_with_progress(files, opts)
    else
      IO.puts("")
      {:ok, false}
    end
  end

  defp encrypt_files_with_progress(files, opts) do
    terminal = Keyword.get(opts, :terminal, Terminal)
    count = length(files)

    IO.puts("")

    IO.puts(
      "🔒  Encrypting #{terminal.format_number(count)} #{terminal.pluralize("file", count)} matching your patterns..."
    )

    IO.puts("")

    with :ok <- add_files_with_progress(files, count, opts) do
      {:ok, true}
    end
  end

  defp get_files_matching_patterns(all_files, opts) do
    repository = Keyword.get(opts, :repository, Git)

    # Batch check all files at once instead of one-by-one to avoid spawning too many processes
    case repository.check_attr_batch("filter", all_files) do
      {:ok, results} ->
        # Use comprehension for single-pass filter+map (more idiomatic)
        # Note: check_attr_batch returns {file, value} where value is just "gitfoil" not "filter: gitfoil"
        matching_files =
          for {file, attr} <- results,
              attr == "gitfoil",
              do: file

        {:ok, matching_files}

      {:error, _reason} ->
        # Fallback to individual checks if batch fails
        # Note: check_attr returns full output like "file.txt: filter: gitfoil"
        matching_files =
          Enum.filter(all_files, fn file ->
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
    FileEncryption.add_files_with_progress(files, total, opts)
  end

  defp count_encrypted_candidates(opts) do
    with {:ok, all_files} <- get_all_repository_files(opts),
         {:ok, matching_files} <- get_files_matching_patterns(all_files, opts) do
      length(matching_files)
    else
      _ -> 0
    end
  end

  defp prompt_refresh_working_tree(repository, terminal, total) do
    IO.puts("")
    IO.puts("💡  Found #{total} encrypted tracked files in this working tree.")
    IO.puts("    GitFoil can decrypt them now so every file is readable.")
    IO.puts("    This will overwrite uncommitted changes to matching files.")
    IO.puts("")
    UIPrompts.print_separator()

    answer =
      terminal.safe_gets("\nDecrypt files now? [Y/n]: ")
      |> String.downcase()

    if affirmed?(answer) do
      case repository.checkout_working_tree() do
        :ok ->
          IO.puts("")
          IO.puts("✅  Working tree refreshed. Files decrypted locally.\n")
          {:ok, true}

        {:error, reason} ->
          IO.puts("")
          IO.puts("⚠️  Failed to refresh working tree: #{UIPrompts.format_error(reason)}")
          IO.puts("    Run 'git checkout -- .' manually when ready.\n")
          {:ok, false}
      end
    else
      IO.puts("")
      IO.puts("ℹ️  Skipping working tree refresh. Ciphertext will remain until you run 'git checkout -- .'.\n")
      {:ok, false}
    end
  end

  # ============================================================================
  # Messages
  # ============================================================================

  defp success_message(pattern_status, encrypted, opts) do
    repository = Keyword.get(opts, :repository, Git)
    use_password = Keyword.get(opts, :use_password, false)
    key_info = UIPrompts.master_key_info(repository: repository)
    encrypted_key_path = encrypted_key_path(repository)

    # Determine key protection message
    protection_message =
      if use_password do
        """
        Protected with password encryption (PBKDF2 + AES-256-GCM).
        Encrypted master key stored at:
        #{encrypted_key_path}
        """
      else
        ""
      end

    base_config = """
    ✅  GitFoil setup complete!

    🔐  Quantum-resistant encryption initialized:
       Generated Kyber1024 post-quantum keypair.
    #{protection_message}
       Enabled automatic encryption.
       Files will encrypt when you git add or git commit.
       Files will decrypt when you git checkout or git pull.
    """

    pattern_message = get_pattern_message(pattern_status, encrypted)

    warning =
      if use_password do
        """

        ⚠️  IMPORTANT: Remember your password!
           Your master key is encrypted with your password.
           Without the password, you cannot decrypt your files.
           There is NO password recovery mechanism.

           Encrypted key stored here:
           #{encrypted_key_path}
        """
      else
        """

        ⚠️  IMPORTANT: Back up your master.key!
           Without this key, you cannot decrypt your files.
           Store it securely in a password manager or encrypted backup.

           Your key can be found here:
           #{key_info.path}

           💡  Tip: Use --password flag to encrypt your key with a password:
              git-foil init --password --force
        """
      end

    base_config <> pattern_message <> warning
  end

  defp encrypted_key_path(repository) do
    case repository.repository_root() do
      {:ok, root} -> Path.join([root, ".git", "git_foil", "master.key.enc"])
      {:error, _} -> Path.expand(".git/git_foil/master.key.enc")
    end
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

       Or use git directly:
          git commit -m "Add encrypted files"
    """
  end

  defp get_pattern_message(:everything, false) do
    """

    🔒  Encryption is active! All files will be encrypted.
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

       Or use git directly:
          git commit -m "Add encrypted files"
    """
  end

  defp get_pattern_message(:secrets, false) do
    """

    🔒  Encryption is active!
       📋  Patterns configured:
          • Environment files (*.env, .env.*)
          • Secrets directory (secrets/**)
          • Key files (*.key, *.pem)
          • Credentials (credentials.json)
    """
  end

  defp get_pattern_message(:env_files, true) do
    """

    🔒  Encryption complete!
       📋  Environment files (*.env, .env.*) are encrypted and staged.

    💡  Next step - commit the encrypted files:
       git-foil commit

       Or use git directly:
          git commit -m "Add encrypted files"
    """
  end

  defp get_pattern_message(:env_files, false) do
    """

    🔒  Encryption is active!
       📋  Environment files will be encrypted (*.env, .env.*).
    """
  end

  defp get_pattern_message(:custom, true) do
    """

    🔒  Encryption complete!
       Custom patterns added to .gitattributes.
       All matching files are encrypted and staged.

    💡  Next step - commit the encrypted files:
       git-foil commit

       Or use git directly:
          git commit -m "Add encrypted files"
    """
  end

  defp get_pattern_message(:custom, false) do
    """

    🔒  Encryption is active!
       Custom patterns added to .gitattributes.
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Check if user answered affirmatively (y, yes, or empty for default yes)
  defp affirmed?(answer) when answer in ["", "y", "yes"], do: true
  defp affirmed?(_answer), do: false
end
