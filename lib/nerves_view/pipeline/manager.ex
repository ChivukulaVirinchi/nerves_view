defmodule NervesView.Pipeline.Manager do
  @moduledoc """
  Starts/stops camera pipelines and exposes runtime health.
  """

  use GenServer

  alias NervesView.Pipeline.Camera, as: CameraPipeline

  @runtime_module if Mix.target() == :host,
                    do: NervesView.Pipeline.Runtime.Host,
                    else: NervesView.Pipeline.Runtime.Target

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

  @spec restart_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def restart_pipeline(camera_id, opts \\ []) when is_binary(camera_id) do
    GenServer.call(@name, {:restart_pipeline, camera_id, opts})
  end

  @spec status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def status(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:status, camera_id})
  end

  @spec health(String.t()) :: {:ok, map()} | {:error, :not_found}
  def health(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:health, camera_id})
  end

  @spec list() :: [map()]
  def list do
    GenServer.call(@name, :list)
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @spec start_camera_pipeline(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_camera_pipeline(camera, opts \\ []) when is_map(camera) do
    GenServer.call(@name, {:start_camera_pipeline, camera, opts})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:start_pipeline, camera_id, opts}, _from, state) do
    case Map.fetch(state, camera_id) do
      {:ok, pipeline} ->
        {:reply, {:ok, pipeline}, state}

      :error ->
        descriptor = %{
          camera_id: camera_id,
          camera_name: camera_id,
          source_type: :test,
          source: %{device_path: "test://pattern", backend: :test},
          outputs: %{webrtc: true, motion_detector: true},
          stream: %{resolution: {1280, 720}, fps: 30},
          inserted_at: System.system_time(:second)
        }

        do_start_runtime(descriptor, opts, state)
    end
  end

  def handle_call({:start_camera_pipeline, camera, opts}, _from, state) do
    camera_id = camera[:id] || camera["id"]

    if is_binary(camera_id) and Map.has_key?(state, camera_id) do
      {:reply, {:ok, Map.fetch!(state, camera_id)}, state}
    else
      case CameraPipeline.build(camera, opts) do
        {:ok, descriptor} ->
          descriptor = Map.put(descriptor, :inserted_at, System.system_time(:second))
          do_start_runtime(descriptor, opts, state)

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:stop_pipeline, camera_id}, _from, state) do
    next_state =
      case Map.pop(state, camera_id) do
        {nil, state_after_pop} ->
          state_after_pop

        {pipeline, state_after_pop} ->
          :ok = @runtime_module.stop_pipeline(pipeline)
          state_after_pop
      end

    {:reply, :ok, next_state}
  end

  def handle_call({:restart_pipeline, camera_id, opts}, _from, state) do
    state_after_stop =
      case Map.pop(state, camera_id) do
        {nil, s} ->
          s

        {pipeline, s} ->
          :ok = @runtime_module.stop_pipeline(pipeline)
          s
      end

    camera =
      case NervesView.Camera.Registry.get(camera_id) do
        {:ok, cam} -> Map.from_struct(cam)
        _ -> nil
      end

    if camera do
      case CameraPipeline.build(camera, opts) do
        {:ok, descriptor} ->
          descriptor = Map.put(descriptor, :inserted_at, System.system_time(:second))
          do_start_runtime(descriptor, opts, state_after_stop)

        {:error, reason} ->
          {:reply, {:error, reason}, state_after_stop}
      end
    else
      {:reply, {:error, :camera_not_found}, state_after_stop}
    end
  end

  def handle_call({:status, camera_id}, _from, state) do
    case Map.fetch(state, camera_id) do
      {:ok, pipeline} -> {:reply, {:ok, pipeline}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:health, camera_id}, _from, state) do
    case Map.fetch(state, camera_id) do
      {:ok, pipeline} ->
        {:reply, {:ok, @runtime_module.health(pipeline)}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(state, fn {_camera_id, pipeline} ->
      :ok = @runtime_module.stop_pipeline(pipeline)
    end)

    {:reply, :ok, %{}}
  end

  defp do_start_runtime(descriptor, opts, state) do
    case @runtime_module.start_pipeline(descriptor, opts) do
      {:ok, pipeline} ->
        {:reply, {:ok, pipeline}, Map.put(state, descriptor.camera_id, pipeline)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
