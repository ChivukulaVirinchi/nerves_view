defmodule NervesView.Camera.Producer.Libcamera do
  @moduledoc false

  use GenServer

  @behaviour NervesView.Camera.Producer
  @tick_ms 33
  @max_payload 1200

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(opts) do
    source_path = Keyword.get(opts, :source_path, "/dev/video0")
    width = Keyword.get(opts, :width, 1280)
    height = Keyword.get(opts, :height, 720)
    fps = Keyword.get(opts, :fps, 30)

    with {:ok, exec} <- find_libcamera_vid(),
         {:ok, port} <- open_port(exec, width, height, fps) do
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
         payload: <<0, 0, 1, 101, 0, 0, 0, 1>>,
         port: port,
         exec: exec
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:tick, state) do
    now = System.system_time(:second)
    Process.send_after(self(), :tick, @tick_ms)

    next =
      if File.exists?(state.source_path) do
        %{
          state
          | healthy: true,
            last_error: nil,
            last_frame_at: now,
            sequence: rem(state.sequence + 1, 65_535),
            timestamp: rem(state.timestamp + 3_000, 4_294_967_295)
        }
      else
        %{state | healthy: false, last_error: :device_not_found}
      end

    {:noreply, next}
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    payload = normalize_payload(data)

    next =
      if payload == <<>> do
        state
      else
        %{
          state
          | payload: payload,
            sequence: rem(state.sequence + 1, 65_535),
            timestamp: rem(state.timestamp + 3_000, 4_294_967_295),
            last_frame_at: System.system_time(:second),
            healthy: true,
            last_error: nil
        }
      end

    {:noreply, next}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    {:noreply, %{state | healthy: false, last_error: {:libcamera_exit, status}}}
  end

  @impl true
  def terminate(_reason, state) do
    if is_port(state[:port]), do: Port.close(state.port)
    :ok
  end

  defp find_libcamera_vid do
    case System.find_executable("libcamera-vid") do
      nil -> {:error, :libcamera_vid_not_found}
      path -> {:ok, path}
    end
  end

  defp open_port(exec, width, height, fps) do
    args = [
      "-t",
      "0",
      "--inline",
      "--codec",
      "h264",
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
        :stderr_to_stdout,
        args: args
      ])

    {:ok, port}
  rescue
    _ -> {:error, :libcamera_port_open_failed}
  end

  defp normalize_payload(data) do
    if byte_size(data) > @max_payload do
      :binary.part(data, 0, @max_payload)
    else
      data
    end
  end
end
