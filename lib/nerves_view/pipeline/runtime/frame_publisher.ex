defmodule NervesView.Pipeline.Runtime.FramePublisher do
  @moduledoc false

  use GenServer

  alias NervesView.Pipeline.StreamBus

  @tick_ms 33

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    camera_id = Keyword.fetch!(opts, :camera_id)
    Process.send_after(self(), :tick, @tick_ms)

    {:ok,
     %{
       camera_id: camera_id,
       sequence: 0,
       timestamp: 0,
       started_at: System.system_time(:second),
       last_frame_at: System.system_time(:second)
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    frame = %{
      payload: <<0, 0, 1, 101, 0, 0, 0, 1>>,
      sequence_number: state.sequence,
      timestamp: state.timestamp,
      inserted_at: System.system_time(:second)
    }

    StreamBus.publish(state.camera_id, frame)
    Process.send_after(self(), :tick, @tick_ms)

    {:noreply,
     %{
       state
       | sequence: rem(state.sequence + 1, 65_535),
         timestamp: rem(state.timestamp + 3_000, 4_294_967_295),
         last_frame_at: System.system_time(:second)
     }}
  end
end
