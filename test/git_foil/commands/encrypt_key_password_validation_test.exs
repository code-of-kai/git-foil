defmodule GitFoil.Commands.EncryptKeyPasswordValidationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GitFoil.Adapters.FileKeyStorage
  alias GitFoil.Commands.EncryptKey
  alias GitFoil.Core.KeyMigration
  alias GitFoil.TestSupport.TempRepo

  setup do
    repo = TempRepo.create!()

    on_exit(fn ->
      File.rm_rf!(repo)
    end)

    {:ok, repo: repo}
  end

  test "returns friendly error when password from file is too short", %{repo: repo} do
    File.cd!(repo, fn ->
      # Initialize with plaintext key present
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      password_file = Path.join(repo, "short_password.txt")
      File.write!(password_file, "short\nshort\n")

      {_output, {:error, {exit_code, reason}}} =
        capture_result(fn -> EncryptKey.run(password_source: {:file, password_file}) end)

      assert exit_code == 2
      assert reason =~ "at least 8"
      # Ensure nothing changed on disk
      assert File.exists?(KeyMigration.plaintext_path())
      refute File.exists?(KeyMigration.encrypted_path())
    end)
  end

  test "returns friendly error when password from file is empty", %{repo: repo} do
    File.cd!(repo, fn ->
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      password_file = Path.join(repo, "empty_password.txt")
      File.write!(password_file, "\n\n")

      {_output, {:error, {exit_code, reason}}} =
        capture_result(fn -> EncryptKey.run(password_source: {:file, password_file}) end)

      assert exit_code == 2
      assert reason =~ "cannot be empty"
      assert File.exists?(KeyMigration.plaintext_path())
      refute File.exists?(KeyMigration.encrypted_path())
    end)
  end

  test "rejects passwords with leading or trailing whitespace", %{repo: repo} do
    File.cd!(repo, fn ->
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      password_file = Path.join(repo, "spaced_password.txt")
      File.write!(password_file, " pass\n pass\n")

      {_output, {:error, {exit_code, reason}}} =
        capture_result(fn -> EncryptKey.run(password_source: {:file, password_file}) end)

      assert exit_code == 2
      assert reason =~ "leading/trailing spaces"
      assert File.exists?(KeyMigration.plaintext_path())
      refute File.exists?(KeyMigration.encrypted_path())
    end)
  end

  defp capture_result(fun) do
    parent = self()

    output =
      capture_io(fn ->
        send(parent, {:result, fun.()})
      end)

    result =
      receive do
        {:result, value} -> value
      after
        0 -> flunk("Expected command result but none was captured")
      end

    {output, result}
  end
end
