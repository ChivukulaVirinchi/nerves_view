defmodule NervesView.Pipeline.StreamBus do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def subscribe(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:subscribe, camera_id, self()})
  end

  def unsubscribe(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:unsubscribe, camera_id, self()})
  end

  def publish(camera_id, frame) when is_binary(camera_id) and is_map(frame) do
    GenServer.cast(@name, {:publish, camera_id, frame})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:subscribe, camera_id, pid}, _from, state) do
    Process.monitor(pid)
    subscribers = Map.update(state, camera_id, MapSet.new([pid]), &MapSet.put(&1, pid))
    {:reply, :ok, subscribers}
  end

  def handle_call({:unsubscribe, camera_id, pid}, _from, state) do
    subscribers =
      Map.update(state, camera_id, MapSet.new(), fn set ->
        set
        |> MapSet.delete(pid)
      end)

    {:reply, :ok, subscribers}
  end

  @impl true
  def handle_cast({:publish, camera_id, frame}, state) do
    Enum.each(Map.get(state, camera_id, MapSet.new()), fn pid ->
      send(pid, {:pipeline_frame, camera_id, frame})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    next =
      state
      |> Enum.map(fn {camera_id, set} -> {camera_id, MapSet.delete(set, pid)} end)
      |> Map.new()

    {:noreply, next}
  end
end
