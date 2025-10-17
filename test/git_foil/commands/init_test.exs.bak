defmodule GitFoil.Commands.InitTest do
  use ExUnit.Case, async: false  # Not async because we create .gitattributes files

  alias GitFoil.Commands.Init

  # Clean up before each test to avoid state pollution
  setup do
    # Clean up any leftover files from previous tests
    File.rm(".gitattributes")
    File.rm_rf(".git/git_foil")

    on_exit(fn ->
      # Clean up after test
      File.rm(".gitattributes")
      File.rm_rf(".git/git_foil")

      # Clear mock configuration
      Process.delete(:mock_git_config)
      Process.delete(:mock_terminal_config)
      Process.delete(:mock_terminal_inputs)
    end)

    :ok
  end

  # ============================================================================
  # Mock Implementations
  # ============================================================================

  defmodule MockGit do
    @moduledoc """
    Mock Git repository for testing - implements GitFoil.Ports.Repository

    Store configuration in process dictionary for stateful mocking.
    """

    def configure(opts \\ []) do
      Process.put(:mock_git_config, opts)
    end

    def verify_repository do
      get_mock(:verify_repository, fn -> {:ok, ".git"} end).()
    end

    def init_repository do
      get_mock(:init_repository, fn -> {:ok, "Initialized"} end).()
    end

    def get_config(key) do
      get_mock(:get_config, fn _k -> {:error, :not_found} end).(key)
    end

    def set_config(key, value) do
      get_mock(:set_config, fn _k, _v -> :ok end).(key, value)
    end

    def list_files do
      get_mock(:list_files, fn -> {:ok, []} end).()
    end

    def list_all_files do
      get_mock(:list_all_files, fn -> {:ok, []} end).()
    end

    def check_attr(attr, file) do
      get_mock(:check_attr, fn _a, _f -> {:ok, "unspecified"} end).(attr, file)
    end

    def add_file(file) do
      get_mock(:add_file, fn _f -> :ok end).(file)
    end

    def repository_root do
      get_mock(:repository_root, fn -> {:ok, "/test/repo"} end).()
    end

    def config_exists?(key) do
      get_mock(:config_exists?, fn _k -> false end).(key)
    end

    defp get_mock(key, default) do
      config = Process.get(:mock_git_config, [])
      Keyword.get(config, key, default)
    end
  end

  defmodule MockTerminal do
    @moduledoc """
    Mock Terminal for testing - implements GitFoil.Ports.Terminal

    Store configuration in process dictionary for stateful mocking.
    """

    def configure(opts \\ []) do
      Process.put(:mock_terminal_config, opts)

      # Store inputs for sequential reading
      if inputs = Keyword.get(opts, :inputs) do
        Process.put(:mock_terminal_inputs, inputs)
      end
    end

    def safe_gets(prompt) do
      get_mock(:safe_gets, fn _p ->
        # Default behavior: consume from inputs list
        case Process.get(:mock_terminal_inputs, []) do
          [input | rest] ->
            Process.put(:mock_terminal_inputs, rest)
            input
          [] ->
            ""
        end
      end).(prompt)
    end

    def with_spinner(label, work_fn, opts \\ []) do
      # Default mock accepts 3 arguments
      default_fn = fn _l, wf, _o -> wf.() end
      mock_fn = get_mock(:with_spinner, default_fn)

      # Handle both 2-arg and 3-arg mocks for flexibility
      case :erlang.fun_info(mock_fn)[:arity] do
        2 -> mock_fn.(label, work_fn)
        3 -> mock_fn.(label, work_fn, opts)
        _ -> default_fn.(label, work_fn, opts)
      end
    end

    def progress_bar(current, total, width \\ 20) do
      get_mock(:progress_bar, fn _c, _t, _w -> "████████" end).(current, total, width)
    end

    def format_number(number) do
      get_mock(:format_number, fn n -> Integer.to_string(n) end).(number)
    end

    def pluralize(word, count) do
      get_mock(:pluralize, fn w, 1 -> w; w, _ -> w <> "s" end).(word, count)
    end

    defp get_mock(key, default) do
      config = Process.get(:mock_terminal_config, [])
      Keyword.get(config, key, default)
    end
  end

  # ============================================================================
  # Error Path Tests - Git Failures
  # ============================================================================

  describe "git repository verification" do
    test "handles missing git repository gracefully when user declines to create one" do
      MockGit.configure(
        verify_repository: fn -> {:error, "not a git repository"} end
      )

      MockTerminal.configure(
        inputs: ["n"] # User says no to creating repo
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      assert {:error, msg} = result
      assert msg =~ "git init"
    end

    test "creates git repository when user confirms" do
      MockGit.configure(
        verify_repository: fn -> {:error, "not a git repository"} end,
        init_repository: fn -> {:ok, "Initialized empty Git repository"} end
      )

      MockTerminal.configure(
        inputs: [
          "y",    # Yes, create git repo
          "y"     # Yes, proceed with initialization
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      # Should succeed after creating repo
      assert {:ok, _msg} = result
    end

    test "handles git init failure" do
      MockGit.configure(
        verify_repository: fn -> {:error, "not a git repository"} end,
        init_repository: fn -> {:error, "permission denied"} end
      )

      MockTerminal.configure(
        inputs: ["y"] # User tries to create repo
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      assert {:error, msg} = result
      assert msg =~ "Failed to initialize Git repository"
    end
  end

  describe "git configuration failures" do
    test "handles git config set failure" do
      MockGit.configure(
        verify_repository: fn -> {:ok, ".git"} end,
        set_config: fn _key, _value -> {:error, "config file locked"} end
      )

      MockTerminal.configure(
        inputs: ["y"], # Confirm initialization
        with_spinner: fn _label, work_fn -> work_fn.() end
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      assert {:error, _msg} = result
    end

    test "detects already configured filters" do
      MockGit.configure(
        verify_repository: fn -> {:ok, ".git"} end,
        config_exists?: fn "filter.gitfoil.clean" -> true; _ -> false end
      )

      MockTerminal.configure(
        inputs: ["y"] # Confirm initialization
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      # Should succeed - filters already configured
      assert {:ok, _msg} = result
    end
  end

  # ============================================================================
  # User Interaction Path Tests
  # ============================================================================

  describe "key choice prompts" do
    setup do
      # Setup for tests where key already exists
      File.mkdir_p!(".git/git_foil")
      File.write!(".git/git_foil/master.key", "fake_key_data")

      on_exit(fn ->
        File.rm_rf!(".git/git_foil")
      end)

      :ok
    end

    test "user chooses to use existing key" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "1",  # Use existing key
          "y"   # Confirm initialization
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      assert {:ok, msg} = result
      assert msg =~ "setup complete"
    end

    test "user chooses to exit initialization" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: ["3"] # Exit
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      # Exit returns {:ok, ""} per the code
      assert {:ok, ""} = result
    end

    test "user declines initialization at confirmation" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "1",  # Use existing key
          "n"   # Don't proceed with initialization
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true
      )

      assert {:ok, ""} = result
    end
  end

  describe "pattern configuration" do
    test "user chooses everything pattern" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "1"   # Everything pattern
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, msg} = result
      assert msg =~ "setup complete"
    end

    test "user chooses secrets pattern" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "2"   # Secrets pattern
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, msg} = result
      assert msg =~ "setup complete"
    end

    test "user chooses to decide later" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "5"   # Decide later
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, msg} = result
      assert msg =~ "Pattern configuration postponed"
    end

    test "user enters custom patterns" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "y",        # Confirm initialization
          "4",        # Custom patterns
          "*.secret", # First pattern
          "*.key",    # Second pattern
          ""          # Done
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, msg} = result
      assert msg =~ "setup complete"
    end

    test "user enters custom patterns but then provides none" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "4",  # Custom patterns
          ""    # Immediately done (no patterns)
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, msg} = result
      assert msg =~ "setup complete"
    end
  end

  # ============================================================================
  # File Encryption Tests
  # ============================================================================

  describe "file encryption" do
    test "handles git ls-files failure" do
      MockGit.configure(
        list_files: fn -> {:error, "failed to list files"} end
      )

      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "1"   # Everything pattern
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      # Should still complete, just skip encryption
      assert {:ok, _msg} = result
    end

    test "offers encryption when files are found" do
      MockGit.configure(
        list_files: fn -> {:ok, ["file1.txt", "file2.txt"]} end,
        check_attr: fn _attr, _file -> {:ok, "file: filter: gitfoil"} end
      )

      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "1",  # Everything pattern
          "n"   # Don't encrypt now
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, _msg} = result
    end

    test "encrypts files when user confirms" do
      MockGit.configure(
        list_all_files: fn -> {:ok, ["file1.txt", "file2.txt"]} end,
        check_attr: fn _attr, _file -> {:ok, "file: filter: gitfoil"} end,
        add_file: fn _file -> :ok end
      )

      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "1",  # Everything pattern
          "y"   # Encrypt now
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, msg} = result
      assert msg =~ "Encryption complete"
    end

    test "handles git add failure during encryption" do
      MockGit.configure(
        list_all_files: fn -> {:ok, ["file1.txt", "file2.txt"]} end,
        check_attr: fn _attr, _file -> {:ok, "file: filter: gitfoil"} end,
        add_file: fn _file -> {:error, "disk full"} end
      )

      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "1",  # Everything pattern
          "y"   # Encrypt now
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:error, msg} = result
      assert msg =~ "Failed to encrypt"
    end
  end

  # ============================================================================
  # Edge Cases and Regression Tests
  # ============================================================================

  describe "edge cases" do
    test "handles invalid pattern choice gracefully" do
      MockGit.configure()
      MockTerminal.configure(
        inputs: [
          "y",   # Confirm initialization
          "99"   # Invalid choice
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:error, msg} = result
      assert msg =~ "Invalid choice"
    end

    test "handles repository_root failure" do
      MockGit.configure(
        repository_root: fn -> {:error, "cannot determine root"} end
      )

      MockTerminal.configure(
        inputs: [
          "y",  # Confirm initialization
          "5"   # Decide later (avoids file operations)
        ]
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      # Should still succeed, just use fallback path
      assert {:ok, _msg} = result
    end

    test "works with force flag to skip existing key check" do
      # Create existing key
      File.mkdir_p!(".git/git_foil")
      File.write!(".git/git_foil/master.key", "old_key")

      MockGit.configure()
      MockTerminal.configure(
        inputs: ["y"], # Confirm initialization
        with_spinner: fn _label, work_fn -> work_fn.() end
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal,
        skip_patterns: true,
        force: true
      )

      assert {:ok, _msg} = result

      # Cleanup
      File.rm_rf!(".git/git_foil")
    end
  end

  # ============================================================================
  # Terminal UI Helper Tests
  # ============================================================================

  describe "terminal helpers" do
    test "progress bar formatting works" do
      MockGit.configure(
        list_files: fn -> {:ok, ["file1.txt"]} end,
        check_attr: fn _attr, _file -> {:ok, "file: filter: gitfoil"} end,
        add_file: fn _file -> :ok end
      )

      MockTerminal.configure(
        inputs: ["y", "1", "y"], # Confirm, Everything, Encrypt
        progress_bar: fn current, total, _width ->
          percentage = trunc(current / total * 100)
          "████ #{percentage}%"
        end
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, _msg} = result
    end

    test "number formatting is used" do
      MockGit.configure(
        list_all_files: fn -> {:ok, Enum.map(1..1000, fn i -> "file#{i}.txt" end)} end,
        check_attr: fn _attr, _file -> {:ok, "file: filter: gitfoil"} end
      )

      format_number_called = make_ref()
      Process.put(format_number_called, false)

      MockTerminal.configure(
        inputs: [
          "y",  # Confirm
          "1",  # Everything
          "n"   # Don't encrypt
        ],
        format_number: fn n ->
          Process.put(format_number_called, true)
          Integer.to_string(n)
        end
      )

      result = Init.run(
        repository: MockGit,
        terminal: MockTerminal
      )

      assert {:ok, _msg} = result
      assert Process.get(format_number_called) == true
    end
  end
end
