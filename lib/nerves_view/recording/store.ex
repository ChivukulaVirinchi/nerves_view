defmodule NervesView.Recording.Store do
  @moduledoc "In-memory recording store with retention controls for phase-3."

  use GenServer

  @name __MODULE__

  @type recording :: %{
          required(:id) => String.t(),
          required(:camera_id) => String.t(),
          required(:started_at) => non_neg_integer(),
          required(:ended_at) => non_neg_integer(),
          required(:mode) => :continuous | :motion,
          required(:path) => String.t(),
          optional(:playlist_path) => String.t(),
          optional(:segment_paths) => [String.t()],
          optional(:size_bytes) => non_neg_integer(),
          optional(:motion_score) => float()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{recordings: %{}, camera_index: %{}}, name: @name)
  end

  @spec put(recording()) :: {:ok, recording()} | {:error, atom()}
  def put(recording) when is_map(recording), do: GenServer.call(@name, {:put, recording})

  @spec list(keyword()) :: [recording()]
  def list(opts \\ []), do: GenServer.call(@name, {:list, opts})

  @spec trim_by_count(pos_integer()) :: non_neg_integer()
  def trim_by_count(max_count) when is_integer(max_count) and max_count > 0 do
    GenServer.call(@name, {:trim_by_count, max_count})
  end

  @spec clear() :: :ok
  def clear, do: GenServer.call(@name, :clear)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:put, recording}, _from, state) do
    with :ok <- validate(recording) do
      recordings = Map.put(state.recordings, recording.id, recording)

      camera_index =
        Map.update(state.camera_index, recording.camera_id, [recording.id], &[recording.id | &1])

      Phoenix.PubSub.broadcast(NervesView.PubSub, "recordings", {:recording_stored, recording})
      {:reply, {:ok, recording}, %{state | recordings: recordings, camera_index: camera_index}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    camera_id = Keyword.get(opts, :camera_id)

    records =
      case camera_id do
        nil ->
          Map.values(state.recordings)

        id ->
          state.camera_index
          |> Map.get(id, [])
          |> Enum.map(&Map.fetch!(state.recordings, &1))
      end

    sorted = Enum.sort_by(records, & &1.started_at, :desc)
    {:reply, sorted, state}
  end

  def handle_call({:trim_by_count, max_count}, _from, state) do
    sorted = Enum.sort_by(Map.values(state.recordings), & &1.started_at, :desc)
    {keep, drop} = Enum.split(sorted, max_count)

    kept_ids = MapSet.new(Enum.map(keep, & &1.id))

    next_recordings =
      state.recordings
      |> Enum.filter(fn {id, _rec} -> MapSet.member?(kept_ids, id) end)
      |> Map.new()

    next_index = rebuild_index(next_recordings)

    {:reply, length(drop), %{state | recordings: next_recordings, camera_index: next_index}}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{recordings: %{}, camera_index: %{}}}
  end

  defp validate(recording) do
    required = [:id, :camera_id, :started_at, :ended_at, :mode, :path]

    if Enum.all?(required, &Map.has_key?(recording, &1)) and
         recording.mode in [:continuous, :motion] do
      :ok
    else
      {:error, :invalid_recording}
    end
  end

  defp rebuild_index(recordings) do
    Enum.reduce(recordings, %{}, fn {_id, rec}, acc ->
      Map.update(acc, rec.camera_id, [rec.id], &[rec.id | &1])
    end)
  end
end
