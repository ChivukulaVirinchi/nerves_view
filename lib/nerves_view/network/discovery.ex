defmodule NervesView.Network.Discovery do
  @moduledoc "Simple service discovery cache for phase-4 LAN camera discovery."

  use GenServer

  @name __MODULE__

  @type service :: %{
          required(:service_id) => String.t(),
          required(:node_id) => String.t(),
          required(:camera_id) => String.t(),
          required(:host) => String.t(),
          required(:port) => non_neg_integer(),
          required(:last_seen_at) => non_neg_integer()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec announce(service()) :: {:ok, service()} | {:error, atom()}
  def announce(attrs) when is_map(attrs) do
    GenServer.call(@name, {:announce, attrs})
  end

  @spec list() :: [service()]
  def list do
    GenServer.call(@name, :list)
  end

  @spec prune_stale(non_neg_integer(), non_neg_integer()) :: [String.t()]
  def prune_stale(max_age_seconds, now_ts \\ now())
      when is_integer(max_age_seconds) and max_age_seconds > 0 and is_integer(now_ts) do
    GenServer.call(@name, {:prune_stale, max_age_seconds, now_ts})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:announce, attrs}, _from, state) do
    with :ok <- validate(attrs) do
      record = Map.put(attrs, :last_seen_at, attrs[:last_seen_at] || now())
      {:reply, {:ok, record}, Map.put(state, record.service_id, record)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list, _from, state) do
    services = state |> Map.values() |> Enum.sort_by(& &1.service_id)
    {:reply, services, state}
  end

  def handle_call({:prune_stale, max_age_seconds, now_ts}, _from, state) do
    stale_ids =
      state
      |> Enum.filter(fn {_id, rec} -> now_ts - rec.last_seen_at > max_age_seconds end)
      |> Enum.map(fn {id, _rec} -> id end)

    next_state = Enum.reduce(stale_ids, state, &Map.delete(&2, &1))
    {:reply, stale_ids, next_state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  defp validate(attrs) do
    required = [:service_id, :node_id, :camera_id, :host, :port]

    cond do
      not Enum.all?(required, &Map.has_key?(attrs, &1)) ->
        {:error, :missing_required_fields}

      not is_binary(attrs.service_id) or not is_binary(attrs.node_id) or
        not is_binary(attrs.camera_id) or not is_binary(attrs.host) ->
        {:error, :invalid_identity}

      not is_integer(attrs.port) or attrs.port <= 0 ->
        {:error, :invalid_port}

      true ->
        :ok
    end
  end

  defp now, do: System.system_time(:second)
end
