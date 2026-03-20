defmodule NervesView.Storage.Manager do
  @moduledoc """
  Tracks recording storage usage and retention limits.
  """

  use GenServer

  alias NervesView.Recording.Store

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec usage() :: %{recording_count: non_neg_integer(), total_bytes: non_neg_integer()}
  def usage do
    GenServer.call(@name, :usage)
  end

  @spec enforce_retention(keyword()) :: %{trimmed: non_neg_integer(), max_count: pos_integer()}
  def enforce_retention(opts \\ []) do
    GenServer.call(@name, {:enforce_retention, opts})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:usage, _from, state) do
    recordings = Store.list()

    total_bytes =
      Enum.reduce(recordings, 0, fn rec, acc ->
        acc + Map.get(rec, :size_bytes, 0)
      end)

    {:reply, %{recording_count: length(recordings), total_bytes: total_bytes}, state}
  end

  def handle_call({:enforce_retention, opts}, _from, state) do
    max_count = Keyword.get(opts, :max_count, 200)
    trimmed = Store.trim_by_count(max_count)
    {:reply, %{trimmed: trimmed, max_count: max_count}, state}
  end
end
