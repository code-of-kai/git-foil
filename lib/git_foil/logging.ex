defmodule GitFoil.Logging do
  @moduledoc """
  Stdout is sacred in git-foil.

  For the `clean`/`smudge` filters, stdout **is** the encrypted blob Git stores;
  for `filter-process`, stdout **is** the pkt-line wire. A single stray log line
  written to stdout is therefore baked verbatim into a Git object — silent data
  corruption (observed in the wild: a flapping `pqclean_nif` load wrote
  `[error] Failed to stage embedded pqclean NIF` into committed blobs).

  This module routes ALL logging to standard_error so that no diagnostic — from
  our code, a dependency, or the BEAM's own `@on_load` failure reporter — can
  ever reach stdout. It is invoked at the earliest possible point
  (`GitFoil.Application.start/2`, before any NIF load is attempted) and again
  defensively at the CLI entry point.
  """

  @doc """
  Point the Erlang/Elixir logger's default handler at standard_error.

  Implementation note: `logger_std_h` does NOT honor a `:type` (output device)
  change via `update_handler_config/3` on an already-installed handler — its
  `changing_config` callback silently ignores it (verified empirically; the log
  kept landing on stdout). The handler must be **removed and re-added** with the
  new device. We preserve the existing formatter and level so log formatting is
  unchanged — only the destination moves from stdout to stderr.

  Best-effort and idempotent: safe to call repeatedly and tolerant of any
  handler shape (it never raises, so it cannot itself break startup).
  """
  @spec redirect_to_stderr() :: :ok
  def redirect_to_stderr do
    old =
      case :logger.get_handler_config(:default) do
        {:ok, cfg} -> cfg
        _ -> %{}
      end

    add_opts =
      %{config: %{type: :standard_error}}
      |> maybe_put(:formatter, Map.get(old, :formatter))
      |> maybe_put(:level, Map.get(old, :level))

    _ = :logger.remove_handler(:default)
    _ = :logger.add_handler(:default, :logger_std_h, add_opts)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
