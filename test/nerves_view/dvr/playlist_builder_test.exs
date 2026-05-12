defmodule NervesView.DVR.PlaylistBuilderTest do
  use ExUnit.Case, async: true

  alias NervesView.DVR.PlaylistBuilder

  @segments [
    %{started_at: 1_700_000_000, duration: 6, filename: "seg-1700000000.ts", size: 5000},
    %{started_at: 1_700_000_006, duration: 6, filename: "seg-1700000006.ts", size: 5100},
    %{started_at: 1_700_000_012, duration: 6, filename: "seg-1700000012.ts", size: 4900}
  ]

  describe "build/3" do
    test "produces valid HLS EVENT playlist" do
      result = PlaylistBuilder.build("cam-1", @segments)

      assert result =~ "#EXTM3U"
      assert result =~ "#EXT-X-VERSION:3"
      assert result =~ "#EXT-X-TARGETDURATION:6"
      assert result =~ "#EXT-X-MEDIA-SEQUENCE:0"
      assert result =~ "#EXT-X-PLAYLIST-TYPE:EVENT"
      assert result =~ "#EXTINF:6,"
      assert result =~ "/api/dvr/cam-1/segments/seg-1700000000.ts"
      assert result =~ "/api/dvr/cam-1/segments/seg-1700000012.ts"
      refute result =~ "#EXT-X-ENDLIST"
    end

    test "uses custom base_url" do
      result = PlaylistBuilder.build("cam-1", @segments, base_url: "/custom")

      assert result =~ "/custom/cam-1/segments/seg-1700000000.ts"
    end

    test "TARGETDURATION reflects longest segment" do
      segments = [
        %{started_at: 100, duration: 4, filename: "seg-100.ts", size: 100},
        %{started_at: 104, duration: 10, filename: "seg-104.ts", size: 100}
      ]

      result = PlaylistBuilder.build("cam-1", segments)
      assert result =~ "#EXT-X-TARGETDURATION:10"
    end

    test "handles empty segment list" do
      result = PlaylistBuilder.build("cam-1", [])

      assert result =~ "#EXTM3U"
      assert result =~ "#EXT-X-TARGETDURATION:7"
      refute result =~ "#EXTINF"
    end
  end

  describe "build_vod/3" do
    test "includes EXT-X-ENDLIST" do
      result = PlaylistBuilder.build_vod("cam-1", @segments)

      assert result =~ "#EXTM3U"
      assert result =~ "#EXT-X-ENDLIST"
    end
  end
end
