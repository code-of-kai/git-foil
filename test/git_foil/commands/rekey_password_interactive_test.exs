defmodule GitFoil.Commands.RekeyPasswordInteractiveTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GitFoil.Adapters.FileKeyStorage
  alias GitFoil.Commands.Rekey
  alias GitFoil.TestSupport.TempRepo

  setup do
    repo = TempRepo.create!()

    on_exit(fn ->
      File.rm_rf!(repo)
      System.delete_env("GIT_FOIL_TTY")
    end)

    {:ok, repo: repo}
  end

  test "rekey --password path reads from GIT_FOIL_TTY and creates encrypted key", %{repo: repo} do
    File.cd!(repo, fn ->
      # Initialize repo state with plaintext key present
      {:ok, keypair} = FileKeyStorage.generate_keypair()
      :ok = FileKeyStorage.store_keypair(keypair)

      # Fake TTY responses for password + confirm
      tty_path = Path.join(repo, "tty_rekey.txt")
      File.write!(tty_path, "AnotherPass9\nAnotherPass9\n")
      System.put_env("GIT_FOIL_TTY", tty_path)

      # Force new key and require password protection
      {output, result} = capture_result(fn -> Rekey.run(force: true, password: true) end)

      # Regardless of repo file state, password prompt was shown and key replaced
      assert output =~ "Password requirements:"
      assert output =~ "Rekeying repository"

      # Encrypted key should exist after rekey
      assert File.exists?(Path.expand(".git/git_foil/master.key.enc"))
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
