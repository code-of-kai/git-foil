defmodule GitFoil.Infrastructure.GitTest do
  use ExUnit.Case, async: false

  alias GitFoil.Infrastructure.Git

  @moduletag :tmp_dir

  setup do
    tmp_root =
      Path.join([
        System.tmp_dir!(),
        "git_foil_test",
        Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      ])

    File.rm_rf!(tmp_root)
    File.mkdir_p!(tmp_root)

    git!(tmp_root, ["init"])

    on_exit(fn -> File.rm_rf(tmp_root) end)

    {:ok, tmp: tmp_root}
  end

  test "list_files returns tracked filenames with unicode and spaces intact", %{tmp: tmp} do
    special = "2 Pitch Deck meeting with investor George – Monday at 16-59.pdf"
    nested_dir = Path.join(tmp, "2nd level")
    nested_file_name = "Deadwood Seasons 1-3 Script.pdf"
    nested = Path.join("2nd level", nested_file_name)

    File.mkdir_p!(nested_dir)
    File.write!(Path.join(tmp, special), "content")
    File.write!(Path.join(nested_dir, nested_file_name), "content")

    git!(tmp, ["add", "."])

    files =
      File.cd!(tmp, fn ->
        {:ok, files} = Git.list_files()
        files
      end)

    assert Enum.sort(files) ==
             Enum.sort([
               special,
               nested
             ])
  end

  test "list_all_files includes tracked and untracked files with special characters", %{tmp: tmp} do
    tracked = "tracked – file.pdf"
    untracked = "untracked data.txt"

    File.write!(Path.join(tmp, tracked), "tracked")
    git!(tmp, ["add", tracked])

    File.write!(Path.join(tmp, untracked), "untracked")

    files =
      File.cd!(tmp, fn ->
        {:ok, files} = Git.list_all_files()
        files
      end)

    assert tracked in files
    assert untracked in files
  end

  test "check_attr_batch normalizes git output paths", %{tmp: tmp} do
    File.write!(Path.join(tmp, ".gitattributes"), "*.pdf filter=gitfoil\n")
    git!(tmp, ["add", ".gitattributes"])

    special = "2 Pitch Deck meeting with investor George – Monday at 16-59.pdf"
    File.write!(Path.join(tmp, special), "content")
    git!(tmp, ["add", special])

    File.cd!(tmp, fn ->
      {:ok, results} = Git.check_attr_batch("filter", [special])
      assert [{^special, "gitfoil"}] = results
    end)
  end

  defp git!(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end
end
