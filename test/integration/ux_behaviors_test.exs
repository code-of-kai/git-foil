defmodule Integration.UXBehaviorsTest do
  use ExUnit.Case, async: false

  alias GitFoil.Test.GitTestHelper

  @moduledoc """
  Integration tests focused on UX behaviors that users experience.

  These tests validate user-facing behaviors like:
  - Progress bars appear and update correctly
  - File counts are accurate and displayed
  - Appropriate messages are shown
  - Batch operations work with many files

  These tests would have caught the bug where init showed "0 files found"
  when files existed, because check_attr_batch format was wrong.
  """

  describe "init: file counting and reporting" do
    test "reports correct count when files exist and match patterns" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 5 files and commit them
        Enum.each(1..5, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "content#{i}")
        end)
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Initial files"], cd: repo_path)

        # Run init with "everything" pattern
        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should report finding 5 files (not counting .gitattributes)
        assert output =~ "Found 5 files matching", "Should report 5 files found"
        assert output =~ "Encrypt existing files now?", "Should offer to encrypt"
        assert output =~ "Encrypting 5 files", "Should show encrypting 5 files"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "shows 'No existing files found' message when repo is empty" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Run init on empty repo
        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should explicitly say no files found
        assert output =~ "No existing files found", "Should report no files found"
        assert output =~ "Files will be encrypted as you add them", "Should explain what happens next"

        # Should NOT show encryption progress
        refute output =~ "Encrypting", "Should not show encryption when no files"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "correctly counts only files matching the selected pattern" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create mix of files
        GitTestHelper.create_file(repo_path, "secret.env", "API_KEY=secret")
        GitTestHelper.create_file(repo_path, "config.txt", "some config")
        GitTestHelper.create_file(repo_path, "data.env", "DB_URL=localhost")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Mixed files"], cd: repo_path)

        # Run init with env-only pattern (option 3)
        answers =
          ["y", "gitfoil-test", "gitfoil-test", "y", "3", "y"]
          |> Enum.join("\n")
          |> Kernel.<>("\n")

        {output, 0} = GitTestHelper.run_init_with_answers(repo_path, answers)

        # Should only count .env files (2), not .txt files (1)
        assert output =~ "Found 2 files matching", "Should only count .env files"
        assert output =~ "Encrypting 2 files", "Should only encrypt .env files"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles batch mode correctly with 100+ files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 150 files to trigger batch mode (check_attr_batch chunks at 100)
        Enum.each(1..150, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "data#{i}")
        end)
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Many files"], cd: repo_path)

        # Run init with password-protected flow to avoid interactive prompts
        answers = Enum.join(["y", "gitfoil-test", "gitfoil-test", "y", "1", "y"], "\n") <> "\n"
        {output, 0} = GitTestHelper.run_init_with_answers(repo_path, answers)

        # Should correctly count all 150 files (not 0 due to batch bug)
        assert output =~ "Found 150 files matching", "Should count all 150 files in batch mode"
        assert output =~ "Encrypting 150 files", "Should encrypt all 150 files"

        # Verify all were actually encrypted
        Enum.each(1..150, fn i ->
          first_byte = GitTestHelper.get_encrypted_first_byte(repo_path, "file#{i}.txt")
          assert first_byte == 0x03, "file#{i}.txt should be encrypted"
        end)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "init: progress bar behavior" do
    test "shows progress bar when encrypting multiple files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 10 files
        Enum.each(1..10, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "content#{i}")
        end)
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Files"], cd: repo_path)

        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should show progress indicators
        assert output =~ "10/10 files", "Should show final progress"

        # Should show progress bar characters
        assert String.contains?(output, "█") or String.contains?(output, "░"),
          "Should contain progress bar characters"

        # Should show percentage
        assert output =~ "100%", "Should show 100% at completion"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "progress bar updates throughout encryption process" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 5 files for easier percentage checking
        Enum.each(1..5, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "content#{i}")
        end)
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Files"], cd: repo_path)

        {output, 0} = GitTestHelper.run_init(repo_path)

        # With 5 files, we should see: 20%, 40%, 60%, 80%, 100%
        # But due to timing, we might not catch all intermediate values
        # At minimum, should see completion
        assert output =~ "5/5 files", "Should show 5/5 at end"

        # Should show file progress format
        assert output =~ ~r/\d+\/\d+ files/, "Should show X/Y files format"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "shows progress while discovering files to encrypt" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        Enum.each(1..3, fn i ->
          GitTestHelper.create_file(repo_path, "doc#{i}.txt", "data#{i}")
        end)

        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Docs"], cd: repo_path)

        {output, 0} = GitTestHelper.run_init(repo_path)

        assert output =~ "🔍  Searching for files to encrypt...",
               "Should announce the search progress"

        [before_encrypt | _] = String.split(output, "🔒  Encrypting")
        assert before_encrypt =~ "3/3 files",
               "Should show discovery progress before encryption begins"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "does not show progress bar when no files to encrypt" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should NOT show progress indicators when no files
        refute output =~ "0/0 files", "Should not show 0/0 progress"
        refute output =~ "█", "Should not show progress bar"
        assert output =~ "No existing files found", "Should show no files message instead"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "init: user feedback messages" do
    test "explains what happens when user declines to encrypt now" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create files
        GitTestHelper.create_file(repo_path, "file.txt", "data")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "File"], cd: repo_path)

        # Run init but decline to encrypt now
        answers =
          ["y", "gitfoil-test", "gitfoil-test", "y", "1", "n"]
          |> Enum.join("\n")
          |> Kernel.<>("\n")

        {output, 0} = GitTestHelper.run_init_with_answers(repo_path, answers)

        # Should explain what happens next
        assert output =~ "Found 1 file matching", "Should show file was found"
        assert output =~ "git-foil encrypt", "Should mention encrypt command"
        assert output =~ "git add", "Should mention files will encrypt with git add"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "shows appropriate message for different file counts" do
      # Test singular vs plural messaging
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Test with 1 file (singular)
        GitTestHelper.create_file(repo_path, "single.txt", "one")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "One file"], cd: repo_path)

        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should use singular form
        assert output =~ "Found 1 file matching", "Should say '1 file' (singular)"
        assert output =~ "Encrypting 1 file", "Should say '1 file' in encryption message"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "shows warning about encryption taking longer with many files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 150 files (>100 triggers "many files" warning)
        Enum.each(1..150, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "data")
        end)
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Many files"], cd: repo_path)

        {output, 0} = GitTestHelper.run_init(repo_path)

        # Should warn about longer encryption time
        assert output =~ "Encryption will take longer with many files",
          "Should warn about time with 150 files"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "unencrypt: progress bar behavior" do
    test "shows progress bar when converting many files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Initialize and encrypt files
        Enum.each(1..10, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "data#{i}")
        end)
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        # Verify encrypted
        assert GitTestHelper.get_encrypted_first_byte(repo_path, "file1.txt") == 0x03

        # Run unencrypt
        {output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Should show progress bar
        assert output =~ "Processing 10 files", "Should report processing 10 files"
        assert output =~ "10/10 files", "Should show completion"
        assert output =~ "100%", "Should show 100%"

        # Should contain progress bar visual
        assert String.contains?(output, "█") or String.contains?(output, "░"),
          "Should show progress bar characters"

        # Verify all decrypted
        assert GitTestHelper.is_plaintext_in_git?(repo_path, "file1.txt")
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "progress bar updates in place (not appending lines)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 5 files
        Enum.each(1..5, fn i ->
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "data")
        end)
        {_output, 0} = GitTestHelper.run_init(repo_path)
        {_output, 0} = GitTestHelper.commit_files(repo_path)

        {output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Count how many progress lines appear
        # Should be ~1 final line, not 5 separate lines
        progress_line_count =
          output
          |> String.split("\n")
          |> Enum.count(&String.contains?(&1, "/5 files"))

        # Should see the final progress line, but not 5 separate appended lines
        assert progress_line_count <= 2,
          "Progress should update in place, not append (found #{progress_line_count} lines)"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles files that don't need conversion gracefully" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create file but don't encrypt it (no init)
        GitTestHelper.create_file(repo_path, "plain.txt", "data")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Plain file"], cd: repo_path)

        # Initialize git-foil (but file is already plain in git)
        {_output, 0} = GitTestHelper.run_init(repo_path)

        # Try to unencrypt (should handle gracefully)
        {output, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Should not error on already-plain files
        assert output =~ "GitFoil encryption removed" or output =~ "complete",
          "Should complete successfully"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  describe "edge cases and error feedback" do
    test "shows clear error if check-attr fails" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create files
        GitTestHelper.create_file(repo_path, "file.txt", "data")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "File"], cd: repo_path)

        # Corrupt .git directory to cause check-attr to fail
        File.rm_rf!(Path.join([repo_path, ".git", "info"]))

        # Run init (might fail or succeed with warning)
        answers =
          ["y", "gitfoil-test", "gitfoil-test", "y", "1", "y"]
          |> Enum.join("\n")
          |> Kernel.<>("\n")

        {output, exit_code} = GitTestHelper.run_init_with_answers(repo_path, answers)

        # Should show some kind of message (either error or warning)
        assert output =~ "Warning" or output =~ "Error" or output =~ "Could not",
          "Should show error/warning when git operations fail"

        # Should not silently succeed with 0 files
        if exit_code == 0 do
          refute output =~ "No existing files found" or output =~ "Warning",
            "If succeeding, should explain what happened"
        end
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .gitattributes already existing" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create .gitattributes with other content
        GitTestHelper.create_file(repo_path, ".gitattributes", "*.txt text\n")
        {_output, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_output, 0} = System.cmd("git", ["commit", "-m", "Attributes"], cd: repo_path)

        {_output, 0} = GitTestHelper.run_init(repo_path)

        # Should preserve existing attributes
        attributes = File.read!(Path.join(repo_path, ".gitattributes"))
        assert attributes =~ "*.txt text", "Should preserve existing attributes"
        assert attributes =~ "filter=gitfoil", "Should add gitfoil filter"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end
end
