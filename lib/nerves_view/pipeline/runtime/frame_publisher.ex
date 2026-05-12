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
    now = System.system_time(:second)

    if snapshot.healthy do
      # Publish one StreamBus message per H.264 access unit. The :nals list
      # carries the NALs of the AU in decode order (e.g. SPS, PPS, IDR for a
      # keyframe AU; a single VCL NAL for an inter frame). All NALs of one AU
      # share the same sequence_number and 90 kHz RTP timestamp so the
      # PeerConnection can build correct STAP-A + FU-A packets, and so the
      # SegmentWriter can keep its per-NAL IDR-boundary cut logic by iterating
      # the list. The :payload field is kept for back-compat.
      aus = Map.get(snapshot, :au_queue, [])

      Enum.each(aus, fn {nals, seq, ts} ->
        StreamBus.publish(state.camera_id, %{
          payload: hd(nals),
          nals: nals,
          sequence_number: seq,
          timestamp: ts,
          inserted_at: now
        })
      end)
    else
      payload = <<0, 0, 1, 101, 0, 0, 0, 0>>

      StreamBus.publish(state.camera_id, %{
        payload: payload,
        nals: [payload],
        sequence_number: 0,
        timestamp: 0,
        inserted_at: now,
        error: snapshot.last_error
      })
    end

    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, %{state | last_frame_at: now}}
  end

  @impl true
  def terminate(_reason, state) do
    state.producer_module.stop(state.producer_pid)
    :ok
  end
end
