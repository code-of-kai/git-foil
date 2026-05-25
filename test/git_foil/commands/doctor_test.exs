defmodule GitFoil.Commands.DoctorTest do
  use ExUnit.Case, async: false

  alias GitFoil.Commands.Doctor

  setup do
    tmp = Path.join(System.tmp_dir!(), "git-foil-doctor-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    cwd = File.cwd!()
    File.cd!(tmp)

    on_exit(fn ->
      File.cd!(cwd)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "returns ok when no .gitattributes exists" do
    {:ok, msg} = Doctor.run([])
    assert msg =~ "No .gitattributes"
  end

  test "returns ok when .gitattributes has no GitFoil filter" do
    File.write!(".gitattributes", "*.txt text\n")
    {:ok, msg} = Doctor.run([])
    assert msg =~ "No GitFoil filter"
  end

  test "returns ok when .gitignore and **/.gitignore are excluded" do
    File.write!(".gitattributes", """
    ** filter=gitfoil
    .gitattributes -filter
    .gitignore -filter
    **/.gitignore -filter
    """)

    {:ok, msg} = Doctor.run([])
    assert msg =~ "correctly excludes"
  end

  test "returns error when .gitignore exclusion is missing" do
    File.write!(".gitattributes", """
    ** filter=gitfoil
    .gitattributes -filter
    """)

    {:error, msg} = Doctor.run([])
    assert msg =~ ".gitignore -filter"
    assert msg =~ "**/.gitignore -filter"
    assert msg =~ "silently disables"
  end

  test "returns error when only **/.gitignore is missing" do
    File.write!(".gitattributes", """
    ** filter=gitfoil
    .gitattributes -filter
    .gitignore -filter
    """)

    {:error, msg} = Doctor.run([])
    assert msg =~ "**/.gitignore -filter"
    refute msg =~ "\n    .gitignore -filter\n"
  end
end
