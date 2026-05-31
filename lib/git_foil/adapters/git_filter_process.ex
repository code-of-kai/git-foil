defmodule GitFoil.Adapters.GitFilterProcess do
  @moduledoc """
  Git long-running filter process (`filter.gitfoil.process`).

  This is the same protocol Git LFS uses: instead of spawning a fresh
  `git-foil clean`/`smudge` process per file, Git starts **one** persistent
  `git-foil filter-process` and streams every clean/smudge request to it over
  stdin/stdout using the pkt-line protocol.

  ## Why this exists

  The per-file `clean`/`smudge` model boots a BEAM and `dlopen`s the five
  crypto NIFs once per file. Under a multi-file `git add`/`status`/`stash -u`,
  hundreds of processes `dlopen` the same `.so` files within milliseconds,
  racing macOS dyld and intermittently failing the NIF load. A single
  long-running process `dlopen`s **once at startup** with no concurrency, so
  the race is structurally impossible — not merely retried.

  ## Transport-only guarantee

  This module changes only *how* Git delivers `(content, pathname)`. It feeds
  the exact same pathname Git provides (`pathname=` packet, identical to the
  `%f` substitution used by `clean`/`smudge`) into the unchanged
  `GitFoil.Adapters.GitFilter` clean/smudge logic. Ciphertext is byte-for-byte
  identical to the `clean`/`smudge` path, so existing repositories decrypt
  unchanged and Git sees no spurious modifications.

  ## Protocol (version 2)

      git> git-filter-client / version=2 / <flush>
      we> git-filter-server / version=2 / <flush>
      git> capability=clean / capability=smudge / capability=delay / <flush>
      we> capability=clean / capability=smudge / <flush>          # we omit delay

      # per file:
      git> command=clean / pathname=foo / <flush> / <content...> / <flush>
      we> status=success / <flush> / <ciphertext...> / <flush> / <flush>
  """

  alias GitFoil.Adapters.{GitFilter, PktLine}
  alias GitFoil.Native.RustlerLoader

  @our_capabilities ["clean", "smudge"]

  @doc """
  Runs the filter process loop until Git closes the stream.

  `opts` may carry password-source options (e.g. `:password_source`) so power
  users can configure `filter.gitfoil.process = git-foil filter-process
  --password-file <path>`; these apply to every request in the session.

  Returns `{:ok, 0}` on a clean end-of-session, `{:error, exit_code}` if the
  crypto NIFs cannot be loaded at startup (Git then reports a filter-process
  failure; with `clean`/`smudge` still configured, *old* Git that ignores the
  `.process` key falls back to them).
  """
  @spec run(keyword()) :: {:ok, 0} | {:error, pos_integer()}
  def run(opts \\ []) do
    in_dev = Keyword.get(opts, :input, :standard_io)
    out_dev = Keyword.get(opts, :output, :standard_io)

    # CRITICAL: stdout IS the pkt-line wire. Any stray byte corrupts it. In an
    # escript the Erlang logger handler defaults to standard_io, so redirect it
    # to standard_error before anything can log (e.g. RustlerLoader on a NIF
    # failure). Our own protocol diagnostics go to :stderr explicitly.
    redirect_logging_to_stderr()

    # The protocol is binary; latin1 keeps bytes 1:1 with no transcoding.
    :io.setopts(in_dev, [:binary, encoding: :latin1])
    :io.setopts(out_dev, [:binary, encoding: :latin1])

    # Load every NIF exactly once, here, before serving any request. A single
    # sequential dlopen has no concurrent contention, so this is the point at
    # which the historical race is eliminated.
    case RustlerLoader.force_load_nifs() do
      :ok ->
        GitFilter.put_password_options(filter_password_opts(opts))

        with :ok <- handshake(in_dev, out_dev),
             :ok <- negotiate_capabilities(in_dev, out_dev) do
          serve(in_dev, out_dev)
        else
          {:error, reason} ->
            log_stderr("git-foil filter-process handshake failed: #{inspect(reason)}")
            {:error, 1}
        end

      {:error, reason} ->
        # Could not load crypto NIFs at all. Exit non-zero before the
        # handshake so Git reports a process-start failure rather than us
        # silently mis-filtering. EX_UNAVAILABLE (69) signals "the binary is
        # present but a required component is unavailable".
        IO.puts(
          :stderr,
          "git-foil: failed to load crypto libraries for filter-process (#{inspect(reason)}). " <>
            "This usually indicates a corrupt or missing native library install."
        )

        {:error, 69}
    end
  end

  # ==========================================================================
  # Handshake
  # ==========================================================================

  defp handshake(in_dev, out_dev) do
    with {:ok, lines} <- read_lines(in_dev),
         :ok <- expect(lines, "git-filter-client"),
         :ok <- expect_version(lines) do
      :ok = write_packets(out_dev, [PktLine.encode_text("git-filter-server"), PktLine.encode_text("version=2")])
      :ok = write_flush(out_dev)
      :ok
    end
  end

  defp expect(lines, token) do
    if token in lines, do: :ok, else: {:error, {:missing_handshake_token, token, lines}}
  end

  defp expect_version(lines) do
    versions =
      lines
      |> Enum.flat_map(fn line ->
        case parse_kv(line) do
          {"version", v} -> [v]
          _ -> []
        end
      end)

    if "2" in versions, do: :ok, else: {:error, {:unsupported_versions, versions}}
  end

  # ==========================================================================
  # Capability negotiation
  # ==========================================================================

  defp negotiate_capabilities(in_dev, out_dev) do
    case read_lines(in_dev) do
      {:ok, lines} ->
        offered =
          lines
          |> Enum.flat_map(fn line ->
            case parse_kv(line) do
              {"capability", cap} -> [cap]
              _ -> []
            end
          end)

        # Advertise only the intersection of what Git offers and what we
        # implement. We deliberately do NOT advertise `delay`, keeping every
        # response synchronous.
        ours = Enum.filter(@our_capabilities, &(&1 in offered))

        packets = Enum.map(ours, &PktLine.encode_text("capability=#{&1}"))
        :ok = write_packets(out_dev, packets)
        :ok = write_flush(out_dev)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ==========================================================================
  # Request loop
  # ==========================================================================

  defp serve(in_dev, out_dev) do
    case read_command(in_dev) do
      :eof ->
        # Git closed the stream at a list boundary: clean end of session.
        {:ok, 0}

      {:ok, meta} ->
        case handle_command(in_dev, out_dev, meta) do
          :ok -> serve(in_dev, out_dev)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        log_stderr("git-foil filter-process: protocol error reading command: #{inspect(reason)}")
        {:error, 1}
    end
  end

  defp read_command(in_dev) do
    case PktLine.read_until_flush(in_dev) do
      :eof -> :eof
      {:ok, lines} -> {:ok, parse_meta(lines)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_meta(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      # Metadata lines are text and carry a trailing newline; strip it before
      # parsing so values like "clean\n" become "clean". (Content packets are
      # handled separately and are NEVER trimmed — they are raw bytes.)
      case parse_kv(String.trim_trailing(line, "\n")) do
        {k, v} -> Map.put(acc, k, v)
        _ -> acc
      end
    end)
  end

  defp handle_command(in_dev, out_dev, %{"command" => command} = meta)
       when command in ["clean", "smudge"] do
    pathname = Map.get(meta, "pathname", "")

    with {:ok, content} <- read_content(in_dev) do
      operation = String.to_existing_atom(command)
      respond(out_dev, run_filter(operation, content, pathname))
    else
      {:error, reason} ->
        log_stderr("git-foil filter-process: failed reading content: #{inspect(reason)}")
        write_status_error(out_dev)
    end
  end

  # `command=list_available_blobs` only arrives if we advertised `delay`, which
  # we never do. Any other command is unexpected; report an error response and
  # keep the session alive so Git can decide how to proceed.
  defp handle_command(_in_dev, out_dev, meta) do
    log_stderr("git-foil filter-process: unexpected command: #{inspect(meta)}")
    write_status_error(out_dev)
  end

  defp read_content(in_dev) do
    case PktLine.read_until_flush(in_dev) do
      {:ok, payloads} -> {:ok, IO.iodata_to_binary(payloads)}
      :eof -> {:error, :unexpected_eof_in_content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_filter(:clean, content, pathname), do: GitFilter.clean(content, pathname)
  defp run_filter(:smudge, content, pathname), do: GitFilter.smudge(content, pathname)

  # ==========================================================================
  # Responses
  # ==========================================================================

  # Success: status list (status=success + flush), then content (chunked) +
  # flush, then a final empty status list (flush) keeping the status unchanged.
  defp respond(out_dev, {:ok, output}) do
    with :ok <- write_packets(out_dev, [PktLine.encode_text("status=success")]),
         :ok <- write_flush(out_dev),
         :ok <- write_packets(out_dev, PktLine.encode_data(output)),
         :ok <- write_flush(out_dev),
         :ok <- write_flush(out_dev) do
      :ok
    end
  end

  # Both {exit_code, message} and bare-reason errors map to a single
  # status=error response. With required=true Git aborts the operation, which
  # mirrors the non-zero exit of the per-file clean/smudge path (fail closed —
  # never store plaintext on a crypto failure).
  defp respond(out_dev, {:error, {_exit_code, message}}) when is_binary(message) do
    IO.puts(:stderr, message)
    write_status_error(out_dev)
  end

  defp respond(out_dev, {:error, reason}) do
    IO.puts(:stderr, "git-foil filter-process error: #{inspect(reason)}")
    write_status_error(out_dev)
  end

  defp write_status_error(out_dev) do
    with :ok <- write_packets(out_dev, [PktLine.encode_text("status=error")]),
         :ok <- write_flush(out_dev) do
      :ok
    end
  end

  # ==========================================================================
  # IO helpers
  # ==========================================================================

  defp read_lines(in_dev) do
    case PktLine.read_until_flush(in_dev) do
      {:ok, payloads} -> {:ok, Enum.map(payloads, &String.trim_trailing(&1, "\n"))}
      :eof -> {:error, :unexpected_eof_in_handshake}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_packets(_out_dev, []), do: :ok

  defp write_packets(out_dev, packets) do
    IO.binwrite(out_dev, IO.iodata_to_binary(packets))
  end

  defp write_flush(out_dev), do: IO.binwrite(out_dev, PktLine.flush())

  defp parse_kv(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> {key, value}
      _ -> :no_kv
    end
  end

  defp filter_password_opts(opts) do
    opts
    |> Keyword.take([:password_source])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # Protocol diagnostics go to stderr directly, never via Logger — Logger's
  # output device is not guaranteed to be stderr, and stdout is the wire.
  defp log_stderr(message), do: IO.puts(:stderr, message)

  # Point the Erlang logger's default handler at standard_error so that any
  # log emitted by a dependency (e.g. RustlerLoader) cannot land on stdout and
  # corrupt the pkt-line stream. Best-effort: tolerate any handler shape.
  defp redirect_logging_to_stderr do
    _ = :logger.update_handler_config(:default, :config, %{type: :standard_error})
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
