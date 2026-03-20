defmodule NervesView.Security.RateLimiter do
  @moduledoc "Simple in-memory token bucket style limiter by key."

  use GenServer

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec check(String.t(), keyword()) :: :ok | {:error, :rate_limited}
  def check(key, opts \\ []) when is_binary(key) do
    GenServer.call(@name, {:check, key, opts})
  end

  @spec clear() :: :ok
  def clear, do: GenServer.call(@name, :clear)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:check, key, opts}, _from, state) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    window = Keyword.get(opts, :window_seconds, 60)
    max_attempts = Keyword.get(opts, :max_attempts, 8)

    attempts =
      state
      |> Map.get(key, [])
      |> Enum.filter(&(now - &1 < window))

    if length(attempts) >= max_attempts do
      {:reply, {:error, :rate_limited}, Map.put(state, key, attempts)}
    else
      {:reply, :ok, Map.put(state, key, [now | attempts])}
    end
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end
end
