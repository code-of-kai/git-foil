defmodule GitFoil.Adapters.PktLine do
  @moduledoc """
  Codec for Git's pkt-line wire format, used by the long-running filter
  process protocol (`filter.<driver>.process`).

  ## Wire format

  Each packet is a 4-byte, lowercase-hex length prefix followed by a payload.
  Crucially, the length **includes the 4 prefix bytes themselves**:

      "0006a\n"   => length 0x0006 = 6 bytes total => 2-byte payload "a\n"
      "0000"      => flush packet (a control marker, NOT a zero-length payload)

  The maximum packet length is `0xfff0` (65520), so the maximum payload is
  65516 bytes (`LARGE_PACKET_DATA_MAX` in Git's source). Larger content must
  be split across multiple data packets.

  Text control lines (e.g. `version=2`, `status=success`) carry a trailing
  newline *inside* the payload. Binary file content is framed verbatim with
  no added newline.

  This module is intentionally transport-only: it never inspects or mutates
  file content beyond chunking it into packets, so ciphertext produced by the
  encryption engine reaches Git byte-for-byte unchanged.
  """

  # Git's LARGE_PACKET_DATA_MAX: 65520 (0xfff0) total - 4 prefix bytes.
  @max_payload 65516

  @flush "0000"

  @doc "Maximum payload bytes per data packet."
  @spec max_payload() :: pos_integer()
  def max_payload, do: @max_payload

  @doc "The flush packet (`\"0000\"`)."
  @spec flush() :: binary()
  def flush, do: @flush

  @doc """
  Encodes a single payload into one pkt-line packet.

  Raises if the payload exceeds `max_payload/0`; callers with arbitrary-length
  content must use `encode_data/1`, which chunks.
  """
  @spec encode(binary()) :: binary()
  def encode(payload) when is_binary(payload) do
    size = byte_size(payload)

    if size > @max_payload do
      raise ArgumentError,
            "pkt-line payload #{size} exceeds max #{@max_payload}; use encode_data/1"
    end

    length_prefix(size + 4) <> payload
  end

  @doc """
  Encodes a text control line, appending the trailing newline Git expects.

  `encode_text("version=2")` => `"000bversion=2\n"`.
  """
  @spec encode_text(binary()) :: binary()
  def encode_text(line) when is_binary(line), do: encode(line <> "\n")

  @doc """
  Encodes arbitrary-length binary content into a list of data packets,
  each at most `max_payload/0` bytes. Empty content yields an empty list
  (the caller emits a flush to denote "no content").
  """
  @spec encode_data(binary()) :: [binary()]
  def encode_data(<<>>), do: []

  def encode_data(content) when is_binary(content) do
    content
    |> chunk(@max_payload, [])
    |> Enum.map(&encode/1)
  end

  defp chunk(<<>>, _size, acc), do: Enum.reverse(acc)

  defp chunk(bin, size, acc) when byte_size(bin) <= size do
    Enum.reverse([bin | acc])
  end

  defp chunk(bin, size, acc) do
    <<head::binary-size(size), rest::binary>> = bin
    chunk(rest, size, [head | acc])
  end

  defp length_prefix(total) do
    total
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(4, "0")
  end

  @doc """
  Reads one packet from `device` (binary-mode IO device).

  Returns:
  - `{:data, payload}` for a normal data packet (payload has its trailing
    newline preserved, if any — the caller decides whether to strip it)
  - `:flush` for a flush packet (`0000`)
  - `:delim` for a delimiter packet (`0001`)
  - `:response_end` for a response-end packet (`0002`)
  - `:eof` when the stream is closed at a packet boundary
  - `{:error, reason}` on a malformed prefix or truncated packet

  `:delim` and `:response_end` are protocol-v2 section markers (ls-refs/fetch,
  stateless-rpc). They never occur in the long-running filter protocol, which
  delimits exclusively with flush packets. They are decoded as *distinct*
  values rather than coerced to `:flush` so that callers fail fast on a
  desynchronised or malformed stream instead of silently truncating a section.
  """
  @spec read_packet(IO.device()) ::
          {:data, binary()} | :flush | :delim | :response_end | :eof | {:error, term()}
  def read_packet(device) do
    case read_exactly(device, 4) do
      :eof ->
        :eof

      {:error, reason} ->
        {:error, {:length_read_failed, reason}}

      {:ok, prefix} ->
        decode_prefix(device, prefix)
    end
  end

  defp decode_prefix(device, prefix) do
    case Integer.parse(prefix, 16) do
      {len, ""} -> decode_length(device, len)
      _ -> {:error, {:invalid_pkt_length, prefix}}
    end
  end

  # Control packets: 0000 flush, 0001 delim, 0002 response-end. Decoded as
  # distinct values — the filter protocol only ever uses flush, so delim and
  # response-end signal a desynchronised/malformed stream and must surface as
  # errors upstream rather than be coerced into a flush boundary.
  defp decode_length(_device, 0), do: :flush
  defp decode_length(_device, 1), do: :delim
  defp decode_length(_device, 2), do: :response_end

  defp decode_length(_device, len) when len < 4 or len > 65520 do
    {:error, {:invalid_pkt_length, len}}
  end

  defp decode_length(device, len) do
    payload_len = len - 4

    case read_exactly(device, payload_len) do
      {:ok, payload} -> {:data, payload}
      # Both a zero-byte EOF and a partial-then-EOF mean the same thing: the
      # stream ended mid-packet. Report both as a truncated packet.
      :eof -> {:error, {:truncated_packet, payload_len}}
      {:error, :unexpected_eof} -> {:error, {:truncated_packet, payload_len}}
      {:error, reason} -> {:error, {:payload_read_failed, reason}}
    end
  end

  @doc """
  Reads packets until a flush, returning the list of payloads (data packets
  only). Returns `:eof` if the stream closes before any packet is read (a
  clean end-of-session at a list boundary).
  """
  @spec read_until_flush(IO.device()) :: {:ok, [binary()]} | :eof | {:error, term()}
  def read_until_flush(device), do: read_until_flush(device, [])

  defp read_until_flush(device, acc) do
    case read_packet(device) do
      :flush ->
        {:ok, Enum.reverse(acc)}

      {:data, payload} ->
        read_until_flush(device, [payload | acc])

      :eof when acc == [] ->
        :eof

      :eof ->
        {:error, :unexpected_eof_before_flush}

      control when control in [:delim, :response_end] ->
        # A protocol-v2 section marker has no meaning in the filter protocol.
        # Fail fast instead of treating it as a flush (which would silently
        # truncate this section and desynchronise the session).
        {:error, {:unexpected_control_packet, control}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Reads exactly `count` bytes, looping over short reads. A pipe can deliver
  # fewer bytes than requested per read; we must not assume one read suffices.
  defp read_exactly(_device, 0), do: {:ok, <<>>}

  defp read_exactly(device, count) do
    read_exactly(device, count, <<>>)
  end

  defp read_exactly(_device, 0, acc), do: {:ok, acc}

  defp read_exactly(device, remaining, acc) do
    case IO.binread(device, remaining) do
      :eof when acc == <<>> ->
        :eof

      :eof ->
        # Stream closed mid-packet: caller turns this into a truncation error.
        {:error, :unexpected_eof}

      {:error, reason} ->
        {:error, reason}

      data when is_binary(data) ->
        got = byte_size(data)

        if got >= remaining do
          {:ok, acc <> data}
        else
          read_exactly(device, remaining - got, acc <> data)
        end
    end
  end
end
