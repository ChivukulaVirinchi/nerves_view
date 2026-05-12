defmodule NervesView.Recording.TsMuxerTest do
  use ExUnit.Case, async: true

  alias NervesView.Recording.TsMuxer

  # Synthetic NAL units for testing.
  # Real NALs start with a header byte where bits [4:0] = NAL type.
  # Type 7 = SPS, Type 8 = PPS, Type 5 = IDR, Type 1 = non-IDR slice.
  @sps_nal <<0x67, 0x42, 0x00, 0x1E, 0xAB, 0x40, 0x50>>
  @pps_nal <<0x68, 0xCE, 0x38, 0x80>>
  @idr_nal <<0x65, 0x88, 0x84, 0x00, 0x33, 0xFF>> <> :binary.copy(<<0xAB>>, 100)
  @slice_nal <<0x41, 0x9A, 0x24, 0x6C, 0x41>> <> :binary.copy(<<0xCD>>, 50)

  describe "mux_segment/2" do
    test "produces a valid MPEG-TS binary with correct sync bytes" do
      nals = [@sps_nal, @pps_nal, @idr_nal, @slice_nal, @slice_nal]
      result = TsMuxer.mux_segment(nals)

      assert is_binary(result)
      # Must be a multiple of 188 bytes
      assert rem(byte_size(result), 188) == 0
      # Every 188-byte packet starts with sync byte 0x47
      assert_all_sync_bytes(result)
    end

    test "first two packets are PAT and PMT" do
      result = TsMuxer.mux_segment([@idr_nal])

      <<pat_packet::binary-size(188), pmt_packet::binary-size(188), _rest::binary>> = result

      # PAT: sync=0x47, PID=0x0000
      <<0x47, _tei::1, pusi_pat::1, _tp::1, pid_pat::13, _::binary>> = pat_packet
      assert pid_pat == 0x0000
      assert pusi_pat == 1

      # PMT: sync=0x47, PID=0x1000
      <<0x47, _tei::1, _pusi::1, _tp::1, pid_pmt::13, _::binary>> = pmt_packet
      assert pid_pmt == 0x1000
    end

    test "video packets use PID 0x0100" do
      result = TsMuxer.mux_segment([@idr_nal])
      # Skip PAT + PMT (first 2 packets)
      <<_pat::binary-size(188), _pmt::binary-size(188), first_video::binary-size(188), _::binary>> =
        result

      <<0x47, _tei::1, _pusi::1, _tp::1, pid::13, _::binary>> = first_video
      assert pid == 0x0100
    end

    test "handles empty NAL list" do
      result = TsMuxer.mux_segment([])

      # Should still produce PAT + PMT
      assert is_binary(result)
      assert rem(byte_size(result), 188) == 0
      # At minimum PAT + PMT = 376 bytes
      assert byte_size(result) >= 376
    end

    test "handles single small NAL" do
      result = TsMuxer.mux_segment([<<0x65, 0x00, 0x01>>])

      assert is_binary(result)
      assert rem(byte_size(result), 188) == 0
      assert_all_sync_bytes(result)
    end

    test "handles large NALs requiring multiple TS packets" do
      # 10KB NAL — will need multiple 188-byte TS packets
      large_nal = <<0x65>> <> :binary.copy(<<0xAA>>, 10_000)
      result = TsMuxer.mux_segment([large_nal])

      assert is_binary(result)
      assert rem(byte_size(result), 188) == 0
      assert_all_sync_bytes(result)
      # At least PAT + PMT + many video packets
      assert byte_size(result) > 188 * 50
    end

    test "respects initial_pts option" do
      result1 = TsMuxer.mux_segment([@idr_nal], initial_pts: 0)
      result2 = TsMuxer.mux_segment([@idr_nal], initial_pts: 90_000)

      # Different PTS should produce different PES headers, thus different output
      assert result1 != result2
    end

    test "respects pts_increment option" do
      nals = [@idr_nal, @slice_nal, @slice_nal]
      result1 = TsMuxer.mux_segment(nals, pts_increment: 3_000)
      result2 = TsMuxer.mux_segment(nals, pts_increment: 6_000)

      assert result1 != result2
    end

    test "produces deterministic output for same input" do
      nals = [@sps_nal, @pps_nal, @idr_nal, @slice_nal]
      result1 = TsMuxer.mux_segment(nals, initial_pts: 0)
      result2 = TsMuxer.mux_segment(nals, initial_pts: 0)

      assert result1 == result2
    end

    test "muxes a realistic segment with multiple frames" do
      nals =
        [@sps_nal, @pps_nal, @idr_nal] ++
          List.duplicate(@slice_nal, 89)

      result = TsMuxer.mux_segment(nals, initial_pts: 0, pts_increment: 6_000)

      assert is_binary(result)
      assert rem(byte_size(result), 188) == 0
      assert_all_sync_bytes(result)
      # ~90 NALs at ~55 bytes each plus overhead — should be several KB
      assert byte_size(result) > 5_000
    end
  end

  # ── Helpers ──

  defp assert_all_sync_bytes(ts_binary) do
    packet_count = div(byte_size(ts_binary), 188)

    for i <- 0..(packet_count - 1) do
      <<_skip::binary-size(i * 188), 0x47, _rest::binary>> = ts_binary
    end
  end
end
