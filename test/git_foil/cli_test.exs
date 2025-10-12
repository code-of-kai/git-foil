defmodule GitFoil.CLITest do
  use ExUnit.Case, async: false

  alias GitFoil.CLI

  setup do
    # Start key storage for tests that need it
    {:ok, _} = start_supervised(GitFoil.Adapters.InMemoryKeyStorage)

    {:ok, keypair} = GitFoil.Adapters.InMemoryKeyStorage.generate_keypair()
    :ok = GitFoil.Adapters.InMemoryKeyStorage.store_keypair(keypair)

    :ok
  end

  describe "help command" do
    test "returns help text with no arguments" do
      {:ok, output} = CLI.run([])
      assert output =~ "GitFoil - Quantum-resistant Git encryption"
    end

    test "returns help text with 'help' command" do
      {:ok, output} = CLI.run(["help"])
      assert output =~ "USAGE:"
    end

    test "returns help text with --help flag" do
      {:ok, output} = CLI.run(["--help"])
      assert output =~ "COMMANDS:"
    end

    test "returns help text with -h flag" do
      {:ok, output} = CLI.run(["-h"])
      assert output =~ "git-foil <command>"
    end
  end

  describe "version command" do
    test "shows version" do
      {:ok, output} = CLI.run(["version"])
      assert output =~ "GitFoil version"
    end

    test "shows version with --version flag" do
      {:ok, output} = CLI.run(["--version"])
      assert output =~ "version"
    end

    test "shows version with -v flag" do
      {:ok, output} = CLI.run(["-v"])
      assert output =~ "version"
    end
  end

  describe "init command" do
    test "shows already initialized message when run in initialized repo" do
      {:error, message} = CLI.run(["init"])
      assert message =~ "already initialized"
    end
  end

  describe "error handling" do
    test "returns error for unknown command" do
      {:error, message} = CLI.run(["unknown", "command"])
      assert message =~ "Unknown command"
    end
  end

  describe "clean and smudge commands" do
    # Note: These commands read from stdin and write to stdout
    # Full integration tests would require subprocess execution
    # For now, we just test they parse correctly and execute

    test "clean command parses correctly" do
      # This would normally read from stdin
      # Just verify it doesn't crash and returns success
      {:ok, output} = CLI.run(["clean", "test.env"])
      assert output == ""  # Git filter writes to stdout directly, not return value
    end

    test "smudge command parses correctly" do
      {:ok, output} = CLI.run(["smudge", "test.env"])
      assert output == ""
    end
  end

  describe "argument parsing" do
    test "parses clean command with file path" do
      result = CLI.run(["clean", "secrets.env"])
      assert match?({:ok, _}, result)
    end

    test "parses smudge command with file path" do
      result = CLI.run(["smudge", "config.yml"])
      assert match?({:ok, _}, result)
    end
  end
end
