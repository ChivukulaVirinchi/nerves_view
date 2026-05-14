defmodule NervesView.Camera.Producer.RTSP do
  @moduledoc """
  Captures H.264 from an RTSP source through ffmpeg.

  The fast path copies an H.264 RTSP stream into Annex B byte stream format on
  stdout. Cameras that only expose H.265 or MJPEG will need an explicit
  transcode path before they can feed the existing WebRTC/HLS pipeline.
  """

  use GenServer

  import Bitwise
  require Logger

  @behaviour NervesView.Camera.Producer
  @tick_ms 1_000
  @start_code_4 <<0, 0, 0, 1>>
  @start_code_3 <<0, 0, 1>>
  @nal_vcl_types 1..5

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(opts) do
    source_path = Keyword.fetch!(opts, :source_path)

    with {:ok, exec} <- find_ffmpeg(),
         {:ok, port} <- open_port(exec, source_path) do
      now = System.system_time(:second)
      Process.send_after(self(), :tick, @tick_ms)

      {:ok,
       %{
         source_type: :rtsp,
         source_path: source_path,
         started_at: now,
         last_frame_at: nil,
         healthy: false,
         last_error: nil,
         sequence: 0,
         timestamp: 0,
         payload: <<>>,
         au_queue: :queue.new(),
         pending_nals: [],
         buffer: <<>>,
         port: port,
         exec: exec
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    queued = :queue.to_list(state.au_queue)
    snapshot = state |> Map.put(:au_queue, queued)
    {:reply, snapshot, %{state | au_queue: :queue.new()}}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)

    healthy? =
      is_port(state.port) and Port.info(state.port) != nil and
        is_integer(state.last_frame_at) and
        System.system_time(:second) - state.last_frame_at <= 5

    last_error =
      cond do
        healthy? -> nil
        state.last_error -> state.last_error
        true -> :waiting_for_rtsp_frames
      end

    {:noreply, %{state | healthy: healthy?, last_error: last_error}}
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    buffer = state.buffer <> data

    case extract_nal_units(buffer) do
      {[], rest} ->
        capped =
          if byte_size(rest) > 524_288 do
            Logger.warning("RTSP buffer overflow on #{redact_url(state.source_path)}")
            <<>>
          else
            rest
          end

        {:noreply, %{state | buffer: capped}}

      {nal_units, rest} ->
        {pending, au_queue, seq, ts} =
          group_into_aus(
            nal_units,
            state.pending_nals,
            state.au_queue,
            state.sequence,
            state.timestamp
          )

        {:noreply,
         %{
           state
           | payload: List.last(nal_units),
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
    Logger.warning("ffmpeg RTSP capture exited with status #{status}; restarting in 2s")
    Process.send_after(self(), :restart_port, 2_000)
    {:noreply, %{state | port: nil, healthy: false, last_error: {:ffmpeg_exit, status}}}
  end

  def handle_info(:restart_port, state) do
    case open_port(state.exec, state.source_path) do
      {:ok, port} ->
        {:noreply, %{state | port: port, buffer: <<>>, pending_nals: [], last_error: nil}}

      {:error, reason} ->
        Process.send_after(self(), :restart_port, 5_000)
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

  defp find_ffmpeg do
    case System.find_executable("ffmpeg") do
      nil -> {:error, :ffmpeg_not_found}
      path -> {:ok, path}
    end
  end

  defp open_port(exec, source_path) do
    transport = Application.get_env(:nerves_view, :rtsp_transport, "tcp")

    args = [
      "-hide_banner",
      "-loglevel",
      "warning",
      "-rtsp_transport",
      transport,
      "-i",
      source_path,
      "-an",
      "-c:v",
      "copy",
      "-bsf:v",
      "h264_mp4toannexb",
      "-f",
      "h264",
      "pipe:1"
    ]

    port =
      Port.open({:spawn_executable, exec}, [
        :binary,
        :use_stdio,
        :stderr_to_stdout,
        :exit_status,
        args: args
      ])

    {:ok, port}
  rescue
    _ -> {:error, :ffmpeg_port_open_failed}
  end

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

  defp extract_nal_units(buffer) do
    case find_start_codes(buffer) do
      [] ->
        {[], buffer}

      [_single] ->
        {[], buffer}

      positions ->
        pairs = Enum.zip(positions, tl(positions))

        nals =
          Enum.map(pairs, fn {{pos1, len1}, {pos2, _len2}} ->
            nal_start = pos1 + len1
            nal_len = pos2 - nal_start
            if nal_len > 0, do: :binary.part(buffer, nal_start, nal_len), else: nil
          end)
          |> Enum.reject(&is_nil/1)

        {last_pos, _last_len} = List.last(positions)
        rest = :binary.part(buffer, last_pos, byte_size(buffer) - last_pos)

        {nals, rest}
    end
  end

  defp find_start_codes(buffer), do: find_start_codes(buffer, 0, [])

  defp find_start_codes(buffer, offset, acc) when offset >= byte_size(buffer) - 2 do
    Enum.reverse(acc)
  end

  defp find_start_codes(buffer, offset, acc) do
    cond do
      offset <= byte_size(buffer) - 4 and :binary.part(buffer, offset, 4) == @start_code_4 ->
        find_start_codes(buffer, offset + 4, [{offset, 4} | acc])

      offset <= byte_size(buffer) - 3 and :binary.part(buffer, offset, 3) == @start_code_3 ->
        find_start_codes(buffer, offset + 3, [{offset, 3} | acc])

      true ->
        find_start_codes(buffer, offset + 1, acc)
    end
  end

  defp redact_url(url) do
    Regex.replace(~r(//[^:/@]+:[^@]+@), url, "//[redacted]@")
  end
end
