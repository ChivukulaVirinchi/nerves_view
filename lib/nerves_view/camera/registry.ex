defmodule NervesView.Camera.Registry do
  @moduledoc "In-memory camera registry used for phase-1 foundation."

  use GenServer

  alias NervesView.Camera

  @name __MODULE__

  @type state :: %{required(String.t()) => Camera.t()}

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

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  def handle_call({:get, camera_id}, _from, state) do
    case Map.fetch(state, camera_id) do
      {:ok, camera} -> {:reply, {:ok, camera}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:upsert, attrs}, _from, state) do
    with {:ok, camera} <- Camera.new(attrs) do
      next_state = Map.put(state, camera.id, camera)
      {:reply, {:ok, camera}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove, camera_id}, _from, state) do
    {:reply, :ok, Map.delete(state, camera_id)}
  end
end
