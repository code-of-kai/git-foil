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

  defp parse_args(["init" | rest]), do: {:init, parse_options(rest)}

  defp parse_args(["clean", file_path | rest]) when is_binary(file_path) do
    {:clean, [file_path: file_path] ++ parse_options(rest)}
  end

  defp parse_args(["smudge", file_path | rest]) when is_binary(file_path) do
    {:smudge, [file_path: file_path] ++ parse_options(rest)}
  end

  defp parse_args(["configure" | rest]), do: {:configure, parse_options(rest)}

  defp parse_args(["add-pattern", pattern | rest]) when is_binary(pattern) do
    {:add_pattern, [pattern: pattern] ++ parse_options(rest)}
  end

  defp parse_args(["remove-pattern", pattern | rest]) when is_binary(pattern) do
    {:remove_pattern, [pattern: pattern] ++ parse_options(rest)}
  end

  defp parse_args(["list-patterns" | rest]), do: {:list_patterns, parse_options(rest)}

  defp parse_args(["commit" | rest]), do: {:commit, parse_commit_options(rest)}

  defp parse_args(["encrypt", "key" | rest]), do: {:encrypt_key, parse_options(rest)}

  defp parse_args(["encrypt" | rest]), do: {:encrypt, parse_options(rest)}

  defp parse_args(["unencrypt", "key" | rest]), do: {:unencrypt_key, parse_options(rest)}

  defp parse_args(["unencrypt" | rest]), do: {:unencrypt, parse_options(rest)}

  defp parse_args(["rekey" | rest]), do: {:rekey, parse_options(rest)}

  defp parse_args(args) do
    {:error, "Unknown command: #{Enum.join(args, " ")}"}
  end

  defp parse_options(args) do
    args
    |> Enum.reduce([], fn
      "--verbose", acc -> [{:verbose, true} | acc]
      "-v", acc -> [{:verbose, true} | acc]
      "--force", acc -> [{:force, true} | acc]
      "-f", acc -> [{:force, true} | acc]
      "--skip-gitattributes", acc -> [{:skip_gitattributes, true} | acc]
      "--keep-key", acc -> [{:keep_key, true} | acc]
      "--password", acc -> [{:password, true} | acc]
      "--no-password", acc -> [{:password, false} | acc]
      _, acc -> acc
    end)
  end

  defp parse_commit_options(args) do
    case args do
      ["-m", message | rest] -> [{:message, message} | parse_options(rest)]
      ["--message", message | rest] -> [{:message, message} | parse_options(rest)]
      rest -> parse_options(rest)
    end
  end

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

    # Process clean filter: plaintext (stdin) → encrypted (stdout)
    # GitFilter.process handles all I/O directly
    case GitFoil.Adapters.GitFilter.process(:clean, file_path) do
      {:ok, 0} -> {:ok, ""}
      {:error, exit_code} -> {:error, exit_code}
    end
  end

  defp execute({:smudge, opts}) do
    file_path = Keyword.fetch!(opts, :file_path)

    # Process smudge filter: encrypted (stdin) → plaintext (stdout)
    # GitFilter.process handles all I/O directly
    case GitFoil.Adapters.GitFilter.process(:smudge, file_path) do
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

  defp handle_result({:error, message}) when is_binary(message) do
    IO.puts(:stderr, "Error: #{message}")
    IO.puts(:stderr, "\nRun 'git-foil help' for usage information.")
    System.halt(1)
  end

  defp handle_result({:error, exit_code}) when is_integer(exit_code) do
    System.halt(exit_code)
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
    """
  end
end
