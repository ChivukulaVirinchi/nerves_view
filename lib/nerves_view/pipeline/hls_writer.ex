defmodule NervesView.Pipeline.HLSWriter do
  @moduledoc """
  File-backed HLS writer for local recording flow.
  """

  alias NervesView.Recording.Store
  alias NervesView.Pipeline.Manager

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
    frame_count = Keyword.get(opts, :frame_count, 30)

    _ =
      case Manager.status(camera_id) do
        {:ok, _status} ->
          :ok

        {:error, :not_found} ->
          Manager.start_pipeline(camera_id, frame_count: 120, interval_ms: 33)
      end

    frame_payload = collect_frame_payload(camera_id, frame_count)
    Enum.each(segment_paths, &write_segment_file(&1, camera_id, rec_id, variant, frame_payload))
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

  defp write_segment_file(path, camera_id, rec_id, variant, frame_payload) do
    content =
      "NervesView segment camera=#{camera_id} recording=#{rec_id} variant=#{variant} frame=#{frame_payload}\n"

    :ok = File.write(path, content)
  end

  defp collect_frame_payload(camera_id, count) do
    :ok = NervesView.Pipeline.StreamBus.subscribe(camera_id)

    payload =
      1..count
      |> Enum.reduce_while(nil, fn _i, _acc ->
        receive do
          {:pipeline_frame, ^camera_id, frame} ->
            value = Base.encode16(Map.get(frame, :payload, <<>>), case: :lower)
            {:halt, value}
        after
          100 -> {:cont, nil}
        end
      end)

    :ok = NervesView.Pipeline.StreamBus.unsubscribe(camera_id)
    payload || "none"
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
