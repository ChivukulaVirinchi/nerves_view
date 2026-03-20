defmodule NervesView.Pipeline.HLSWriter do
  @moduledoc """
  Synthetic HLS writer for host/testing flow.
  """

  alias NervesView.Recording.Store

  @spec write(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def write(camera_id, opts \\ []) when is_binary(camera_id) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    duration = Keyword.get(opts, :duration_seconds, 20)
    segments = Keyword.get(opts, :segments, 4)
    mode = Keyword.get(opts, :mode, :continuous)

    rec_id = "rec-#{camera_id}-#{now}"
    base = "/data/hls/#{camera_id}/#{rec_id}"

    recording = %{
      id: rec_id,
      camera_id: camera_id,
      started_at: now,
      ended_at: now + duration,
      mode: mode,
      path: "#{base}.m3u8",
      playlist_path: "#{base}.m3u8",
      segment_paths: Enum.map(1..segments, &"#{base}-#{&1}.ts"),
      size_bytes: segments * 1_024 * 512
    }

    Store.put(recording)
  end
end
