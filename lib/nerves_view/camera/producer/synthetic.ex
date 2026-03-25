defmodule NervesView.Camera.Producer.Synthetic do
  @moduledoc false

  use GenServer

  @behaviour NervesView.Camera.Producer
  @tick_ms 33

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(opts) do
    source_type = Keyword.get(opts, :source_type, :synthetic)
    source_path = Keyword.get(opts, :source_path, "synthetic://pattern")
    now = System.system_time(:second)
    Process.send_after(self(), :tick, @tick_ms)

    {:ok,
     %{
       source_type: source_type,
       source_path: source_path,
       started_at: now,
       last_frame_at: now,
       healthy: true,
       last_error: nil,
       sequence: 0,
       timestamp: 0,
       payload: <<0, 0, 1, 101, 0, 0, 0, 1>>
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.system_time(:second)
    Process.send_after(self(), :tick, @tick_ms)

    {:noreply,
     %{
       state
       | last_frame_at: now,
         sequence: rem(state.sequence + 1, 65_535),
         timestamp: rem(state.timestamp + 3_000, 4_294_967_295)
     }}
  end
end
