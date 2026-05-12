defmodule NervesView.DVR.PlaylistBuilder do
  @moduledoc """
  Generates HLS playlists from a list of segment metadata.

  Pure functions — no state, no side effects. Used by `DVRController`
  to build on-the-fly VOD playlists for timeline scrubbing.
  """

  @doc """
  Builds an HLS EVENT playlist from a list of segments.

  The playlist uses `EXT-X-PLAYLIST-TYPE:EVENT` so players know it may
  grow as new segments are produced, and will re-fetch periodically.

  Each segment URI is built as a relative path suitable for the
  DVR segment-serving endpoint.

  ## Options

    * `:camera_id` - camera ID for building segment URLs (required)
    * `:base_url` - URL prefix for segments (default: "/api/dvr")

  """
  @spec build(String.t(), [map()], keyword()) :: String.t()
  def build(camera_id, segments, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "/api/dvr")
    target_duration = max_duration(segments)

    header = """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-TARGETDURATION:#{target_duration}
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-PLAYLIST-TYPE:EVENT
    """

    entries =
      Enum.map_join(segments, fn seg ->
        url = "#{base_url}/#{camera_id}/segments/#{seg.filename}"
        "#EXTINF:#{seg.duration},\n#{url}\n"
      end)

    String.trim(header) <> "\n" <> entries
  end

  @doc """
  Builds a finalized VOD playlist (with `EXT-X-ENDLIST`).
  Used for completed time ranges that won't grow.
  """
  @spec build_vod(String.t(), [map()], keyword()) :: String.t()
  def build_vod(camera_id, segments, opts \\ []) do
    build(camera_id, segments, opts) <> "#EXT-X-ENDLIST\n"
  end

  defp max_duration([]), do: 7

  defp max_duration(segments) do
    segments
    |> Enum.map(& &1.duration)
    |> Enum.max()
    |> max(1)
  end
end
