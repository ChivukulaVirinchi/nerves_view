defmodule NervesView.Pipeline.Runtime.FramePublisher do
  @moduledoc false

  use GenServer

  alias NervesView.Camera.Producer
  alias NervesView.Pipeline.StreamBus

  @tick_ms 33

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def snapshot(pid) when is_pid(pid) do
    GenServer.call(pid, :snapshot)
  end

  @impl true
  def init(opts) do
    camera_id = Keyword.fetch!(opts, :camera_id)
    source_type = Keyword.get(opts, :source_type, :synthetic)
    source_path = Keyword.get(opts, :source_path, "synthetic://pattern")

    producer_module = Producer.module_for(source_type)

    case producer_module.start_link(source_type: source_type, source_path: source_path) do
      {:ok, producer_pid} ->
        Process.send_after(self(), :tick, @tick_ms)

        {:ok,
         %{
           camera_id: camera_id,
           producer_module: producer_module,
           producer_pid: producer_pid,
           started_at: System.system_time(:second),
           last_frame_at: System.system_time(:second)
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    producer_snapshot = state.producer_module.snapshot(state.producer_pid)

    reply = %{
      healthy: producer_snapshot.healthy,
      last_frame_at: state.last_frame_at,
      last_error: producer_snapshot.last_error,
      started_at: state.started_at
    }

    {:reply, reply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    snapshot = state.producer_module.snapshot(state.producer_pid)

    frame =
      if snapshot.healthy do
        %{
          payload: snapshot.payload,
          sequence_number: snapshot.sequence,
          timestamp: snapshot.timestamp,
          inserted_at: System.system_time(:second)
        }
      else
        %{
          payload: <<0, 0, 1, 101, 0, 0, 0, 0>>,
          sequence_number: 0,
          timestamp: 0,
          inserted_at: System.system_time(:second),
          error: snapshot.last_error
        }
      end

    StreamBus.publish(state.camera_id, frame)
    Process.send_after(self(), :tick, @tick_ms)

    {:noreply, %{state | last_frame_at: System.system_time(:second)}}
  end

  @impl true
  def terminate(_reason, state) do
    state.producer_module.stop(state.producer_pid)
    :ok
  end
end
