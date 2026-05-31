defmodule GitFoil.Adapters.PktLineTest do
  use ExUnit.Case, async: true

  alias GitFoil.Adapters.PktLine

  @max PktLine.max_payload()

  describe "encode/1 and length prefix" do
    test "prefixes with 4-hex length that INCLUDES the 4 prefix bytes" do
      # "a\n" is 2 bytes -> total 6 -> "0006"
      assert PktLine.encode("a\n") == "0006a\n"
    end

    test "encode_text appends a trailing newline inside the payload" do
      # "version=2\n" is 10 bytes -> total 14 -> 0x000e
      assert PktLine.encode_text("version=2") == "000eversion=2\n"
    end

    test "flush is exactly 0000" do
      assert PktLine.flush() == "0000"
    end

    test "raises if a single packet would exceed max payload" do
      assert_raise ArgumentError, fn -> PktLine.encode(:binary.copy("x", @max + 1)) end
    end

    test "encodes a packet at exactly max payload" do
      packet = PktLine.encode(:binary.copy("x", @max))
      # 65516 + 4 = 65520 = 0xfff0
      assert binary_part(packet, 0, 4) == "fff0"
      assert byte_size(packet) == 65520
    end
  end

  describe "encode_data/1 chunking" do
    test "empty content yields no packets" do
      assert PktLine.encode_data("") == []
    end

    test "content at or below max is a single packet" do
      assert length(PktLine.encode_data(:binary.copy("x", @max))) == 1
    end

    test "content one byte over max splits into two packets" do
      assert length(PktLine.encode_data(:binary.copy("x", @max + 1))) == 2
    end
  end

  describe "read_until_flush/1 round-trips encode_data/1 (framing correctness)" do
    # These sizes are exactly where long-running-filter bugs hide: empty,
    # one byte, exactly on packet boundaries, just over, and multi-packet.
    for size <- [0, 1, 100, @max - 1, @max, @max + 1, 2 * @max, 2 * @max + 1, 5 * @max + 123] do
      test "size #{size} reassembles byte-for-byte" do
        size = unquote(size)
        content = random_binary(size)

        wire = IO.iodata_to_binary(PktLine.encode_data(content) ++ [PktLine.flush()])
        {:ok, device} = StringIO.open(wire)
        :io.setopts(device, [:binary, encoding: :latin1])

        assert {:ok, payloads} = PktLine.read_until_flush(device)
        assert IO.iodata_to_binary(payloads) == content
      end
    end
  end

  describe "read_packet/1 control packets and errors" do
    test "decodes flush as :flush" do
      {:ok, device} = StringIO.open("0000")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert PktLine.read_packet(device) == :flush
    end

    test "clean EOF at a boundary returns :eof" do
      {:ok, device} = StringIO.open("")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert PktLine.read_packet(device) == :eof
    end

    test "invalid hex prefix is an error" do
      {:ok, device} = StringIO.open("zzzz")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert {:error, {:invalid_pkt_length, "zzzz"}} = PktLine.read_packet(device)
    end

    test "truncated payload is an error" do
      # Claims 10-byte payload (000e) but only 3 bytes follow.
      {:ok, device} = StringIO.open("000eabc")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert {:error, {:truncated_packet, _}} = PktLine.read_packet(device)
    end

    test "binary content with embedded NULs and high bytes survives a round-trip" do
      content = <<0, 1, 2, 255, 254, 0, 0, 10, 13, 200, 199>>
      wire = IO.iodata_to_binary(PktLine.encode_data(content) ++ [PktLine.flush()])
      {:ok, device} = StringIO.open(wire)
      :io.setopts(device, [:binary, encoding: :latin1])
      assert {:ok, payloads} = PktLine.read_until_flush(device)
      assert IO.iodata_to_binary(payloads) == content
    end

    test "decodes delim (0001) as a distinct :delim, NOT :flush" do
      {:ok, device} = StringIO.open("0001")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert PktLine.read_packet(device) == :delim
    end

    test "decodes response-end (0002) as a distinct :response_end, NOT :flush" do
      {:ok, device} = StringIO.open("0002")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert PktLine.read_packet(device) == :response_end
    end
  end

  describe "read_until_flush/1 control-packet handling (anti-truncation)" do
    test "a delim packet mid-section is a hard error, not a silent section end" do
      # A real data packet ("0006a\n"), then a delim (0001) where the filter
      # protocol only ever expects flush. Coercing delim to flush would
      # silently truncate after one payload; we must fail fast instead.
      {:ok, device} = StringIO.open("0006a\n0001")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert {:error, {:unexpected_control_packet, :delim}} =
               PktLine.read_until_flush(device)
    end

    test "a response-end packet mid-section is a hard error" do
      {:ok, device} = StringIO.open("0006a\n0002")
      :io.setopts(device, [:binary, encoding: :latin1])
      assert {:error, {:unexpected_control_packet, :response_end}} =
               PktLine.read_until_flush(device)
    end
  end

  # Deterministic pseudo-random bytes (no Date/random dependency).
  defp random_binary(0), do: <<>>

  defp random_binary(n) do
    0..(n - 1)
    |> Enum.map(&rem(&1 * 31 + 7, 256))
    |> :erlang.list_to_binary()
  end
end
