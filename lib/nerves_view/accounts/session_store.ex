defmodule NervesView.Accounts.SessionStore do
  @moduledoc "In-memory session management for authenticated users."

  use GenServer

  alias NervesView.Persistence

  @name __MODULE__
  @ttl_seconds 86_400
  @persist_file "sessions.term"

  @type session :: %{
          required(:token) => String.t(),
          required(:user_id) => String.t(),
          required(:created_at) => non_neg_integer(),
          required(:expires_at) => non_neg_integer()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec create(String.t(), keyword()) :: {:ok, session()}
  def create(user_id, opts \\ []) when is_binary(user_id) do
    GenServer.call(@name, {:create, user_id, opts})
  end

  @spec fetch(String.t(), non_neg_integer()) :: {:ok, session()} | {:error, :not_found | :expired}
  def fetch(token, now_ts \\ now()) when is_binary(token) and is_integer(now_ts) do
    GenServer.call(@name, {:fetch, token, now_ts})
  end

  @spec revoke(String.t()) :: :ok
  def revoke(token) when is_binary(token), do: GenServer.call(@name, {:revoke, token})

  @spec prune_expired(non_neg_integer()) :: [String.t()]
  def prune_expired(now_ts \\ now()) when is_integer(now_ts) do
    GenServer.call(@name, {:prune_expired, now_ts})
  end

  @spec clear() :: :ok
  def clear, do: GenServer.call(@name, :clear)

  @impl true
  def init(_state), do: {:ok, Persistence.load(@persist_file, %{})}

  @impl true
  def handle_call({:create, user_id, opts}, _from, state) do
    ttl = if Keyword.get(opts, :remember_me, false), do: @ttl_seconds * 30, else: @ttl_seconds
    ts = Keyword.get(opts, :now, now())

    session = %{
      token: token(),
      user_id: user_id,
      created_at: ts,
      expires_at: ts + ttl
    }

    next_state = Map.put(state, session.token, session)
    :ok = Persistence.save(@persist_file, next_state)
    {:reply, {:ok, session}, next_state}
  end

  def handle_call({:fetch, token, now_ts}, _from, state) do
    case Map.fetch(state, token) do
      {:ok, session} when now_ts <= session.expires_at ->
        {:reply, {:ok, session}, state}

      {:ok, _session} ->
        next_state = Map.delete(state, token)
        :ok = Persistence.save(@persist_file, next_state)
        {:reply, {:error, :expired}, next_state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:revoke, token}, _from, state) do
    next_state = Map.delete(state, token)
    :ok = Persistence.save(@persist_file, next_state)
    {:reply, :ok, next_state}
  end

  def handle_call({:prune_expired, now_ts}, _from, state) do
    expired =
      state
      |> Enum.filter(fn {_token, session} -> session.expires_at < now_ts end)
      |> Enum.map(fn {token, _session} -> token end)

    next_state = Enum.reduce(expired, state, &Map.delete(&2, &1))
    :ok = Persistence.save(@persist_file, next_state)
    {:reply, expired, next_state}
  end

  def handle_call(:clear, _from, _state) do
    :ok = Persistence.save(@persist_file, %{})
    {:reply, :ok, %{}}
  end

  defp token do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end

  defp now, do: System.system_time(:second)
end
