defmodule NervesView.Camera.Producer.Libcamera do
  @moduledoc """
  Captures H.264 frames from libcamera-vid via Port.

  Accumulates the raw bytestream and splits on NAL unit start codes
  (0x00000001 or 0x000001) to extract individual access units.
  """

  use GenServer

  import Bitwise
  require Logger

  @behaviour NervesView.Camera.Producer
  @tick_ms 33

  # H.264 NAL start code patterns
  @start_code_4 <<0, 0, 0, 1>>
  @start_code_3 <<0, 0, 1>>

  # H.264 NAL unit types
  @nal_vcl_types 1..5

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(opts) do
    source_path = Keyword.get(opts, :source_path, "/dev/video0")
    width = Keyword.get(opts, :width, 640)
    height = Keyword.get(opts, :height, 480)
    fps = Keyword.get(opts, :fps, 15)
    color_config = Keyword.get(opts, :color_config, %NervesView.Camera.Config{})

    kill_orphaned_libcamera_vid()

    with {:ok, exec} <- find_libcamera_vid(),
         {:ok, port} <- open_port(exec, width, height, fps, color_config) do
      now = System.system_time(:second)
      Process.send_after(self(), :tick, @tick_ms)

      {:ok,
       %{
         source_type: :libcamera,
         source_path: source_path,
         started_at: now,
         last_frame_at: now,
         healthy: true,
         last_error: nil,
         sequence: 0,
         timestamp: 0,
         payload: <<>>,
         au_queue: :queue.new(),
         pending_nals: [],
         buffer: <<>>,
         port: port,
         exec: exec,
         color_config: color_config,
         width: width,
         height: height,
         fps: fps
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    # Drain the access-unit queue. Each AU is `{nals, seq, ts}`. Callers that
    # only need the latest payload use :payload (backward compat).
    queued = :queue.to_list(state.au_queue)
    snapshot = state |> Map.put(:au_queue, queued)
    {:reply, snapshot, %{state | au_queue: :queue.new()}}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)

    next =
      if File.exists?(state.source_path) do
        %{state | healthy: true, last_error: nil}
      else
        %{state | healthy: false, last_error: :device_not_found}
      end

    {:noreply, next}
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    buffer = state.buffer <> data

    case extract_nal_units(buffer) do
      {[], rest} ->
        capped =
          if byte_size(rest) > 262_144 do
            Logger.warning(
              "libcamera buffer overflow on #{state.source_path}: dropping #{byte_size(rest)} bytes"
            )

            <<>>
          else
            rest
          end

        {:noreply, %{state | buffer: capped, healthy: true, last_error: nil}}

      {nal_units, rest} ->
        {pending, au_queue, seq, ts} =
          group_into_aus(
            nal_units,
            state.pending_nals,
            state.au_queue,
            state.sequence,
            state.timestamp
          )

        latest_nal = List.last(nal_units)

        {:noreply,
         %{
           state
           | payload: latest_nal,
             pending_nals: pending,
             au_queue: au_queue,
             buffer: rest,
             sequence: seq,
             timestamp: ts,
             last_frame_at: System.system_time(:second),
             healthy: true,
             last_error: nil
         }}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("libcamera-vid exited with status #{status}, restarting in 1s...")
    Process.send_after(self(), :restart_port, 1_000)
    {:noreply, %{state | port: nil, healthy: false, last_error: {:libcamera_exit, status}}}
  end

  def handle_info(:restart_port, state) do
    w = Map.get(state, :width, 640)
    h = Map.get(state, :height, 480)
    fps = Map.get(state, :fps, 15)
    color_config = Map.get(state, :color_config, %NervesView.Camera.Config{})

    case open_port(state.exec, w, h, fps, color_config) do
      {:ok, new_port} ->
        Logger.info("libcamera-vid restarted successfully")
        {:noreply, %{state | port: new_port, buffer: <<>>, healthy: true, last_error: nil}}

      {:error, reason} ->
        Logger.error("libcamera-vid restart failed: #{inspect(reason)}")
        {:noreply, %{state | healthy: false, last_error: reason}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if is_port(state[:port]) and Port.info(state.port) != nil do
      Port.close(state.port)
    end

    :ok
  end

  # Walk NALs in order, grouping into access units. Non-VCL NALs (types 6/7/8/9
  # — SEI/SPS/PPS/AUD) accumulate as pending parameter sets, then the next VCL
  # NAL (types 1..5 — slice or IDR) closes the AU. Each closed AU advances the
  # shared sequence_number and 90 kHz timestamp.
  defp group_into_aus(nals, pending, queue, seq, ts) do
    Enum.reduce(nals, {pending, queue, seq, ts}, fn nal, {pending, queue, seq, ts} ->
      case nal_type(nal) do
        type when type in @nal_vcl_types ->
          au_nals = Enum.reverse([nal | pending])
          next_seq = rem(seq + 1, 65_536)
          next_ts = rem(ts + 6_000, 4_294_967_296)
          {[], :queue.in({au_nals, next_seq, next_ts}, queue), next_seq, next_ts}

        _non_vcl ->
          {[nal | pending], queue, seq, ts}
      end
    end)
  end

  defp nal_type(<<header, _rest::binary>>), do: header &&& 0x1F
  defp nal_type(_), do: 0

  # Split a binary buffer into complete NAL units.
  # Returns {completed_nal_units, remaining_buffer}.
  defp extract_nal_units(buffer) do
    case find_start_codes(buffer) do
      [] ->
        {[], buffer}

      [_single] ->
        # Only one start code found — NAL not yet complete
        {[], buffer}

      positions ->
        # Extract NAL units between consecutive start code positions
        pairs = Enum.zip(positions, tl(positions))

        nals =
          Enum.map(pairs, fn {{pos1, len1}, {pos2, _len2}} ->
            nal_start = pos1 + len1
            nal_len = pos2 - nal_start
            if nal_len > 0, do: :binary.part(buffer, nal_start, nal_len), else: nil
          end)
          |> Enum.reject(&is_nil/1)

        # Keep everything from the last start code onward as the remaining buffer
        {last_pos, _last_len} = List.last(positions)
        rest = :binary.part(buffer, last_pos, byte_size(buffer) - last_pos)

        {nals, rest}
    end
  end

  # Find all NAL start code positions in the buffer.
  # Returns list of {byte_offset, start_code_length} tuples.
  defp find_start_codes(buffer) do
    find_start_codes(buffer, 0, [])
  end

  defp find_start_codes(buffer, offset, acc) when offset >= byte_size(buffer) - 2 do
    Enum.reverse(acc)
  end

  defp find_start_codes(buffer, offset, acc) do
    cond do
      offset <= byte_size(buffer) - 4 &&
          :binary.part(buffer, offset, 4) == @start_code_4 ->
        find_start_codes(buffer, offset + 4, [{offset, 4} | acc])

      offset <= byte_size(buffer) - 3 &&
          :binary.part(buffer, offset, 3) == @start_code_3 ->
        find_start_codes(buffer, offset + 3, [{offset, 3} | acc])

      true ->
        find_start_codes(buffer, offset + 1, acc)
    end
  end

  defp kill_orphaned_libcamera_vid do
    case System.find_executable("pkill") do
      nil ->
        :ok

      _pkill ->
        try do
          _ = System.cmd("pkill", ["-f", "libcamera-vid"], stderr_to_stdout: true)
          :ok
        rescue
          _ -> :ok
        end
    end

    Process.sleep(100)
  end

  defp find_libcamera_vid do
    case System.find_executable("libcamera-vid") do
      nil -> {:error, :libcamera_vid_not_found}
      path -> {:ok, path}
    end
  end

  defp open_port(exec, width, height, fps, color_config) do
    awb = Map.get(color_config, :awb_mode, :auto) |> Atom.to_string()
    exposure = Map.get(color_config, :exposure_mode, :normal) |> Atom.to_string()
    saturation = Map.get(color_config, :saturation, 1.0) |> Float.to_string()
    contrast = Map.get(color_config, :contrast, 1.0) |> Float.to_string()
    sharpness = Map.get(color_config, :sharpness, 1.0) |> Float.to_string()

    args = [
      "-t",
      "0",
      "--inline",
      "--codec",
      "h264",
      "--profile",
      "baseline",
      "--awb",
      awb,
      "--metering",
      "average",
      "--exposure",
      exposure,
      "--saturation",
      saturation,
      "--contrast",
      contrast,
      "--sharpness",
      sharpness,
      "--denoise",
      "cdn_fast",
      "--intra",
      to_string(fps),
      "--framerate",
      to_string(fps),
      "--width",
      to_string(width),
      "--height",
      to_string(height),
      "-o",
      "-"
    ]

    port =
      Port.open({:spawn_executable, exec}, [
        :binary,
        :use_stdio,
        :exit_status,
        args: args
      ])

    {:ok, port}
  rescue
    _ -> {:error, :libcamera_port_open_failed}
  end
end
