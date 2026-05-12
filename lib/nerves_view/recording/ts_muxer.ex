defmodule NervesView.Recording.TsMuxer do
  @moduledoc """
  Pure Elixir MPEG-TS muxer for a single H.264 video elementary stream.

  Converts a list of raw H.264 NAL unit binaries into a valid MPEG-TS
  binary suitable for HLS segment files (.ts). No external dependencies.

  Reference: ISO/IEC 13818-1 (MPEG-TS), ITU-T H.264 Annex B.
  """

  import Bitwise

  # ── Constants ──

  @ts_packet_size 188
  @sync_byte 0x47
  @pat_pid 0x0000
  @pmt_pid 0x1000
  @video_pid 0x0100
  @stream_type_h264 0x1B
  @stuffing_byte 0xFF

  # ── Public API ──

  @doc """
  Muxes a list of raw H.264 NAL binaries into a complete MPEG-TS segment.

  Each NAL is wrapped with an Annex B start code, packed into PES packets,
  and split into 188-byte TS packets. PAT and PMT tables are prepended.

  ## Options

    * `:initial_pts` - 90kHz PTS for the first NAL (default: 0)
    * `:pts_increment` - PTS ticks between NALs (default: 6000 for 15fps)

  Returns a binary containing the complete `.ts` file content.
  """
  @spec mux_segment([binary()], keyword()) :: binary()
  def mux_segment(nals, opts \\ []) when is_list(nals) do
    initial_pts = Keyword.get(opts, :initial_pts, 0)
    pts_increment = Keyword.get(opts, :pts_increment, 6_000)

    pat = build_pat(0)
    pmt = build_pmt(0)

    {video_packets, _cc} =
      nals
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {nal, idx}, {acc, cc} ->
        pts = rem(initial_pts + idx * pts_increment, 1 <<< 33)
        is_rap = nal_is_rap?(nal)
        {packets, next_cc} = nal_to_ts_packets(nal, pts, cc, is_rap)
        {[packets | acc], next_cc}
      end)

    IO.iodata_to_binary([pat, pmt | Enum.reverse(video_packets)])
  end

  # ── PAT (Program Association Table) ──

  defp build_pat(cc) do
    # Table: program_number=1 → PMT PID
    table_data = <<
      # table_id=0x00, section_syntax=1, reserved, section_length
      0x00, 0b1011::4, 13::12,
      # transport_stream_id
      0x0001::16,
      # reserved, version=0, current_next=1
      0b11::2, 0::5, 1::1,
      # section_number, last_section_number
      0::8, 0::8,
      # program_number=1, reserved, PMT PID
      0x0001::16, 0b111::3, @pmt_pid::13
    >>

    crc = crc32_mpeg(table_data)
    section = <<0x00, table_data::binary, crc::32>>
    wrap_single_ts_packet(section, @pat_pid, cc, true)
  end

  # ── PMT (Program Map Table) ──

  defp build_pmt(cc) do
    table_data = <<
      # table_id=0x02, section_syntax=1, reserved, section_length
      0x02, 0b1011::4, 18::12,
      # program_number=1
      0x0001::16,
      # reserved, version=0, current_next=1
      0b11::2, 0::5, 1::1,
      # section_number, last_section_number
      0::8, 0::8,
      # reserved, PCR PID = video PID
      0b111::3, @video_pid::13,
      # reserved, program_info_length=0
      0b1111::4, 0::12,
      # stream: type=H.264, reserved, elementary PID, reserved, ES info length=0
      @stream_type_h264::8, 0b111::3, @video_pid::13, 0b1111::4, 0::12
    >>

    crc = crc32_mpeg(table_data)
    section = <<0x00, table_data::binary, crc::32>>
    wrap_single_ts_packet(section, @pmt_pid, cc, true)
  end

  # ── NAL → PES → TS packets ──

  defp nal_to_ts_packets(nal, pts, cc, is_rap) do
    # Prepend Annex B start code
    annexb_nal = <<0, 0, 0, 1, nal::binary>>
    pes = build_pes_packet(annexb_nal, pts)
    packetize_pes(pes, @video_pid, cc, pts, is_rap)
  end

  defp build_pes_packet(payload, pts) do
    pts_bytes = encode_pts(pts)

    # PES header:
    # start code prefix (3 bytes) + stream_id (0xE0 = video)
    # PES packet length (0 = unbounded for video)
    # flags: marker=10, no scrambling, no priority, no alignment, no copyright, no original
    # PTS/DTS flags = 10 (PTS only), no ESCR, no ES rate, no DSM, no additional copy info, no CRC, no extension
    # PES header data length = 5 (PTS only)
    <<
      0x00, 0x00, 0x01, 0xE0,
      0x0000::16,
      0b10::2, 0::2, 0::1, 0::1, 0::1, 0::1,
      0b10::2, 0::6,
      5::8,
      pts_bytes::binary-size(5),
      payload::binary
    >>
  end

  defp encode_pts(pts) do
    # 5-byte PTS encoding per ISO 13818-1
    # Marker bits: 0010 xxx1 xxxx xxxx xxxx xxx1 xxxx xxxx xxxx xxx1
    p32 = pts >>> 30 &&& 0x07
    p29 = pts >>> 15 &&& 0x7FFF
    p14 = pts &&& 0x7FFF

    <<0b0010::4, p32::3, 1::1, p29::15, 1::1, p14::15, 1::1>>
  end

  # ── TS packetization ──

  defp packetize_pes(pes, pid, cc, pcr, is_rap) do
    adaptation = build_adaptation_field(pcr, is_rap)
    overhead = 4 + byte_size(adaptation)
    max_first = @ts_packet_size - overhead
    {first_chunk, rest} = split_binary(pes, max_first)

    # First packet: PUSI=1, adaptation + payload
    first_header = ts_header(pid, 0b11, cc, _pusi = 1)
    padding = :binary.copy(<<@stuffing_byte>>, max_first - byte_size(first_chunk))
    first_packet = IO.iodata_to_binary([first_header, adaptation, first_chunk, padding])
    cc = rem(cc + 1, 16)

    # Continuation packets
    {cont_packets, final_cc} = packetize_continuation(rest, pid, cc)
    {[first_packet | cont_packets], final_cc}
  end

  defp packetize_continuation(<<>>, _pid, cc), do: {[], cc}

  defp packetize_continuation(data, pid, cc) do
    max_payload = @ts_packet_size - 4

    data
    |> chunk_binary(max_payload)
    |> Enum.reduce({[], cc}, fn chunk, {acc, cur_cc} ->
      packet = build_continuation_packet(chunk, pid, cur_cc, max_payload)
      {[packet | acc], rem(cur_cc + 1, 16)}
    end)
    |> then(fn {pkts, final_cc} -> {Enum.reverse(pkts), final_cc} end)
  end

  defp build_continuation_packet(payload, pid, cc, max_payload) do
    pad_needed = max_payload - byte_size(payload)

    if pad_needed == 0 do
      header = ts_header(pid, 0b01, cc, _pusi = 0)
      <<header::binary, payload::binary>>
    else
      # Stuff via adaptation field: 1 byte length + 1 byte flags + N-2 stuffing
      adapt_len = pad_needed - 1
      flags = <<0>>
      stuffing = :binary.copy(<<@stuffing_byte>>, max(adapt_len - 1, 0))
      adaptation = IO.iodata_to_binary([<<adapt_len>>, flags, stuffing])
      header = ts_header(pid, 0b11, cc, _pusi = 0)
      IO.iodata_to_binary([header, adaptation, payload])
    end
  end

  defp ts_header(pid, afc, cc, pusi) do
    <<
      @sync_byte::8,
      0::1, pusi::1, 0::1, pid::13,
      0::2, afc::2, rem(cc, 16)::4
    >>
  end

  defp build_adaptation_field(pcr, is_rap) do
    pcr_base = rem(pcr, 1 <<< 33)
    pcr_bytes = <<pcr_base::33, 0b111111::6, 0::9>>
    flags = if is_rap, do: 0b01010000, else: 0b00010000
    content = IO.iodata_to_binary([<<flags>>, pcr_bytes])
    <<byte_size(content)::8, content::binary>>
  end

  # ── Helpers ──

  defp wrap_single_ts_packet(payload, pid, cc, pusi) do
    max_payload = @ts_packet_size - 4
    payload_len = byte_size(payload)
    stuffing_len = max_payload - payload_len
    pusi_val = if pusi, do: 1, else: 0

    if stuffing_len > 0 do
      header = ts_header(pid, 0b11, cc, pusi_val)
      adapt_data_len = stuffing_len - 1
      stuffing = :binary.copy(<<@stuffing_byte>>, max(adapt_data_len - 1, 0))
      adaptation = IO.iodata_to_binary([<<adapt_data_len::8, 0::8>>, stuffing])
      IO.iodata_to_binary([header, adaptation, payload])
    else
      header = ts_header(pid, 0b01, cc, pusi_val)
      <<header::binary, payload::binary>>
    end
  end

  defp nal_is_rap?(<<header, _rest::binary>>), do: (header &&& 0x1F) == 5
  defp nal_is_rap?(_), do: false

  defp split_binary(bin, max) when byte_size(bin) <= max, do: {bin, <<>>}

  defp split_binary(bin, max) do
    <<chunk::binary-size(max), rest::binary>> = bin
    {chunk, rest}
  end

  defp chunk_binary(<<>>, _size), do: []

  defp chunk_binary(bin, size) when byte_size(bin) <= size, do: [bin]

  defp chunk_binary(bin, size) do
    <<chunk::binary-size(size), rest::binary>> = bin
    [chunk | chunk_binary(rest, size)]
  end

  # ── CRC-32/MPEG-2 ──

  # MPEG-2 uses a standard CRC-32 with polynomial 0x04C11DB7.
  # We use a lookup table for performance.

  @crc_table (
    for i <- 0..255 do
      Enum.reduce(0..7, i <<< 24, fn _bit, crc ->
        if (crc &&& 0x80000000) != 0 do
          bxor(crc <<< 1, 0x04C11DB7) &&& 0xFFFFFFFF
        else
          (crc <<< 1) &&& 0xFFFFFFFF
        end
      end)
    end
    |> List.to_tuple()
  )

  defp crc32_mpeg(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(0xFFFFFFFF, fn byte, crc ->
      idx = bxor(crc >>> 24, byte) &&& 0xFF
      bxor(crc <<< 8, elem(@crc_table, idx)) &&& 0xFFFFFFFF
    end)
  end
end
