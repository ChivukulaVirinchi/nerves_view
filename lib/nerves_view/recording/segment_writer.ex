defmodule NervesView.Recording.SegmentWriter do
  @moduledoc """
  Subscribes to the frame StreamBus for a single camera, accumulates
  H.264 NAL units, and flushes them as MPEG-TS segments to disk.

  Segments are cut on IDR (keyframe) boundaries when the target duration
  has elapsed, producing HLS-compatible `.ts` files.
  """

  use GenServer

  import Bitwise
  require Logger

  alias NervesView.Pipeline.StreamBus
  alias NervesView.Recording.TsMuxer

  @target_duration 6
  @max_duration 10

  # H.264 NAL unit types
  @nal_sps 7
  @nal_pps 8
  @nal_idr 5
  @nal_slice_types 1..4

  # ── Public API ──

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def stop(pid), do: GenServer.stop(pid, :normal)

  # ── Callbacks ──

  @impl true
  def init(opts) do
    camera_id = Keyword.fetch!(opts, :camera_id)

    recordings_path =
      Keyword.get_lazy(opts, :recordings_path, fn ->
        Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")
      end)

    dir = Path.join(recordings_path, camera_id)
    File.mkdir_p!(dir)

    :ok = StreamBus.subscribe(camera_id)

    {:ok,
     %{
       camera_id: camera_id,
       dir: dir,
       nal_buffer: [],
       segment_start_at: nil,
       initial_pts: 0,
       current_pts: 0,
       sps: nil,
       pps: nil,
       waiting_for_keyframe: true,
       segment_count: 0
     }}
  end

  @impl true
  def handle_info({:pipeline_frame, camera_id, frame}, %{camera_id: camera_id} = state) do
    # Accept both the new shape (frame carries an :nals list — one access unit)
    # and the legacy shape (a single NAL in :payload). Iterate per NAL so the
    # existing IDR-boundary segment cut logic keeps working unchanged.
    nals =
      case Map.get(frame, :nals) do
        list when is_list(list) and list != [] -> list
        _ -> [Map.get(frame, :payload, <<>>)]
      end

    next =
      Enum.reduce(nals, state, fn nal, acc ->
        if byte_size(nal) == 0, do: acc, else: ingest_nal(nal, frame, acc)
      end)

    {:noreply, next}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    StreamBus.unsubscribe(state.camera_id)

    # Flush remaining buffer as a final segment
    if state.nal_buffer != [] and not state.waiting_for_keyframe do
      flush_segment(state)
    end

    :ok
  end

  # ── NAL ingestion ──

  defp ingest_nal(nal, frame, state) do
    type = nal_type(nal)
    pts = Map.get(frame, :timestamp, state.current_pts)

    state = %{state | current_pts: pts}

    cond do
      type == @nal_sps ->
        %{state | sps: nal}

      type == @nal_pps ->
        %{state | pps: nal}

      type == @nal_idr ->
        handle_keyframe(nal, state)

      type in @nal_slice_types and not state.waiting_for_keyframe ->
        buffer_nal(nal, state)

      true ->
        # Skip non-video NALs (SEI, AUD, etc.) or frames before first keyframe
        state
    end
  end

  defp handle_keyframe(nal, state) do
    now = System.system_time(:second)

    cond do
      # First keyframe ever — start a new segment
      state.waiting_for_keyframe ->
        start_new_segment(nal, now, state)

      # Elapsed >= target and we hit a keyframe — flush and start new
      state.segment_start_at != nil and now - state.segment_start_at >= @target_duration ->
        start_new_segment(nal, now, flush_segment(state))

      # Max duration exceeded — force flush even if not ideal
      state.segment_start_at != nil and now - state.segment_start_at >= @max_duration ->
        start_new_segment(nal, now, flush_segment(state))

      # Not time yet — just buffer
      true ->
        buffer_nal(nal, state)
    end
  end

  defp start_new_segment(nal, now, state) do
    # Prepend SPS + PPS before the IDR so the segment is self-contained
    prefix_nals =
      [state.sps, state.pps]
      |> Enum.reject(&is_nil/1)

    %{
      state
      | nal_buffer: Enum.reverse([nal | Enum.reverse(prefix_nals)]),
        segment_start_at: now,
        initial_pts: state.current_pts,
        waiting_for_keyframe: false
    }
  end

  defp buffer_nal(nal, state) do
    %{state | nal_buffer: [nal | state.nal_buffer]}
  end

  # ── Segment flush ──

  defp flush_segment(state) do
    nals = Enum.reverse(state.nal_buffer)

    if nals == [] do
      state
    else
      ts_binary =
        TsMuxer.mux_segment(nals,
          initial_pts: state.initial_pts,
          pts_increment: 6_000
        )

      started_at = state.segment_start_at || System.system_time(:second)
      filename = "seg-#{started_at}.ts"
      path = Path.join(state.dir, filename)

      case File.write(path, ts_binary) do
        :ok ->
          duration = max(System.system_time(:second) - started_at, 1)
          size = byte_size(ts_binary)

          Logger.debug(
            "SegmentWriter [#{state.camera_id}] wrote #{filename} (#{size} bytes, #{duration}s)"
          )

          notify_playlist_manager(state.camera_id, %{
            path: path,
            filename: filename,
            started_at: started_at,
            duration: duration,
            size: size
          })

        {:error, reason} ->
          Logger.warning(
            "SegmentWriter [#{state.camera_id}] failed to write #{filename}: #{inspect(reason)}"
          )
      end

      %{
        state
        | nal_buffer: [],
          segment_start_at: nil,
          segment_count: state.segment_count + 1
      }
    end
  end

  defp notify_playlist_manager(camera_id, segment_meta) do
    NervesView.Recording.PlaylistManager.add_segment(camera_id, segment_meta)

    NervesView.DVR.SegmentIndex.register(camera_id, segment_meta.started_at, segment_meta)
  catch
    :exit, _ -> :ok
  end

  # ── Helpers ──

  defp nal_type(<<header, _rest::binary>>), do: header &&& 0x1F
  defp nal_type(_), do: 0
end
