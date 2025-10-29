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
      System.delete_env("GIT_FOIL_PASSWORD")
    end)

    {:ok, repo: repo}
  end

  test "returns friendly error when GIT_FOIL_PASSWORD is too short", %{repo: repo} do
    File.cd!(repo, fn ->
      # Initialize with plaintext key present
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      System.put_env("GIT_FOIL_PASSWORD", "short")

      {_output, {:error, reason}} = capture_result(fn -> EncryptKey.run() end)

      assert reason =~ "at least 8"
      # Ensure nothing changed on disk
      assert File.exists?(KeyMigration.plaintext_path())
      refute File.exists?(KeyMigration.encrypted_path())
    end)
  end

  test "returns friendly error when GIT_FOIL_PASSWORD is empty", %{repo: repo} do
    File.cd!(repo, fn ->
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      System.put_env("GIT_FOIL_PASSWORD", "")

      {_output, {:error, reason}} = capture_result(fn -> EncryptKey.run() end)

      assert reason =~ "cannot be empty"
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

