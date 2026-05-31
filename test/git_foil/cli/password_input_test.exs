defmodule GitFoil.CLI.PasswordInputTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias GitFoil.CLI.PasswordInput

  describe "existing_password/2 non-interactive guard (filter-process wire safety)" do
    test "refuses :tty source and writes NOTHING to stdout" do
      # The long-running filter process uses stdin/stdout as the pkt-line wire.
      # A :tty prompt would IO.write the prompt to stdout, corrupting the
      # protocol. Under :non_interactive it must hard-fail off-wire instead.
      result = nil

      stdout =
        capture_io(fn ->
          send(self(), {:result, PasswordInput.existing_password("GitFoil password: ", non_interactive: true, password_source: :tty)})
        end)

      assert_received {:result, {:error, {1, message}}}
      assert message =~ "filter process cannot prompt"
      # The critical property: not a single byte reached stdout.
      assert stdout == ""
      _ = result
    end

    test "refuses :stdin source (stdin is the wire too) without touching stdout" do
      stdout =
        capture_io(fn ->
          send(self(), {:result, PasswordInput.existing_password("GitFoil password: ", non_interactive: true, password_source: :stdin)})
        end)

      assert_received {:result, {:error, {1, _message}}}
      assert stdout == ""
    end

    test "default source is :tty, so non_interactive with no source given also fails closed" do
      # filter-process passes no :password_source, so the default (:tty) must
      # be caught by the guard.
      assert {:error, {1, _}} =
               PasswordInput.existing_password("GitFoil password: ", non_interactive: true)
    end

    test "off-wire sources are NOT blocked by the guard (they reach the prompt layer)" do
      # A {:fd, _} source does not read/write the process stdio, so the guard
      # must let it through. We can't supply a real fd here, but we assert the
      # guard does not short-circuit it with the non-interactive error: any
      # error returned must NOT be the {1, "...filter process cannot prompt..."}
      # guard error.
      result =
        capture_io(fn ->
          send(self(), {:result, PasswordInput.existing_password("p: ", non_interactive: true, password_source: {:fd, 9})})
        end)

      assert_received {:result, outcome}

      case outcome do
        {:error, {1, message}} ->
          refute message =~ "filter process cannot prompt"

        _other ->
          :ok
      end

      _ = result
    end
  end
end
