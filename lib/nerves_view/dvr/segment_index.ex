defmodule NervesView.DVR.SegmentIndex do
  @moduledoc """
  In-memory index of recorded segments per camera, optimized for
  time-range queries needed by the DVR/timeline feature.

  Populated by `SegmentWriter` as segments are flushed to disk.
  Scans the recordings directory on boot to rebuild state.
  """

  use GenServer

  @name __MODULE__

  # ── Public API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  @doc "Register a new segment. Called by SegmentWriter after writing a .ts file."
  @spec register(String.t(), non_neg_integer(), map()) :: :ok
  def register(camera_id, started_at, meta)
      when is_binary(camera_id) and is_integer(started_at) and is_map(meta) do
    GenServer.cast(@name, {:register, camera_id, started_at, meta})
  end

  @doc "Remove a segment. Called by SegmentReaper during cleanup."
  @spec remove(String.t(), non_neg_integer()) :: :ok
  def remove(camera_id, started_at)
      when is_binary(camera_id) and is_integer(started_at) do
    GenServer.cast(@name, {:remove, camera_id, started_at})
  end

  @doc "Returns segments for a camera within a time range, sorted ascending."
  @spec segments_for(String.t(), non_neg_integer(), non_neg_integer()) :: [map()]
  def segments_for(camera_id, from_ts, to_ts)
      when is_binary(camera_id) and is_integer(from_ts) and is_integer(to_ts) do
    GenServer.call(@name, {:segments_for, camera_id, from_ts, to_ts})
  end

  @doc "Returns all segments for a camera, sorted ascending by started_at."
  @spec all_segments(String.t()) :: [map()]
  def all_segments(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:all_segments, camera_id})
  end

  @doc "Returns `{oldest_ts, newest_end_ts}` or nil if no segments."
  @spec retention_window(String.t()) :: {non_neg_integer(), non_neg_integer()} | nil
  def retention_window(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:retention_window, camera_id})
  end

  @doc "Clears all state. Used in tests."
  @spec clear() :: :ok
  def clear, do: GenServer.call(@name, :clear)

  # ── Callbacks ──

  @impl true
  def init(:ok) do
    state = scan_recordings_dir()
    {:ok, state}
  end

  @impl true
  def handle_cast({:register, camera_id, started_at, meta}, state) do
    segment = %{
      started_at: started_at,
      duration: Map.get(meta, :duration, 6),
      filename: Map.get(meta, :filename, "seg-#{started_at}.ts"),
      path: Map.get(meta, :path),
      size: Map.get(meta, :size, 0)
    }

    camera_segs = Map.get(state, camera_id, [])
    updated = insert_sorted(camera_segs, segment)
    {:noreply, Map.put(state, camera_id, updated)}
  end

  def handle_cast({:remove, camera_id, started_at}, state) do
    camera_segs = Map.get(state, camera_id, [])
    updated = Enum.reject(camera_segs, &(&1.started_at == started_at))
    {:noreply, Map.put(state, camera_id, updated)}
  end

  @impl true
  def handle_call({:segments_for, camera_id, from_ts, to_ts}, _from, state) do
    segs =
      state
      |> Map.get(camera_id, [])
      |> Enum.filter(fn s ->
        seg_end = s.started_at + s.duration
        s.started_at < to_ts and seg_end > from_ts
      end)

    {:reply, segs, state}
  end

  def handle_call({:all_segments, camera_id}, _from, state) do
    {:reply, Map.get(state, camera_id, []), state}
  end

  def handle_call({:retention_window, camera_id}, _from, state) do
    result =
      case Map.get(state, camera_id, []) do
        [] ->
          nil

        segs ->
          oldest = hd(segs).started_at
          newest = List.last(segs)
          {oldest, newest.started_at + newest.duration}
      end

    {:reply, result, state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  # ── Helpers ──

  defp insert_sorted([], segment), do: [segment]

  defp insert_sorted(list, segment) do
    # Insert maintaining ascending order by started_at.
    # Segments arrive roughly in order so appending is the common case.
    if List.last(list).started_at <= segment.started_at do
      list ++ [segment]
    else
      idx = Enum.find_index(list, &(&1.started_at > segment.started_at)) || length(list)
      List.insert_at(list, idx, segment)
    end
  end

  defp scan_recordings_dir do
    recordings_path = Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")

    case File.ls(recordings_path) do
      {:ok, dirs} ->
        Map.new(dirs, fn camera_id ->
          dir = Path.join(recordings_path, camera_id)
          segs = scan_camera_dir(dir, camera_id)
          {camera_id, segs}
        end)

      {:error, _} ->
        %{}
    end
  end

  defp scan_camera_dir(dir, _camera_id) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.match?(&1, ~r/^seg-\d+\.ts$/))
        |> Enum.map(fn filename ->
          [_, ts_str] = Regex.run(~r/^seg-(\d+)\.ts$/, filename)
          started_at = String.to_integer(ts_str)
          path = Path.join(dir, filename)
          size = case File.stat(path) do
            {:ok, %{size: s}} -> s
            _ -> 0
          end

          %{
            started_at: started_at,
            duration: Application.get_env(:nerves_view, :recording_segment_duration, 6),
            filename: filename,
            path: path,
            size: size
          }
        end)
        |> Enum.sort_by(& &1.started_at)

      {:error, _} ->
        []
    end
  rescue
    _ -> []
  end
end
