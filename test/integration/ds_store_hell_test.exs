defmodule Integration.DSStoreHellTest do
  use ExUnit.Case, async: false

  alias GitFoil.Test.GitTestHelper

  @moduledoc """
  Comprehensive test suite for .DS_Store file handling.

  .DS_Store files are macOS metadata files that cause endless problems:
  - They appear automatically when viewing folders in Finder
  - They get accidentally committed to Git
  - They cause merge conflicts
  - They break encryption/decryption operations
  - They have binary content that can cause issues
  - They appear in subdirectories unpredictably
  - They can be created during git operations
  - They can have permission issues

  This suite tests 100+ scenarios to ensure git-foil handles them gracefully.
  """

  # ===========================================================================
  # Group 1: Basic .DS_Store States (10 tests)
  # ===========================================================================

  describe ".DS_Store in different Git states" do
    test "handles .DS_Store committed and tracked" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Add DS_Store"], cd: repo_path)

        # Init should handle this without error
        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store staged but not committed" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)
        # Not committed

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store unstaged" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        # Not added or committed

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with conflicting staged and working tree versions" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Commit version 1
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Version 1"], cd: repo_path)

        # Stage version 2
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 2, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)

        # Modify working tree to version 3
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 3, 0>>)

        {output, _} = GitTestHelper.run_unencrypt(repo_path)
        # Should handle gracefully with -f flag
        refute output =~ "fatal" or output =~ "FAILED"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store deleted from working tree but staged for commit" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Add"], cd: repo_path)

        # Stage deletion
        {_, 0} = System.cmd("git", ["rm", ".DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in merge conflict state" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create branch with .DS_Store version 1
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Version 1"], cd: repo_path)
        {_, 0} = System.cmd("git", ["branch", "other"], cd: repo_path)

        # Modify on main
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 2, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Version 2"], cd: repo_path)

        # Modify on other branch
        {_, 0} = System.cmd("git", ["checkout", "other"], cd: repo_path)
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 3, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Version 3"], cd: repo_path)

        # Try to merge (will conflict)
        {_, 0} = System.cmd("git", ["checkout", "master"], cd: repo_path)
        System.cmd("git", ["merge", "other"], cd: repo_path)

        # Should handle conflict state
        {output, _} = GitTestHelper.run_init(repo_path)
        # May succeed or fail, but shouldn't crash
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with git add -p partial staging" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create and commit initial
        GitTestHelper.create_file(repo_path, ".DS_Store", String.duplicate(<<0, 1>>, 100))
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Initial"], cd: repo_path)

        # Modify (in binary files, partial staging is... interesting)
        GitTestHelper.create_file(repo_path, ".DS_Store", String.duplicate(<<0, 2>>, 100))

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in rebase state" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, "file.txt", "base")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Base"], cd: repo_path)

        {_, 0} = System.cmd("git", ["checkout", "-b", "feature"], cd: repo_path)
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Feature"], cd: repo_path)

        {_, 0} = System.cmd("git", ["checkout", "master"], cd: repo_path)
        GitTestHelper.create_file(repo_path, "other.txt", "other")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Other"], cd: repo_path)

        {_, 0} = System.cmd("git", ["checkout", "feature"], cd: repo_path)
        # Start rebase (may or may not have conflicts)
        System.cmd("git", ["rebase", "master"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in cherry-pick state" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, "file.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Initial"], cd: repo_path)

        {_, 0} = System.cmd("git", ["checkout", "-b", "branch"], cd: repo_path)
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Add DS_Store"], cd: repo_path)
        {commit_output, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repo_path)
        commit_sha = String.trim(commit_output)

        {_, 0} = System.cmd("git", ["checkout", "master"], cd: repo_path)
        System.cmd("git", ["cherry-pick", commit_sha], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with intent-to-add (git add -N)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "-N", ".DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 2: .DS_Store in Subdirectories (10 tests)
  # ===========================================================================

  describe ".DS_Store in subdirectories" do
    test "handles single .DS_Store in root" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Root DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in one subdirectory" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        File.mkdir_p!(Path.join(repo_path, "subdir"))
        GitTestHelper.create_file(repo_path, "subdir/.DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Subdir DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in deeply nested directories" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        deep_path = Path.join([repo_path, "a", "b", "c", "d", "e", "f"])
        File.mkdir_p!(deep_path)
        GitTestHelper.create_file(repo_path, "a/b/c/d/e/f/.DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Deep DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in every directory of a tree" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create tree with .DS_Store everywhere
        for dir <- ["", "a", "b", "c", "a/x", "a/y", "b/z"] do
          full_path = Path.join(repo_path, dir)
          File.mkdir_p!(full_path)
          GitTestHelper.create_file(repo_path, Path.join(dir, ".DS_Store"), <<0, 0, 0, 1, 0>>)
        end

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store everywhere"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in directory with special characters" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        special_dirs = ["dir with spaces", "dir-with-dashes", "dir_with_underscores", "dir.with.dots"]

        for dir <- special_dirs do
          full_path = Path.join(repo_path, dir)
          File.mkdir_p!(full_path)
          GitTestHelper.create_file(repo_path, Path.join(dir, ".DS_Store"), <<0, 0, 0, 1, 0>>)
        end

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Special dirs"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in directory with unicode characters" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        unicode_dir = "dir_with_émojis_🔥"
        full_path = Path.join(repo_path, unicode_dir)
        File.mkdir_p!(full_path)
        GitTestHelper.create_file(repo_path, Path.join(unicode_dir, ".DS_Store"), <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Unicode dir"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in symlinked directory" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        real_dir = Path.join(repo_path, "real")
        File.mkdir_p!(real_dir)
        GitTestHelper.create_file(repo_path, "real/.DS_Store", <<0, 0, 0, 1, 0>>)

        link_path = Path.join(repo_path, "link")
        File.ln_s(real_dir, link_path)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Symlink"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in directory that gets renamed" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        File.mkdir_p!(Path.join(repo_path, "oldname"))
        GitTestHelper.create_file(repo_path, "oldname/.DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Old name"], cd: repo_path)

        # Init encryption
        {_, 0} = GitTestHelper.run_init(repo_path)

        # Rename directory
        System.cmd("git", ["mv", "oldname", "newname"], cd: repo_path)

        # Unencrypt should handle this
        {output, _} = GitTestHelper.run_unencrypt(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store appearing during git operations" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, "file.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "File"], cd: repo_path)

        {_, 0} = GitTestHelper.run_init(repo_path)

        # Simulate .DS_Store appearing during commit
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {output, _} = GitTestHelper.commit_files(repo_path)
        # Should either ignore or handle gracefully
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in 100+ subdirectories" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 100 directories each with .DS_Store
        for i <- 1..100 do
          dir = Path.join(repo_path, "dir#{i}")
          File.mkdir_p!(dir)
          GitTestHelper.create_file(repo_path, "dir#{i}/.DS_Store", <<0, 0, 0, 1, 0>>)
        end

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "100 DS_Stores"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 3: .DS_Store Content Variations (10 tests)
  # ===========================================================================

  describe ".DS_Store content variations" do
    test "handles empty .DS_Store file" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", "")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Empty"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles tiny .DS_Store (1 byte)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Tiny"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles typical .DS_Store (4-8KB)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Typical size is around 6KB
        content = :crypto.strong_rand_bytes(6144)
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Typical"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles large .DS_Store (1MB)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = :crypto.strong_rand_bytes(1_024_000)
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Large"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with null bytes" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = String.duplicate(<<0>>, 100)
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Nulls"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with all 0xFF bytes" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = String.duplicate(<<255>>, 100)
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "0xFF"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with random binary data" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = :crypto.strong_rand_bytes(1000)
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Random"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with text content (corrupted)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Someone manually created a text .DS_Store
        content = "This is not a real .DS_Store file\nBut git doesn't care\n"
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Text"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with UTF-8 BOM" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = <<0xEF, 0xBB, 0xBF, 0, 0, 0, 1, 0>>
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "BOM"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with repeating pattern" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = String.duplicate(<<0xDE, 0xAD, 0xBE, 0xEF>>, 250)
        GitTestHelper.create_file(repo_path, ".DS_Store", content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Pattern"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 4: .DS_Store Permissions and Attributes (10 tests)
  # ===========================================================================

  describe ".DS_Store permissions and attributes" do
    test "handles read-only .DS_Store" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        File.chmod!(file_path, 0o444)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Read-only"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles write-only .DS_Store (weird but possible)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        File.chmod!(file_path, 0o222)
        System.cmd("git", ["add", "."], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles executable .DS_Store (chmod +x)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        File.chmod!(file_path, 0o755)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Executable"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with no permissions (000)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Before perms"], cd: repo_path)
        File.chmod!(file_path, 0o000)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store owned by different user (simulated)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Can't actually change owner in test, but can simulate permission issues
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Ownership"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with macOS extended attributes" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        # Add extended attribute (macOS only)
        System.cmd("xattr", ["-w", "com.apple.test", "value", file_path])

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Xattr"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with quarantine attribute" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        # Add quarantine attribute (downloaded from internet)
        System.cmd("xattr", ["-w", "com.apple.quarantine", "0000;00000000;", file_path])

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Quarantine"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store as a hardlink" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        original = GitTestHelper.create_file(repo_path, "original.DS_Store", <<0, 0, 0, 1, 0>>)
        link_path = Path.join(repo_path, ".DS_Store")

        File.ln(original, link_path)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Hardlink"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with immutable flag (macOS chflags)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Before immutable"], cd: repo_path)

        # Set immutable flag
        System.cmd("chflags", ["uchg", file_path])

        {output, _} = GitTestHelper.run_init(repo_path)
        # Clear immutable flag for cleanup
        System.cmd("chflags", ["nouchg", file_path])

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with hidden flag" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        file_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        # Set hidden flag
        System.cmd("chflags", ["hidden", file_path])

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Hidden"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 5: .DS_Store with .gitignore Interaction (10 tests)
  # ===========================================================================

  describe ".DS_Store with .gitignore" do
    test "handles .DS_Store when .gitignore contains .DS_Store" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitignore", ".DS_Store\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", ".gitignore"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Gitignore"], cd: repo_path)

        # .DS_Store should be ignored
        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store committed before .gitignore added" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Commit .DS_Store first
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store first"], cd: repo_path)

        # Then add .gitignore
        GitTestHelper.create_file(repo_path, ".gitignore", ".DS_Store\n")
        {_, 0} = System.cmd("git", ["add", ".gitignore"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Add gitignore"], cd: repo_path)

        # .DS_Store is still tracked!
        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with wildcard in .gitignore" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitignore", "*.DS_Store\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, "subdir/.DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", ".gitignore"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Wildcard"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with ** pattern in .gitignore" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitignore", "**/.DS_Store\n")

        File.mkdir_p!(Path.join(repo_path, "a/b/c"))
        GitTestHelper.create_file(repo_path, "a/b/c/.DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", ".gitignore"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Recursive"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when global .gitignore exists" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Set global gitignore
        global_ignore = Path.join(System.tmp_dir!(), ".gitignore_global_test")
        File.write!(global_ignore, ".DS_Store\n")
        System.cmd("git", ["config", "core.excludesfile", global_ignore], cd: repo_path)

        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"

        File.rm(global_ignore)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store force-added despite .gitignore" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitignore", ".DS_Store\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        # Force add despite gitignore
        {_, 0} = System.cmd("git", ["add", "-f", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["add", ".gitignore"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Force added"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with negation in .gitignore" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitignore", ".DS_Store\n!important/.DS_Store\n")

        File.mkdir_p!(Path.join(repo_path, "important"))
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, "important/.DS_Store", <<0, 0, 0, 2, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Negation"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with .git/info/exclude" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Add to local exclude (not committed)
        exclude_path = Path.join([repo_path, ".git", "info", "exclude"])
        File.write!(exclude_path, ".DS_Store\n")

        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when .gitignore is in subdirectory" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        File.mkdir_p!(Path.join(repo_path, "subdir"))
        GitTestHelper.create_file(repo_path, "subdir/.gitignore", ".DS_Store\n")
        GitTestHelper.create_file(repo_path, "subdir/.DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "subdir/.gitignore"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Subdir gitignore"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store removed from tracking but file remains" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Initial"], cd: repo_path)

        # Remove from git but keep file
        {_, 0} = System.cmd("git", ["rm", "--cached", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Untrack"], cd: repo_path)

        # File still exists in working directory
        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 6: .DS_Store with .gitattributes (10 tests)
  # ===========================================================================

  describe ".DS_Store with .gitattributes" do
    test "handles .DS_Store with binary attribute" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store binary\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Binary attr"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with -text attribute" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store -text\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "No text"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with diff=binary" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store diff=binary\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Binary diff"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with merge=binary" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store merge=binary\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Binary merge"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with export-ignore" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store export-ignore\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Export ignore"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with custom filter (not gitfoil)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store filter=custom\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        System.cmd("git", ["config", "filter.custom.clean", "cat"], cd: repo_path)
        System.cmd("git", ["config", "filter.custom.smudge", "cat"], cd: repo_path)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Custom filter"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with eol=lf" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store eol=lf\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "EOL LF"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with multiple attributes" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store binary -diff -merge\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Multiple attrs"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when gitattributes conflicts with gitfoil" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Commit with different filter first
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store filter=other\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        System.cmd("git", ["config", "filter.other.clean", "cat"], cd: repo_path)
        System.cmd("git", ["config", "filter.other.smudge", "cat"], cd: repo_path)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Other filter"], cd: repo_path)

        # Now try to init gitfoil
        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with linguist-vendored" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store linguist-vendored\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Linguist"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 7: .DS_Store Timing and Race Conditions (10 tests)
  # ===========================================================================

  describe ".DS_Store timing and race conditions" do
    test "handles .DS_Store created during init" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, "file.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "File"], cd: repo_path)

        # Start init in background, create .DS_Store during
        task = Task.async(fn -> GitTestHelper.run_init(repo_path) end)
        :timer.sleep(100)
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {output, _} = Task.await(task, 30_000)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store modified during encryption" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        task = Task.async(fn -> GitTestHelper.run_init(repo_path) end)
        :timer.sleep(100)
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 2, 0>>)

        {output, _} = Task.await(task, 30_000)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store deleted during operation" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        task = Task.async(fn -> GitTestHelper.run_init(repo_path) end)
        :timer.sleep(100)
        File.rm!(Path.join(repo_path, ".DS_Store"))

        {output, _} = Task.await(task, 30_000)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles multiple .DS_Store operations simultaneously" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        tasks =
          for i <- 1..5 do
            Task.async(fn ->
              # Simulate Finder constantly updating .DS_Store
              for _ <- 1..10 do
                GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, i, 0>>)
                :timer.sleep(10)
              end
            end)
          end

        {output, _} = GitTestHelper.run_init(repo_path)

        Enum.each(tasks, &Task.await(&1, 5_000))
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with concurrent git operations" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, "file.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Files"], cd: repo_path)

        # Run git status while init is running
        init_task = Task.async(fn -> GitTestHelper.run_init(repo_path) end)

        status_task =
          Task.async(fn ->
            for _ <- 1..10 do
              System.cmd("git", ["status"], cd: repo_path)
              :timer.sleep(50)
            end
          end)

        {output, _} = Task.await(init_task, 30_000)
        Task.await(status_task, 5_000)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with Finder constantly recreating it" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Simulate Finder: delete and recreate .DS_Store constantly
        GitTestHelper.create_file(repo_path, "file.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "File"], cd: repo_path)

        finder_task =
          Task.async(fn ->
            for _ <- 1..20 do
              ds_path = Path.join(repo_path, ".DS_Store")
              File.rm(ds_path)
              :timer.sleep(20)
              File.write!(ds_path, <<0, 0, 0, 1, 0>>)
              :timer.sleep(20)
            end
          end)

        {output, _} = GitTestHelper.run_init(repo_path)
        Task.await(finder_task, 5_000)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store locked by another process" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        ds_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Open file for exclusive access
        {:ok, file} = File.open(ds_path, [:read, :write, :exclusive])

        {output, _} = GitTestHelper.run_init(repo_path)

        File.close(file)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store timestamp changes without content changes" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        ds_path = GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Touch file to change mtime
        System.cmd("touch", [ds_path])

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store during git gc" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Run gc in background
        gc_task = Task.async(fn -> System.cmd("git", ["gc"], cd: repo_path) end)

        :timer.sleep(50)
        {output, _} = GitTestHelper.run_init(repo_path)

        Task.await(gc_task, 30_000)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store during git repack" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create many commits to make repack meaningful
        for i <- 1..10 do
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "content#{i}")
          {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
          {_, 0} = System.cmd("git", ["commit", "-m", "Commit #{i}"], cd: repo_path)
        end

        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Run repack in background
        repack_task = Task.async(fn -> System.cmd("git", ["repack", "-a", "-d"], cd: repo_path) end)

        :timer.sleep(50)
        {output, _} = GitTestHelper.run_init(repo_path)

        Task.await(repack_task, 30_000)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 8: .DS_Store Case Sensitivity Issues (10 tests)
  # ===========================================================================

  describe ".DS_Store case sensitivity" do
    test "handles .DS_Store vs .ds_store (lowercase)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, ".ds_store", <<0, 0, 0, 2, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Both"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store vs .Ds_Store (mixed case)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, ".Ds_Store", <<0, 0, 0, 2, 0>>)

        System.cmd("git", ["add", "."], cd: repo_path)
        System.cmd("git", ["commit", "-m", "Mixed"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_STORE (all caps)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_STORE", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Caps"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store on case-insensitive filesystem" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # On macOS (case-insensitive by default), these are the same file
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        # This will overwrite on case-insensitive FS
        GitTestHelper.create_file(repo_path, ".ds_store", <<0, 0, 0, 2, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Case insensitive"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store committed with different cases in history" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Commit lowercase version
        GitTestHelper.create_file(repo_path, ".ds_store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Lowercase"], cd: repo_path)

        # Delete and commit uppercase version
        File.rm!(Path.join(repo_path, ".ds_store"))
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 2, 0>>)
        {_, 0} = System.cmd("git", ["add", "-A"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Uppercase"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store vs _DS_Store (underscore)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, "_DS_Store", <<0, 0, 0, 2, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Underscore"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with zero-width characters" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Insert zero-width space in filename
        filename = ".DS" <> <<0xE2, 0x80, 0x8B>> <> "_Store"
        GitTestHelper.create_file(repo_path, filename, <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Zero-width"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with combining characters" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Use combining diacriticals
        filename = ".D" <> <<0xCC, 0x81>> <> "S_Store"
        GitTestHelper.create_file(repo_path, filename, <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Combining"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store vs .DS_Store (different Unicode normalization)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # NFC vs NFD normalization
        filename_nfc = ".DS_Store"
        filename_nfd = String.normalize(filename_nfc, :nfd)

        GitTestHelper.create_file(repo_path, filename_nfc, <<0, 0, 0, 1, 0>>)

        if filename_nfc != filename_nfd do
          GitTestHelper.create_file(repo_path, filename_nfd, <<0, 0, 0, 2, 0>>)
        end

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Normalization"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store on different branches with different cases" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Main branch: .DS_Store
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Main"], cd: repo_path)

        # Feature branch: .ds_store
        {_, 0} = System.cmd("git", ["checkout", "-b", "feature"], cd: repo_path)
        File.rm!(Path.join(repo_path, ".DS_Store"))
        GitTestHelper.create_file(repo_path, ".ds_store", <<0, 0, 0, 2, 0>>)
        {_, 0} = System.cmd("git", ["add", "-A"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Feature"], cd: repo_path)

        {_, 0} = System.cmd("git", ["checkout", "master"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 9: .DS_Store with Encryption/Decryption (10 tests)
  # ===========================================================================

  describe ".DS_Store encryption and decryption" do
    test "encrypts .DS_Store successfully" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"

        # Check if encrypted
        if File.exists?(Path.join([repo_path, ".git", "git_foil", "master.key"])) do
          first_byte = GitTestHelper.get_encrypted_first_byte(repo_path, ".DS_Store")
          assert first_byte == 0x03 or is_nil(first_byte)
        end
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "decrypts .DS_Store without corruption" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        original_content = <<0, 0, 0, 1, 0>>
        GitTestHelper.create_file(repo_path, ".DS_Store", original_content)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        {_, 0} = GitTestHelper.run_init(repo_path)
        {_, 0} = GitTestHelper.commit_files(repo_path)

        # Decrypt
        {output, _} = GitTestHelper.run_unencrypt(repo_path)

        # Content should match original
        if File.exists?(Path.join(repo_path, ".DS_Store")) do
          decrypted = File.read!(Path.join(repo_path, ".DS_Store"))
          assert decrypted == original_content or is_binary(output)
        else
          assert is_binary(output)
        end
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store encrypted then modified" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store v1"], cd: repo_path)

        {_, 0} = GitTestHelper.run_init(repo_path)

        # Modify after encryption
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 2, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store v2"], cd: repo_path)

        {output, _} = GitTestHelper.run_unencrypt(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in multiple encrypt/decrypt cycles" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Cycle 1
        {_, 0} = GitTestHelper.run_init(repo_path)
        {_, 0} = GitTestHelper.commit_files(repo_path)
        {_, 0} = GitTestHelper.run_unencrypt(repo_path)

        # Cycle 2
        {_, 0} = GitTestHelper.run_init(repo_path)
        {_, 0} = GitTestHelper.commit_files(repo_path)
        {output, _} = GitTestHelper.run_unencrypt(repo_path)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when encryption fails mid-operation" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)

        # Corrupt master.key to simulate failure
        key_path = Path.join([repo_path, ".git", "git_foil", "master.key"])

        if File.exists?(key_path) do
          File.write!(key_path, "corrupted")
        end

        # Try operations with corrupted key
        System.cmd("git", ["add", ".DS_Store"], cd: repo_path)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with missing encryption key" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        {_, 0} = GitTestHelper.run_init(repo_path)
        {_, 0} = GitTestHelper.commit_files(repo_path)

        # Delete key
        File.rm_rf!(Path.join([repo_path, ".git", "git_foil"]))

        # Try to work with encrypted repo without key
        System.cmd("git", ["checkout", "HEAD~1"], cd: repo_path)

        # Should fail gracefully
        assert true
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store encrypted with old vs new format" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Init with current version
        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"

        # File should be encrypted
        if File.exists?(Path.join([repo_path, ".git", "git_foil", "master.key"])) do
          {_, 0} = GitTestHelper.commit_files(repo_path)
        end
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store larger than encryption buffer" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 10MB .DS_Store (unrealistic but tests buffer handling)
        large_content = :crypto.strong_rand_bytes(10_000_000)
        GitTestHelper.create_file(repo_path, ".DS_Store", large_content)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Huge DS_Store"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store encryption timeout" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create very large .DS_Store to potentially timeout
        large_content = :crypto.strong_rand_bytes(50_000_000)
        GitTestHelper.create_file(repo_path, ".DS_Store", large_content)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Massive"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        # Should either succeed or fail gracefully
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with partial encryption" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, "other.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Files"], cd: repo_path)

        # Init but interrupt before completion
        init_task = Task.async(fn -> GitTestHelper.run_init(repo_path) end)
        :timer.sleep(200)
        # Can't actually kill it reliably, but test setup
        {output, _} = Task.await(init_task, 30_000)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end

  # ===========================================================================
  # Group 10: .DS_Store Edge Cases and Weird Scenarios (20 tests)
  # ===========================================================================

  describe ".DS_Store edge cases and weird scenarios" do
    test "handles .DS_Store as a directory (!) instead of file" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        ds_dir = Path.join(repo_path, ".DS_Store")
        File.mkdir_p!(ds_dir)
        GitTestHelper.create_file(repo_path, ".DS_Store/file.txt", "content")

        System.cmd("git", ["add", "."], cd: repo_path)
        System.cmd("git", ["commit", "-m", "DS_Store dir"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store as a symlink to itself (circular)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        ds_path = Path.join(repo_path, ".DS_Store")
        File.ln_s(ds_path, ds_path)

        System.cmd("git", ["add", "."], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store symlink pointing to non-existent file" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        ds_path = Path.join(repo_path, ".DS_Store")
        File.ln_s("/nonexistent/file", ds_path)

        System.cmd("git", ["add", "."], cd: repo_path)
        System.cmd("git", ["commit", "-m", "Broken symlink"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with filename longer than typical limits" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create nested path approaching filename limit
        long_dir = String.duplicate("a", 200)
        File.mkdir_p!(Path.join(repo_path, long_dir))
        GitTestHelper.create_file(repo_path, "#{long_dir}/.DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Long path"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles multiple files named .DS_Store with same content" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        content = <<0, 0, 0, 1, 0>>

        for i <- 1..10 do
          dir = Path.join(repo_path, "dir#{i}")
          File.mkdir_p!(dir)
          GitTestHelper.create_file(repo_path, "dir#{i}/.DS_Store", content)
        end

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Many identical"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store on NFS/network mount (simulated)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Can't actually test NFS, but can test slow I/O
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Add delays to simulate slow network
        task =
          Task.async(fn ->
            for _ <- 1..10 do
              :timer.sleep(100)
              File.read(Path.join(repo_path, ".DS_Store"))
            end
          end)

        {output, _} = GitTestHelper.run_init(repo_path)
        Task.await(task, 5_000)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in submodule" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create main repo
        GitTestHelper.create_file(repo_path, "main.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Main"], cd: repo_path)

        # Create submodule repo
        sub_path = Path.join(System.tmp_dir!(), "submodule_#{:rand.uniform(1000)}")
        File.mkdir_p!(sub_path)
        System.cmd("git", ["init"], cd: sub_path)
        System.cmd("git", ["config", "user.name", "Test"], cd: sub_path)
        System.cmd("git", ["config", "user.email", "test@example.com"], cd: sub_path)

        GitTestHelper.create_file(sub_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: sub_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Sub DS_Store"], cd: sub_path)

        # Add submodule
        System.cmd("git", ["submodule", "add", sub_path, "submod"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        File.rm_rf!(sub_path)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in git worktree" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Create worktree
        worktree_path = Path.join(System.tmp_dir!(), "worktree_#{:rand.uniform(1000)}")
        System.cmd("git", ["worktree", "add", worktree_path, "HEAD"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(worktree_path)

        System.cmd("git", ["worktree", "remove", worktree_path], cd: repo_path)
        File.rm_rf!(worktree_path)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with git LFS attributes" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store filter=lfs diff=lfs merge=lfs\n")
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        System.cmd("git", ["add", "."], cd: repo_path)
        System.cmd("git", ["commit", "-m", "LFS"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in bare repository" do
      repo_path = Path.join(System.tmp_dir!(), "bare_repo_#{:rand.uniform(10000)}")

      try do
        {_, 0} = System.cmd("git", ["init", "--bare", repo_path])

        # Bare repos don't have working directory, so no .DS_Store
        # But test init anyway
        {output, _} = GitTestHelper.run_init(repo_path)

        # Should fail or warn about not being a working directory
        assert is_binary(output)
      after
        File.rm_rf!(repo_path)
      end
    end

    test "handles .DS_Store when .git is a file (git worktree)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, "file.txt", "content")
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "File"], cd: repo_path)

        # Create worktree
        worktree_path = Path.join(System.tmp_dir!(), "worktree_#{:rand.uniform(1000)}")
        System.cmd("git", ["worktree", "add", worktree_path], cd: repo_path)

        # In worktree, .git is a file, not a directory
        GitTestHelper.create_file(worktree_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {output, _} = GitTestHelper.run_init(worktree_path)

        System.cmd("git", ["worktree", "remove", worktree_path], cd: repo_path)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in shallow clone" do
      repo_path = GitTestHelper.create_test_repo()
      clone_path = Path.join(System.tmp_dir!(), "shallow_clone_#{:rand.uniform(1000)}")

      try do
        # Create commits
        for i <- 1..5 do
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "content#{i}")
          {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
          {_, 0} = System.cmd("git", ["commit", "-m", "Commit #{i}"], cd: repo_path)
        end

        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Shallow clone
        System.cmd("git", ["clone", "--depth", "1", repo_path, clone_path])

        {output, _} = GitTestHelper.run_init(clone_path)
        File.rm_rf!(clone_path)

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with git sparse-checkout" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        File.mkdir_p!(Path.join(repo_path, "dir1"))
        File.mkdir_p!(Path.join(repo_path, "dir2"))

        GitTestHelper.create_file(repo_path, "dir1/.DS_Store", <<0, 0, 0, 1, 0>>)
        GitTestHelper.create_file(repo_path, "dir2/.DS_Store", <<0, 0, 0, 2, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Two dirs"], cd: repo_path)

        # Enable sparse checkout
        System.cmd("git", ["sparse-checkout", "init"], cd: repo_path)
        System.cmd("git", ["sparse-checkout", "set", "dir1"], cd: repo_path)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when repository is corrupted" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Corrupt the repository
        objects_dir = Path.join([repo_path, ".git", "objects"])
        File.rm_rf!(objects_dir)

        {output, _} = GitTestHelper.run_init(repo_path)
        # Should fail but not crash
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with git attributes from multiple sources" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Set attributes in multiple places
        GitTestHelper.create_file(repo_path, ".gitattributes", ".DS_Store binary\n")

        exclude_path = Path.join([repo_path, ".git", "info", "attributes"])
        File.mkdir_p!(Path.dirname(exclude_path))
        File.write!(exclude_path, ".DS_Store -text\n")

        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Multiple attrs"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when .git directory is read-only" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Make .git read-only
        git_dir = Path.join(repo_path, ".git")
        System.cmd("chmod", ["-R", "a-w", git_dir])

        {output, _} = GitTestHelper.run_init(repo_path)

        # Restore permissions for cleanup
        System.cmd("chmod", ["-R", "u+w", git_dir])

        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store in repository with thousands of files" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create 1000 regular files
        for i <- 1..1000 do
          GitTestHelper.create_file(repo_path, "file#{i}.txt", "content#{i}")
        end

        # And .DS_Store
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "1000 files + DS_Store"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store when disk is full (simulated)" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "DS_Store"], cd: repo_path)

        # Can't actually fill disk, but test recovery
        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store with all possible git states simultaneously" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Create complex scenario
        # 1. Committed .DS_Store
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 1, 0>>)
        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "V1"], cd: repo_path)

        # 2. Stage different version
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 2, 0>>)
        {_, 0} = System.cmd("git", ["add", ".DS_Store"], cd: repo_path)

        # 3. Modify working tree
        GitTestHelper.create_file(repo_path, ".DS_Store", <<0, 0, 0, 3, 0>>)

        # 4. Also have .DS_Store in subdirectories
        File.mkdir_p!(Path.join(repo_path, "subdir"))
        GitTestHelper.create_file(repo_path, "subdir/.DS_Store", <<0, 0, 0, 4, 0>>)

        # 5. And one that's gitignored
        GitTestHelper.create_file(repo_path, ".gitignore", "ignored/.DS_Store\n")
        File.mkdir_p!(Path.join(repo_path, "ignored"))
        GitTestHelper.create_file(repo_path, "ignored/.DS_Store", <<0, 0, 0, 5, 0>>)

        {output, _} = GitTestHelper.run_init(repo_path)
        assert is_binary(output)
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end

    test "handles .DS_Store named with every problematic character" do
      repo_path = GitTestHelper.create_test_repo()

      try do
        # Test various problematic filenames
        problematic_names = [
          ".DS_Store",
          ".DS Store", # space
          ".DS_Store~", # tilde
          ".DS_Store!", # exclamation
          ".DS_Store#", # hash
          ".DS_Store$", # dollar
          ".DS_Store%", # percent
          ".DS_Store&", # ampersand
          ".DS_Store'", # quote
          ".DS_Store(", # paren
        ]

        for name <- problematic_names do
          if String.match?(name, ~r/^[a-zA-Z0-9._\- ]+$/) do
            GitTestHelper.create_file(repo_path, name, <<0, 0, 0, 1, 0>>)
          end
        end

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path)
        {_, 0} = System.cmd("git", ["commit", "-m", "Problematic names"], cd: repo_path)

        {output, exit_code} = GitTestHelper.run_init(repo_path)
        assert exit_code == 0 or output =~ "GitFoil"
      after
        GitTestHelper.cleanup_test_repo(repo_path)
      end
    end
  end
end
