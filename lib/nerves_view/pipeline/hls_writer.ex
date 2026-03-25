defmodule NervesView.Pipeline.HLSWriter do
  @moduledoc """
  File-backed HLS writer for local recording flow.
  """

  alias NervesView.Recording.Store

  @default_base_dir "tmp/recordings"

  @spec write(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def write(camera_id, opts \\ []) when is_binary(camera_id) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    duration = Keyword.get(opts, :duration_seconds, 20)
    segments = Keyword.get(opts, :segments, 4)
    mode = Keyword.get(opts, :mode, :continuous)
    segment_duration = Keyword.get(opts, :segment_duration, 6)

    rec_id = "rec-#{camera_id}-#{now}"
    base_dir = Application.get_env(:nerves_view, :recordings_path, @default_base_dir)
    dir = Path.join([base_dir, camera_id, rec_id])
    playlist_path = Path.join(dir, "playlist.m3u8")
    segment_paths = Enum.map(1..segments, &Path.join(dir, "segment-#{&1}.ts"))

    :ok = File.mkdir_p(dir)
    variant = Keyword.get(opts, :variant, :simulated)
    Enum.each(segment_paths, &write_segment_file(&1, camera_id, rec_id, variant))
    :ok = write_playlist_file(playlist_path, segment_paths, segment_duration)

    size_bytes =
      segment_paths
      |> Enum.reduce(0, fn path, acc ->
        case File.stat(path) do
          {:ok, stat} -> acc + stat.size
          _ -> acc
        end
      end)

    recording = %{
      id: rec_id,
      camera_id: camera_id,
      started_at: now,
      ended_at: now + duration,
      mode: mode,
      path: playlist_path,
      playlist_path: playlist_path,
      segment_paths: segment_paths,
      size_bytes: size_bytes
    }

    Store.put(recording)
  end

  defp write_segment_file(path, camera_id, rec_id, variant) do
    content = "NervesView segment camera=#{camera_id} recording=#{rec_id} variant=#{variant}\n"
    :ok = File.write(path, content)
  end

  defp write_playlist_file(playlist_path, segment_paths, segment_duration) do
    lines =
      [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-TARGETDURATION:#{segment_duration}",
        "#EXT-X-MEDIA-SEQUENCE:0"
      ] ++
        Enum.flat_map(segment_paths, fn segment ->
          ["#EXTINF:#{segment_duration}.0,", Path.basename(segment)]
        end) ++ ["#EXT-X-ENDLIST"]

    File.write(playlist_path, Enum.join(lines, "\n") <> "\n")
  end
end
