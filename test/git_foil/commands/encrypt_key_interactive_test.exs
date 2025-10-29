defmodule GitFoil.Commands.EncryptKeyInteractiveTest do
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
      System.delete_env("GIT_FOIL_TTY")
    end)

    {:ok, repo: repo}
  end

  test "interactive path reads from GIT_FOIL_TTY and encrypts key", %{repo: repo} do
    File.cd!(repo, fn ->
      # Start with plaintext key present
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      # Prepare fake TTY file with password + confirm
      tty_path = Path.join(repo, "tty_input.txt")
      File.write!(tty_path, "StrongPass9\nStrongPass9\n")
      System.put_env("GIT_FOIL_TTY", tty_path)

      {output, {:ok, message}} = capture_result(fn -> EncryptKey.run() end)

      assert output =~ "Password requirements:"
      assert message =~ "Master key encrypted with password"
      assert File.exists?(KeyMigration.encrypted_path())
      refute File.exists?(KeyMigration.plaintext_path())
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

