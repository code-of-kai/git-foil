defmodule GitFoil.CLI do
  @moduledoc """
  Command-line interface for GitFoil.

  ## Commands

  - `init` - Initialize GitFoil in the current Git repository
  - `clean <file>` - Clean filter (working tree → repository)
  - `smudge <file>` - Smudge filter (repository → working tree)
  - `version` - Show version information
  - `help` - Show help message

  ## Git Filter Integration

  GitFoil is designed to be used as a Git clean/smudge filter:

  ```
  [filter "gitfoil"]
    clean = git_foil clean %f
    smudge = git_foil smudge %f
    required = true
  ```

  Files matching `.gitattributes` patterns will be automatically encrypted:

  ```
  *.env filter=gitfoil
  secrets/** filter=gitfoil
  ```
  """

  alias GitFoil.Commands.{
    Commit,
    Encrypt,
    EncryptKey,
    Init,
    Pattern,
    Rekey,
    Unencrypt,
    UnencryptKey
  }

  @version Mix.Project.config()[:version] || "dev"

  @doc """
  Main CLI entry point.

  Parses arguments and dispatches to appropriate command.
  """
  def main(args) do
    setup_signal_handlers()
    result = run(args)
    handle_result(result)
  end

  @doc """
  Run command without halting (for testing).

  Returns the result tuple instead of exiting.
  """
  def run(args) do
    parse_args(args)
    |> execute()
  end

  # ============================================================================
  # Argument Parsing
  # ============================================================================

  defp parse_args([]), do: {:help, []}
  defp parse_args(["help", "patterns" | _]), do: {:help_patterns, []}
  defp parse_args(["help" | _]), do: {:help, []}
  defp parse_args(["--help" | _]), do: {:help, []}
  defp parse_args(["-h" | _]), do: {:help, []}

  defp parse_args(["version" | _]), do: {:version, []}
  defp parse_args(["--version" | _]), do: {:version, []}
  defp parse_args(["-v" | _]), do: {:version, []}

  defp parse_args(["init" | rest]), do: with_parsed_options(rest, &{:init, &1})

  defp parse_args(["clean", file_path | rest]) when is_binary(file_path) do
    with_parsed_options(rest, fn opts ->
      {:clean, Keyword.put(opts, :file_path, file_path)}
    end)
  end

  defp parse_args(["smudge", file_path | rest]) when is_binary(file_path) do
    with_parsed_options(rest, fn opts ->
      {:smudge, Keyword.put(opts, :file_path, file_path)}
    end)
  end

  defp parse_args(["configure" | rest]), do: with_parsed_options(rest, &{:configure, &1})

  defp parse_args(["add-pattern", pattern | rest]) when is_binary(pattern) do
    with_parsed_options(rest, fn opts ->
      {:add_pattern, Keyword.put(opts, :pattern, pattern)}
    end)
  end

  defp parse_args(["remove-pattern", pattern | rest]) when is_binary(pattern) do
    with_parsed_options(rest, fn opts ->
      {:remove_pattern, Keyword.put(opts, :pattern, pattern)}
    end)
  end

  defp parse_args(["list-patterns" | rest]), do: with_parsed_options(rest, &{:list_patterns, &1})

  defp parse_args(["commit" | rest]) do
    case parse_commit_options(rest) do
      {:ok, opts} -> {:commit, opts}
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_args(["encrypt", "key" | rest]), do: with_parsed_options(rest, &{:encrypt_key, &1})

  defp parse_args(["encrypt" | rest]), do: with_parsed_options(rest, &{:encrypt, &1})

  defp parse_args(["unencrypt", "key" | rest]), do: with_parsed_options(rest, &{:unencrypt_key, &1})

  defp parse_args(["unencrypt" | rest]), do: with_parsed_options(rest, &{:unencrypt, &1})

  defp parse_args(["rekey" | rest]), do: with_parsed_options(rest, &{:rekey, &1})

  defp parse_args(args), do: {:error, "Unknown command: #{Enum.join(args, " ")}"}

  defp with_parsed_options(args, fun) when is_function(fun, 1) do
    case parse_options(args) do
      {:ok, opts} -> fun.(opts)
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_options(args), do: do_parse_options(args, [])

  defp do_parse_options([], acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse_options(["--verbose" | rest], acc), do: do_parse_options(rest, [{:verbose, true} | acc])
  defp do_parse_options(["-v" | rest], acc), do: do_parse_options(rest, [{:verbose, true} | acc])
  defp do_parse_options(["--force" | rest], acc), do: do_parse_options(rest, [{:force, true} | acc])
  defp do_parse_options(["-f" | rest], acc), do: do_parse_options(rest, [{:force, true} | acc])
  defp do_parse_options(["--skip-gitattributes" | rest], acc), do: do_parse_options(rest, [{:skip_gitattributes, true} | acc])
  defp do_parse_options(["--skip-patterns" | rest], acc), do: do_parse_options(rest, [{:skip_patterns, true} | acc])
  defp do_parse_options(["--keep-key" | rest], acc), do: do_parse_options(rest, [{:keep_key, true} | acc])
  defp do_parse_options(["--password" | rest], acc), do: do_parse_options(rest, [{:password, true} | acc])
  defp do_parse_options(["--no-password" | rest], acc), do: do_parse_options(rest, [{:password, false} | acc])
  defp do_parse_options(["--password-stdin" | rest], acc), do: add_password_source(:stdin, acc, rest)
  defp do_parse_options(["--password-file", path | rest], acc) when is_binary(path), do: add_password_source({:file, path}, acc, rest)
  defp do_parse_options(["--password-fd", fd | rest], acc), do: parse_password_fd(fd, acc, rest)
  defp do_parse_options(["--no-confirm" | rest], acc), do: do_parse_options(rest, [{:password_no_confirm, true} | acc])

  defp do_parse_options([<<"--password-file=", path::binary>> | rest], acc),
    do: add_password_source({:file, path}, acc, rest)

  defp do_parse_options([<<"--password-fd=", value::binary>> | rest], acc),
    do: parse_password_fd(value, acc, rest)

  defp do_parse_options([unknown | _rest], _acc) when unknown in ["--password-file", "--password-fd"] do
    {:error, "Missing value for #{unknown}"}
  end

  defp do_parse_options([_arg | rest], acc), do: do_parse_options(rest, acc)

  defp parse_password_fd(value, acc, rest) do
    with {fd, ""} <- Integer.parse(value),
         true <- fd >= 0 do
      add_password_source({:fd, fd}, acc, rest)
    else
      _ -> {:error, "Invalid value for --password-fd: #{value}"}
    end
  end

  defp add_password_source(source, acc, rest) do
    if Keyword.has_key?(acc, :password_source) do
      {:error, "Multiple password sources specified. Choose only one of --password-stdin, --password-file, or --password-fd."}
    else
      do_parse_options(rest, [{:password_source, source} | acc])
    end
  end

  defp parse_commit_options(args) do
    with {:ok, message_opts, rest} <- extract_commit_message(args, []) do
      case parse_options(rest) do
        {:ok, opts} -> {:ok, message_opts ++ opts}
        {:error, msg} -> {:error, msg}
      end
    end
  end

  defp extract_commit_message(["-m", message | rest], acc),
    do: extract_commit_message(rest, [{:message, message} | acc])

  defp extract_commit_message(["--message", message | rest], acc),
    do: extract_commit_message(rest, [{:message, message} | acc])

  defp extract_commit_message([<<"--message=", message::binary>> | rest], acc),
    do: extract_commit_message(rest, [{:message, message} | acc])

  defp extract_commit_message(args, acc), do: {:ok, Enum.reverse(acc), args}

  # ============================================================================
  # Command Execution
  # ============================================================================

  defp execute({:help, _opts}) do
    {:ok, help_text()}
  end

  defp execute({:version, _opts}) do
    {:ok, "GitFoil version #{@version}"}
  end

  defp execute({:init, opts}) do
    case Init.run(opts) do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute({:clean, opts}) do
    file_path = Keyword.fetch!(opts, :file_path)
    filter_opts = Keyword.delete(opts, :file_path)

    # Process clean filter: plaintext (stdin) → encrypted (stdout)
    # GitFilter.process handles all I/O directly
    case GitFoil.Adapters.GitFilter.process(:clean, file_path, filter_opts) do
      {:ok, 0} -> {:ok, ""}
      {:error, exit_code} -> {:error, exit_code}
    end
  end

  defp execute({:smudge, opts}) do
    file_path = Keyword.fetch!(opts, :file_path)
    filter_opts = Keyword.delete(opts, :file_path)

    # Process smudge filter: encrypted (stdin) → plaintext (stdout)
    # GitFilter.process handles all I/O directly
    case GitFoil.Adapters.GitFilter.process(:smudge, file_path, filter_opts) do
      {:ok, 0} -> {:ok, ""}
      {:error, exit_code} -> {:error, exit_code}
    end
  end

  defp execute({:configure, _opts}) do
    Pattern.configure()
  end

  defp execute({:add_pattern, opts}) do
    pattern = Keyword.fetch!(opts, :pattern)
    Pattern.add(pattern)
  end

  defp execute({:remove_pattern, opts}) do
    pattern = Keyword.fetch!(opts, :pattern)
    Pattern.remove(pattern)
  end

  defp execute({:list_patterns, _opts}) do
    Pattern.list()
  end

  defp execute({:help_patterns, _opts}) do
    Pattern.help()
  end

  defp execute({:commit, opts}) do
    Commit.run(opts)
  end

  defp execute({:encrypt, opts}) do
    Encrypt.run(opts)
  end

  defp execute({:encrypt_key, opts}) do
    EncryptKey.run(opts)
  end

  defp execute({:unencrypt, opts}) do
    Unencrypt.run(opts)
  end

  defp execute({:unencrypt_key, opts}) do
    UnencryptKey.run(opts)
  end

  defp execute({:rekey, opts}) do
    Rekey.run(opts)
  end

  defp execute({:error, message}) do
    {:error, message}
  end

  # ============================================================================
  # Result Handling
  # ============================================================================

  defp handle_result({:ok, output}) when is_binary(output) do
    if output != "" do
      IO.puts(output)
    end

    System.halt(0)
  end

  defp handle_result({:error, {exit_code, message}})
       when is_integer(exit_code) and is_binary(message) do
    IO.puts(:stderr, message)
    System.halt(exit_code)
  end

  defp handle_result({:error, message}) when is_binary(message) do
    IO.puts(:stderr, "Error: #{message}")
    IO.puts(:stderr, "\nRun 'git-foil help' for usage information.")
    System.halt(1)
  end

  defp handle_result({:error, exit_code}) when is_integer(exit_code) do
    System.halt(exit_code)
  end

  defp setup_signal_handlers do
    Enum.each([:sigint, :sigterm, :sigquit], &install_signal_handler/1)
  end

  defp install_signal_handler(signal) do
    System.trap_signal(signal, fn ->
      IO.puts(:stderr, "\nInterrupted")
      System.halt(130)
    end)
  rescue
    ArgumentError -> :ok
    FunctionClauseError -> :ok
  end

  # ============================================================================
  # Help Text
  # ============================================================================

  defp help_text do
    """
    GitFoil - Quantum-resistant Git encryption

    USAGE:
        git-foil <command> [options]

    COMMANDS:
        init                        Initialize GitFoil in current Git repository
        configure                   Configure encryption patterns (interactive)
        add-pattern <pattern>       Add encryption pattern to .gitattributes
        remove-pattern <pattern>    Remove encryption pattern from .gitattributes
        list-patterns               List all configured encryption patterns
        encrypt                     Encrypt all files matching patterns
        encrypt key                 Protect master key with a password
        unencrypt                   Remove all GitFoil encryption (decrypt all files)
        unencrypt key               Store master key without password
        rekey                       Rekey repository (generate new keys or refresh with existing)
        commit                      Commit .gitattributes changes
        version                     Show version information
        help                        Show this help message
        help patterns               Show pattern syntax help

    OPTIONS:
        --verbose, -v               Show verbose output
        --help, -h                  Show help
        --force, -f                 Force overwrite (for init command)
        --skip-patterns             Skip pattern configuration during init
        --keep-key                  Preserve encryption key when unencrypting
        --password                  Require password protection during init/rekey
        --no-password               Disable password protection during init/rekey
        --password-stdin            Read password from stdin (non-interactive)
        --password-file <path>      Read password (and optional confirmation) from file
        --password-fd <fd>          Read password from file descriptor
        --no-confirm                Skip confirmation when providing password non-interactively

    GETTING STARTED:

        1. Initialize GitFoil
           git-foil init

        2. Configure which files to encrypt (interactive menu)
           git-foil configure

        3. Or add patterns manually
           git-foil add-pattern "*.env"
           git-foil add-pattern "secrets/**"

    PATTERN MANAGEMENT:

        # Configure encryption patterns interactively
        git-foil configure

        # Add a pattern
        git-foil add-pattern "*.env"

        # Remove a pattern
        git-foil remove-pattern "*.env"

        # List all patterns
        git-foil list-patterns

        # Get help with pattern syntax
        git-foil help patterns

    OTHER COMMANDS:

        # Reinitialize with new keypair (destroys old key!)
        git-foil init --force

    For more information, visit: https://github.com/code-of-kai/git-foil
  
  Commands
  - init                Initialize in current repo
  - encrypt key         Encrypt master key with a password
  - unencrypt key       Remove password protection from master key
  - rekey               Rotate keys or re-apply encryption
  - configure           Interactive pattern setup
  - add-pattern <glob>  Add encryption pattern
  - list-patterns       List configured patterns
  - commit              Commit staged changes with guidance

  For more, see README.md (Setup, Non-interactive prompts).
  """
  end
end
