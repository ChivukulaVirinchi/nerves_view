defmodule NervesView.Camera.Registry do
  @moduledoc "In-memory camera registry with per-camera color config."

  use GenServer

  alias NervesView.Camera
  alias NervesView.Camera.Config, as: ColorConfig
  alias NervesView.Persistence

  @name __MODULE__
  @persist_file "cameras.term"
  @config_file "camera_configs.term"

  @type state :: %{
          cameras: %{required(String.t()) => Camera.t()},
          configs: %{required(String.t()) => ColorConfig.t()}
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec list() :: [Camera.t()]
  def list do
    GenServer.call(@name, :list)
  end

  @spec get(String.t()) :: {:ok, Camera.t()} | {:error, :not_found}
  def get(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:get, camera_id})
  end

  @spec upsert(map()) :: {:ok, Camera.t()} | {:error, term()}
  def upsert(attrs) when is_map(attrs) do
    GenServer.call(@name, {:upsert, attrs})
  end

  @spec remove(String.t()) :: :ok
  def remove(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:remove, camera_id})
  end

  @spec list_ids() :: [String.t()]
  def list_ids do
    list()
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  @spec get_config(String.t()) :: {:ok, ColorConfig.t()} | {:error, :not_found}
  def get_config(camera_id) when is_binary(camera_id) do
    GenServer.call(@name, {:get_config, camera_id})
  end

  @spec put_config(String.t(), map()) :: :ok
  def put_config(camera_id, attrs) when is_binary(camera_id) and is_map(attrs) do
    GenServer.call(@name, {:put_config, camera_id, attrs})
  end

  @impl true
  def init(_state) do
    cameras = Persistence.load(@persist_file, %{})
    configs = Persistence.load(@config_file, %{})
    {:ok, %{cameras: cameras, configs: configs}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.cameras), state}
  end

  def handle_call({:get, camera_id}, _from, state) do
    case Map.fetch(state.cameras, camera_id) do
      {:ok, camera} -> {:reply, {:ok, camera}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:upsert, attrs}, _from, state) do
    with {:ok, camera} <- Camera.new(attrs) do
      next_cameras = Map.put(state.cameras, camera.id, camera)
      :ok = Persistence.save(@persist_file, next_cameras)

      config_attrs = Map.get(attrs, :config) || Map.get(attrs, "config")
      {next_configs, :ok} = maybe_save_config(state.configs, camera.id, config_attrs)

      {:reply, {:ok, camera}, %{state | cameras: next_cameras, configs: next_configs}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove, camera_id}, _from, state) do
    next_cameras = Map.delete(state.cameras, camera_id)
    next_configs = Map.delete(state.configs, camera_id)
    :ok = Persistence.save(@persist_file, next_cameras)
    :ok = Persistence.save(@config_file, next_configs)
    {:reply, :ok, %{state | cameras: next_cameras, configs: next_configs}}
  end

  def handle_call({:get_config, camera_id}, _from, state) do
    case Map.fetch(state.configs, camera_id) do
      {:ok, config} -> {:reply, {:ok, config}, state}
      :error -> {:reply, {:ok, %ColorConfig{}}, state}
    end
  end

  def handle_call({:put_config, camera_id, attrs}, _from, state) do
    with {:ok, config} <- ColorConfig.new(attrs) do
      next_configs = Map.put(state.configs, camera_id, config)
      :ok = Persistence.save(@config_file, next_configs)
      {:reply, :ok, %{state | configs: next_configs}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp maybe_save_config(configs, _camera_id, nil), do: {configs, :ok}

  defp maybe_save_config(configs, camera_id, attrs) when is_map(attrs) do
    {:ok, config} = ColorConfig.new(attrs)
    next_configs = Map.put(configs, camera_id, config)
    :ok = Persistence.save(@config_file, next_configs)
    {next_configs, :ok}
  end
end
