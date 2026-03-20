defmodule NervesView.Cluster.NodeRegistry do
  @moduledoc "In-memory hub/node registry for phase-4 multi-node support."

  use GenServer

  @name __MODULE__

  @valid_modes [:hub, :node]

  @type node_record :: %{
          required(:id) => String.t(),
          required(:mode) => :hub | :node,
          required(:host) => String.t(),
          required(:port) => non_neg_integer(),
          required(:last_seen_at) => non_neg_integer(),
          optional(:meta) => map()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec register(node_record()) :: {:ok, node_record()} | {:error, atom()}
  def register(attrs) when is_map(attrs) do
    GenServer.call(@name, {:register, attrs})
  end

  @spec heartbeat(String.t(), non_neg_integer()) :: :ok | {:error, :not_found}
  def heartbeat(node_id, timestamp \\ now()) when is_binary(node_id) and is_integer(timestamp) do
    GenServer.call(@name, {:heartbeat, node_id, timestamp})
  end

  @spec list(keyword()) :: [node_record()]
  def list(opts \\ []) do
    GenServer.call(@name, {:list, opts})
  end

  @spec get(String.t()) :: {:ok, node_record()} | {:error, :not_found}
  def get(node_id) when is_binary(node_id) do
    GenServer.call(@name, {:get, node_id})
  end

  @spec remove(String.t()) :: :ok
  def remove(node_id) when is_binary(node_id) do
    GenServer.call(@name, {:remove, node_id})
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
  def handle_call({:register, attrs}, _from, state) do
    with :ok <- validate(attrs) do
      record = Map.put(attrs, :last_seen_at, attrs[:last_seen_at] || now())
      {:reply, {:ok, record}, Map.put(state, record.id, record)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:heartbeat, node_id, timestamp}, _from, state) do
    case Map.fetch(state, node_id) do
      {:ok, record} ->
        next = Map.put(record, :last_seen_at, timestamp)
        {:reply, :ok, Map.put(state, node_id, next)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    mode = Keyword.get(opts, :mode)

    records =
      state
      |> Map.values()
      |> maybe_filter_mode(mode)
      |> Enum.sort_by(& &1.id)

    {:reply, records, state}
  end

  def handle_call({:get, node_id}, _from, state) do
    case Map.fetch(state, node_id) do
      {:ok, record} -> {:reply, {:ok, record}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:remove, node_id}, _from, state) do
    {:reply, :ok, Map.delete(state, node_id)}
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

  defp maybe_filter_mode(records, nil), do: records
  defp maybe_filter_mode(records, mode), do: Enum.filter(records, &(&1.mode == mode))

  defp validate(attrs) do
    required = [:id, :mode, :host, :port]

    cond do
      not Enum.all?(required, &Map.has_key?(attrs, &1)) ->
        {:error, :missing_required_fields}

      attrs.mode not in @valid_modes ->
        {:error, :invalid_mode}

      not is_binary(attrs.id) or not is_binary(attrs.host) ->
        {:error, :invalid_identity}

      not is_integer(attrs.port) or attrs.port <= 0 ->
        {:error, :invalid_port}

      true ->
        :ok
    end
  end

  defp now, do: System.system_time(:second)
end
