defmodule NervesView.Pipeline.Manager do
  @moduledoc """
  Starts/stops host test pipelines per camera and exposes status.
  """

  use GenServer

  alias NervesView.Pipeline.TestSource

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec start_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_pipeline(camera_id, opts \\ []) when is_binary(camera_id) do
    GenServer.call(@name, {:start_pipeline, camera_id, opts})
  end

  @spec stop_pipeline(String.t()) :: :ok
  def stop_pipeline(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:stop_pipeline, camera_id})
  end

  @spec status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def status(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:status, camera_id})
  end

  @spec list() :: [map()]
  def list do
    GenServer.call(@name, :list)
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:start_pipeline, camera_id, opts}, _from, state) do
    case Map.fetch(state, camera_id) do
      {:ok, pipeline} ->
        {:reply, {:ok, pipeline}, state}

      :error ->
        frame_count = Keyword.get(opts, :frame_count, 30)
        interval_ms = Keyword.get(opts, :interval_ms, 33)

        {:ok, pid} = TestSource.start_link(frame_count: frame_count, interval_ms: interval_ms)

        pipeline = %{
          camera_id: camera_id,
          source: :test,
          status: :running,
          source_pid: pid,
          inserted_at: System.system_time(:second)
        }

        {:reply, {:ok, pipeline}, Map.put(state, camera_id, pipeline)}
    end
  end

  def handle_call({:stop_pipeline, camera_id}, _from, state) do
    next_state =
      case Map.pop(state, camera_id) do
        {nil, state_after_pop} ->
          state_after_pop

        {%{source_pid: pid}, state_after_pop} ->
          if Process.alive?(pid), do: Process.exit(pid, :normal)
          state_after_pop
      end

    {:reply, :ok, next_state}
  end

  def handle_call({:status, camera_id}, _from, state) do
    case Map.fetch(state, camera_id) do
      {:ok, pipeline} -> {:reply, {:ok, pipeline}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(state, fn {_camera_id, %{source_pid: pid}} ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    {:reply, :ok, %{}}
  end
end
