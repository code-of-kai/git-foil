defmodule GitFoil.Infrastructure.FilenameEdgeCasesTest do
  @moduledoc """
  Tests for edge cases in filenames that git-foil must handle.

  Real users will have files with:
  - Spaces
  - Special characters
  - Unicode
  - Very long names
  - Hidden files (starting with .)
  - Multiple dots
  - Parentheses, quotes, etc.

  These tests ensure git-foil handles all valid filenames correctly.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduletag :integration
  @moduletag timeout: 120_000

  setup do
    # Create a unique temporary directory for each test
    test_dir = "/tmp/gitfoil_filename_test_#{:erlang.unique_integer([:positive])}"
    File.mkdir_p!(test_dir)

    # Change to test directory
    original_dir = File.cwd!()
    File.cd!(test_dir)

    # Initialize git
    System.cmd("git", ["init"])
    System.cmd("git", ["config", "user.email", "test@example.com"])
    System.cmd("git", ["config", "user.name", "Test User"])

    # Initialize git-foil
    capture_io(fn ->
      send_input(["Y", "1", "n"])
      GitFoil.Commands.Init.run()
    end)

    on_exit(fn ->
      File.cd!(original_dir)
      File.rm_rf!(test_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "filenames with spaces" do
    test "encrypts and decrypts file with spaces in name" do
      filename = "file with spaces.txt"
      content = "content with spaces"

      File.write!(filename, content)

      # Encrypt
      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      # Commit the file
      System.cmd("git", ["commit", "-m", "Add file with spaces"])

      # Verify encrypted in Git's storage
      {blob, 0} = System.cmd("git", ["cat-file", "blob", "HEAD:#{filename}"])
      refute blob == content <> "\n"

      # Verify working directory still has plaintext
      assert File.read!(filename) == content
    end

    test "handles multiple spaces" do
      filename = "file   with   multiple   spaces.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles leading and trailing spaces (if filesystem allows)" do
      # Note: Some filesystems don't allow leading/trailing spaces
      filename = " file .txt"

      case File.write(filename, "test") do
        :ok ->
          capture_io(fn ->
            send_input(["1"])
            GitFoil.Commands.Encrypt.run()
          end)

          System.cmd("git", ["commit", "-m", "Test"])
          assert File.read!(filename) == "test"

        {:error, _} ->
          # Filesystem doesn't support it, skip
          :ok
      end
    end
  end

  describe "filenames with special characters" do
    test "handles parentheses" do
      filename = "file(with)parens.txt"
      content = "test content"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles brackets" do
      filename = "file[with]brackets.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles ampersand" do
      filename = "file&with&ampersand.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles percent sign" do
      filename = "file%20with%20percent.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles plus sign" do
      filename = "file+with+plus.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles equals sign" do
      filename = "file=with=equals.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles at sign" do
      filename = "file@2x.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles hash/pound sign" do
      filename = "file#123.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles dollar sign" do
      filename = "file$price.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles exclamation mark" do
      filename = "file!important.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles tilde" do
      filename = "file~backup.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles comma" do
      filename = "file,with,comma.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end
  end

  describe "filenames with unicode" do
    test "handles cyrillic characters" do
      filename = "файл.txt"
      content = "содержимое"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles chinese characters" do
      filename = "文件.txt"
      content = "内容"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles japanese characters" do
      filename = "ファイル.txt"
      content = "コンテンツ"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles arabic characters" do
      filename = "ملف.txt"
      content = "محتوى"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles emoji in filename" do
      filename = "🔐secret.txt"
      content = "encrypted data"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles mixed unicode and ascii" do
      filename = "file_файл_文件_🔒.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end
  end

  describe "filenames with dots" do
    test "handles hidden files (starting with dot)" do
      filename = ".env"
      content = "SECRET=value"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles multiple dots" do
      filename = "file.backup.old.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles double dots" do
      filename = "file..txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles file with no extension" do
      filename = "Makefile"
      content = "all:\n\techo test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end
  end

  describe "long filenames" do
    test "handles very long filename (255 characters)" do
      # Most filesystems have a 255 character limit for filenames
      base_name = String.duplicate("a", 251)  # 251 + ".txt" = 255
      filename = base_name <> ".txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end

    test "handles long path (directory + filename)" do
      # Create nested directory structure
      dir_path = "a/b/c/d/e/f/g/h/i/j"
      File.mkdir_p!(dir_path)

      filename = "#{dir_path}/file.txt"
      content = "test"

      File.write!(filename, content)

      capture_io(fn ->
        send_input(["1"])
        GitFoil.Commands.Encrypt.run()
      end)

      System.cmd("git", ["commit", "-m", "Test"])
      assert File.read!(filename) == content
    end
  end

  describe "filenames with quotes" do
    @tag :skip  # These might not work on all filesystems
    test "handles single quotes" do
      filename = "file'with'quotes.txt"
      content = "test"

      case File.write(filename, content) do
        :ok ->
          capture_io(fn ->
            send_input(["1"])
            GitFoil.Commands.Encrypt.run()
          end)

          System.cmd("git", ["commit", "-m", "Test"])
          assert File.read!(filename) == content

        {:error, _} ->
          :ok  # Filesystem doesn't support it
      end
    end

    @tag :skip  # These might not work on all filesystems
    test "handles double quotes" do
      filename = "file\"with\"quotes.txt"
      content = "test"

      case File.write(filename, content) do
        :ok ->
          capture_io(fn ->
            send_input(["1"])
            GitFoil.Commands.Encrypt.run()
          end)

          System.cmd("git", ["commit", "-m", "Test"])
          assert File.read!(filename) == content

        {:error, _} ->
          :ok  # Filesystem doesn't support it
      end
    end
  end

  describe "case sensitivity" do
    test "treats File.txt and file.txt as different on case-sensitive filesystems" do
      File.write!("File.txt", "uppercase")
      File.write!("file.txt", "lowercase")

      # Check if filesystem is case-sensitive
      if File.read!("File.txt") != File.read!("file.txt") do
        capture_io(fn ->
          send_input(["1"])
          GitFoil.Commands.Encrypt.run()
        end)

        System.cmd("git", ["commit", "-m", "Test"])

        assert File.read!("File.txt") == "uppercase"
        assert File.read!("file.txt") == "lowercase"
      end
    end
  end

  # Helper functions

  defp send_input(inputs) when is_list(inputs) do
    Process.put(:test_inputs, inputs)
  end
end
