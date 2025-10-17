defmodule GitFoil.Test.GitTestHelper do
  @moduledoc """
  Helper module for creating and managing real git repositories in tests.

  This module provides utilities for integration testing with actual git repos,
  avoiding mocks to catch real-world bugs.
  """

  @doc """
  Creates a temporary git repository for testing.

  Returns the path to the temporary directory.
  The repo is initialized with git and has basic config set.

  ## Example

      test "something with git" do
        repo_path = create_test_repo()
        # ... test code ...
        cleanup_test_repo(repo_path)
      end
  """
  def create_test_repo do
    # Create unique temp directory
    timestamp = System.system_time(:microsecond)
    tmp_dir = Path.join(System.tmp_dir!(), "gitfoil_test_#{timestamp}")
    File.mkdir_p!(tmp_dir)

    # Initialize git repo
    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)

    tmp_dir
  end

  @doc """
  Cleans up a test repository.
  """
  def cleanup_test_repo(repo_path) do
    File.rm_rf!(repo_path)
  end

  @doc """
  Creates a file in the test repo with given content.

  Returns the absolute path to the created file.
  """
  def create_file(repo_path, filename, content) do
    file_path = Path.join(repo_path, filename)
    File.write!(file_path, content)
    file_path
  end

  @doc """
  Runs git-foil init in the test repo.

  Automatically answers prompts with defaults (yes, encrypt everything, yes encrypt now).
  """
  def run_init(repo_path) do
    default_answers =
      ["y", test_password(), test_password(), "y", "1", "y"]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    run_init_with_answers(repo_path, default_answers)
  end

  @doc """
  Runs git-foil unencrypt in the test repo.

  Automatically answers prompts with yes.
  """
  def run_unencrypt(repo_path) do
    # Answer yes to both confirmation prompts
    answers = "y\nyes\n"

    run_cli(repo_path, "unencrypt", answers)
  end

  @doc """
  Runs git-foil init with custom answers.
  """
  def run_init_with_answers(repo_path, answers) do
    run_cli(repo_path, "init", answers)
  end

  @doc """
  Commits files in the test repo.
  """
  def commit_files(repo_path, message \\ "Test commit") do
    {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
    {output, exit_code} = System.cmd("git", ["commit", "-m", message], cd: repo_path)
    {output, exit_code}
  end

  @doc """
  Checks if a file is encrypted in git storage.

  Returns the first byte of the file as stored in git.
  For encrypted files with 6-layer encryption, this should be 0x03.

  Checks the staged version if not committed yet, otherwise HEAD.
  """
  def get_encrypted_first_byte(repo_path, filename) do
    # Try staged version first (:filename)
    case System.cmd("git", ["show", ":#{filename}"], cd: repo_path, stderr_to_stdout: true) do
      {output, 0} ->
        case output do
          <<first_byte, _rest::binary>> -> first_byte
          _ -> nil
        end

      _ ->
        # Fall back to HEAD
        case System.cmd("git", ["show", "HEAD:#{filename}"], cd: repo_path, stderr_to_stdout: true) do
          {output, 0} ->
            case output do
              <<first_byte, _rest::binary>> -> first_byte
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  @doc """
  Checks if a file is plaintext in git storage.

  Returns true if the file in git starts with printable ASCII (not encrypted).
  Checks staged version first, then HEAD.
  """
  def is_plaintext_in_git?(repo_path, filename) do
    # Try staged version first
    result = case System.cmd("git", ["show", ":#{filename}"], cd: repo_path, stderr_to_stdout: true) do
      {output, 0} ->
        case output do
          <<first_byte, _rest::binary>> when first_byte >= 32 and first_byte <= 126 -> true
          _ -> false
        end

      _ ->
        # Fall back to HEAD
        case System.cmd("git", ["show", "HEAD:#{filename}"], cd: repo_path, stderr_to_stdout: true) do
          {output, 0} ->
            case output do
              <<first_byte, _rest::binary>> when first_byte >= 32 and first_byte <= 126 -> true
              _ -> false
            end

          _ ->
            false
        end
    end

    result
  end

  @doc """
  Checks if git-foil is initialized (has master key).
  """
  def gitfoil_initialized?(repo_path) do
    File.exists?(Path.join([repo_path, ".git", "git_foil", "master.key"]))
  end

  @doc """
  Checks if git filters are configured.
  """
  def filters_configured?(repo_path) do
    {output, exit_code} = System.cmd(
      "git",
      ["config", "--get", "filter.gitfoil.clean"],
      cd: repo_path
    )

    exit_code == 0 and String.trim(output) != ""
  end

  @doc """
  Stages files that are already committed (for testing re-encryption scenarios).
  """
  def stage_committed_files(repo_path) do
    # Get list of tracked files
    {files, 0} = System.cmd("git", ["ls-files"], cd: repo_path)

    files
    |> String.split("\n", trim: true)
    |> Enum.each(fn file ->
      System.cmd("git", ["add", file], cd: repo_path)
    end)
  end

  defp get_git_foil_command do
    # Get project root (assumes we're in test/support/)
    project_root = Path.expand("../..", __DIR__)
    dev_escript = Path.join(project_root, "git-foil-dev")

    if File.exists?(dev_escript) do
      {:escript, dev_escript}
    else
      {:mix, project_root}
    end
  end

  defp build_command({:escript, path}, subcommand, _repo_path, answers) do
    env = password_env_prefix(answers)
    "#{env}#{path} #{subcommand}"
  end

  defp build_command({:mix, project_root}, subcommand, repo_path, answers) do
    escaped_root = escape_path(project_root)
    escaped_repo = escape_path(repo_path)
    eval =
      "File.cd!(System.get_env(\"GIT_FOIL_TEST_REPO\")); GitFoil.CLI.main(System.argv())"

    password_env = password_env_prefix(answers)

    "(cd #{escaped_root} && #{password_env}GIT_FOIL_TEST_REPO=#{escaped_repo} mix run -e '#{eval}' -- #{subcommand})"
  end

  defp escape_path(path) do
    "'" <> String.replace(path, "'", "'\"'\"'") <> "'"
  end

  defp test_password, do: "gitfoil-test"

  defp password_env_prefix(answers) do
    first_answer =
      answers
      |> String.split("\n", parts: 2)
      |> List.first()
      |> to_string()
      |> String.trim()
      |> String.downcase()

    if first_answer == "y" do
      "GIT_FOIL_PASSWORD=#{test_password()} "
    else
      ""
    end
  end

  defp run_cli(repo_path, subcommand, answers) do
    git_foil_cmd = get_git_foil_command()
    command = build_command(git_foil_cmd, subcommand, repo_path, answers)

    {output, exit_code} =
      System.cmd(
        "sh",
        ["-c", "echo '#{answers}' | #{command}"],
        cd: repo_path,
        stderr_to_stdout: true
      )

    {output, exit_code}
  end
end
