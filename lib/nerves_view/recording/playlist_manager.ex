defmodule NervesView.Recording.PlaylistManager do
  @moduledoc """
  Maintains rolling HLS playlists (`live.m3u8`) for each camera's
  continuous recording. Segments are added by SegmentWriter and
  removed by SegmentReaper.
  """

  use GenServer

  @name __MODULE__
  @target_duration 7

  # ── Public API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @doc "Register a new segment for a camera."
  @spec add_segment(String.t(), map()) :: :ok
  def add_segment(camera_id, segment_meta) when is_binary(camera_id) and is_map(segment_meta) do
    GenServer.cast(@name, {:add_segment, camera_id, segment_meta})
  end

  @doc "Remove a segment (called during retention cleanup)."
  @spec remove_segment(String.t(), non_neg_integer()) :: :ok
  def remove_segment(camera_id, started_at)
      when is_binary(camera_id) and is_integer(started_at) do
    GenServer.cast(@name, {:remove_segment, camera_id, started_at})
  end

  @doc "Returns the list of segments for a camera (oldest first)."
  @spec segments(String.t()) :: [map()]
  def segments(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:segments, camera_id})
  end

  @doc "Returns `{oldest_ts, newest_ts}` for a camera, or nil if no segments."
  @spec retention_window(String.t()) :: {non_neg_integer(), non_neg_integer()} | nil
  def retention_window(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:retention_window, camera_id})
  end

  @doc "Clears all state. Used in tests."
  @spec clear() :: :ok
  def clear, do: GenServer.call(@name, :clear)

  # ── Callbacks ──

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:add_segment, camera_id, meta}, state) do
    camera_state = Map.get(state, camera_id, new_camera_state())

    segment = %{
      started_at: meta.started_at,
      duration: meta.duration,
      filename: meta.filename,
      path: meta.path,
      size: meta.size
    }

    all_segments = camera_state.segments ++ [segment]

    updated = %{camera_state | segments: all_segments}
    state = Map.put(state, camera_id, updated)
    write_playlist(camera_id, updated)
    {:noreply, state}
  end

  def handle_cast({:remove_segment, camera_id, started_at}, state) do
    case Map.get(state, camera_id) do
      nil ->
        {:noreply, state}

      camera_state ->
        updated_segments =
          Enum.reject(camera_state.segments, &(&1.started_at == started_at))

        updated = %{
          camera_state
          | segments: updated_segments,
            media_sequence: camera_state.media_sequence + 1
        }

        state = Map.put(state, camera_id, updated)
        write_playlist(camera_id, updated)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:segments, camera_id}, _from, state) do
    segs =
      case Map.get(state, camera_id) do
        nil -> []
        cs -> cs.segments
      end

    {:reply, segs, state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  def handle_call({:retention_window, camera_id}, _from, state) do
    result =
      case Map.get(state, camera_id) do
        nil ->
          nil

        %{segments: []} ->
          nil

        %{segments: segs} ->
          oldest = List.first(segs).started_at
          newest = List.last(segs)
          {oldest, newest.started_at + newest.duration}
      end

    {:reply, result, state}
  end

  # ── Playlist generation ──

  defp write_playlist(camera_id, camera_state) do
    content = build_playlist(camera_state)
    recordings_path = Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")
    dir = Path.join(recordings_path, camera_id)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "live.m3u8"), content)
  end

  # Number of segments to keep in the live playlist (rolling window).
  # Fewer segments = lower latency for live viewers.
  @live_window_size 3

  defp build_playlist(camera_state) do
    # Only include the last N segments for a live-edge playlist.
    # This keeps the playlist small and makes players start near live.
    total = length(camera_state.segments)
    recent = Enum.take(camera_state.segments, -@live_window_size)

    # media_sequence = number of segments that have "scrolled off" the playlist.
    # hls.js uses this to detect new segments on each playlist refresh.
    media_seq = max(0, total - @live_window_size)

    max_dur =
      recent
      |> Enum.map(& &1.duration)
      |> Enum.max(fn -> @target_duration end)
      |> max(@target_duration)

    header = """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-TARGETDURATION:#{max_dur}
    #EXT-X-MEDIA-SEQUENCE:#{media_seq}
    """

    entries =
      Enum.map_join(recent, fn seg ->
        "#EXTINF:#{seg.duration},\n#{seg.filename}\n"
      end)

    String.trim(header) <> "\n" <> entries
  end

  defp new_camera_state do
    %{segments: [], media_sequence: 0}
  end
end
