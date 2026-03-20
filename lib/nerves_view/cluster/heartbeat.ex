defmodule NervesView.Cluster.Heartbeat do
  @moduledoc false

  use GenServer

  @interval_ms 5_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec beat_now() :: :ok
  def beat_now do
    GenServer.call(__MODULE__, :beat_now)
  end

  @impl true
  def init(state) do
    Process.send_after(self(), :beat, @interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:beat, state) do
    do_beat()
    Process.send_after(self(), :beat, @interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:beat_now, _from, state) do
    do_beat()
    {:reply, :ok, state}
  end

  defp do_beat do
    node_id = Atom.to_string(node())
    now = System.system_time(:second)

    _ =
      NervesView.register_node(%{
        id: node_id,
        mode: NervesView.Mode.current(),
        host: "127.0.0.1",
        port: 4000,
        last_seen_at: now
      })

    _ = NervesView.node_heartbeat(node_id, now)
    _ = NervesView.prune_stale_nodes(30, now)
  end
end
