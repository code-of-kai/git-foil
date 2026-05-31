defmodule GitFoil.LoggingTest do
  use ExUnit.Case, async: false

  alias GitFoil.Logging

  setup do
    # This test mutates the global :default logger handler. Snapshot it and
    # restore on exit so we don't disturb other tests' log handling.
    saved =
      case :logger.get_handler_config(:default) do
        {:ok, cfg} -> cfg
        _ -> nil
      end

    on_exit(fn ->
      _ = :logger.remove_handler(:default)

      case saved do
        %{module: module} = cfg ->
          opts = Map.take(cfg, [:config, :formatter, :level, :filters, :filter_default])
          _ = :logger.add_handler(:default, module, opts)

        _ ->
          :ok
      end
    end)

    :ok
  end

  describe "redirect_to_stderr/0" do
    test "returns :ok and actually points the default handler at standard_error" do
      assert :ok = Logging.redirect_to_stderr()

      {:ok, config} = :logger.get_handler_config(:default)
      # The whole point: the default handler must write to standard_error so a
      # log line can never reach stdout (which is the encrypted blob / pkt-line
      # wire for clean/smudge/filter-process). NOTE: update_handler_config does
      # NOT achieve this for logger_std_h — only remove+re-add does, which is
      # what redirect_to_stderr/0 implements.
      assert get_in(config, [:config, :type]) == :standard_error
    end

    test "is idempotent — safe to call repeatedly (start/2 + main/1 both call it)" do
      assert :ok = Logging.redirect_to_stderr()
      assert :ok = Logging.redirect_to_stderr()

      {:ok, config} = :logger.get_handler_config(:default)
      assert get_in(config, [:config, :type]) == :standard_error
    end

    # End-to-end proof that a real NIF-load-failure log stays off stdout (the
    # blob) is an escript-level integration check: reproduced by building under
    # erts-29 and running the filter under erts-28, then asserting the clean blob
    # is pure 0x03 ciphertext with the pqclean/rustler errors routed to stderr.
    # (ExUnit's capture_io swaps the caller's group leader, not the :logger
    # process's, so it cannot faithfully assert handler-routed output here.)
  end
end
