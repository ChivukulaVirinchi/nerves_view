defmodule NervesView.Pipeline.Runtime.Target do
  @moduledoc false

  @behaviour NervesView.Pipeline.Runtime

  alias NervesView.Pipeline.Runtime.FramePublisher
  alias NervesView.Recording.SegmentWriter

  @impl true
  def start_pipeline(descriptor, _opts) do
    case descriptor do
      %{source: %{device_path: path}, source_type: source_type}
      when is_binary(path) and path != "" ->
        with :ok <- validate_source(source_type, path),
             {:ok, publisher_pid} <-
               FramePublisher.start_link(
                 camera_id: descriptor.camera_id,
                 source_type: source_type,
                 source_path: path,
                 color_config: descriptor[:color_config]
               ) do
          snapshot = FramePublisher.snapshot(publisher_pid)

          # Start the segment writer for continuous recording
          writer_pid =
            case SegmentWriter.start_link(camera_id: descriptor.camera_id) do
              {:ok, pid} -> pid
              {:error, reason} ->
                require Logger
                Logger.warning("SegmentWriter failed to start: #{inspect(reason)}")
                nil
            end

          {:ok,
           descriptor
           |> Map.put(:runtime, %{
             module: __MODULE__,
             publisher_pid: publisher_pid,
             writer_pid: writer_pid,
             source_path: path
           })
           |> Map.put(:status, :running)
           |> Map.put(:started_at, snapshot.started_at)
           |> Map.put(:last_frame_at, snapshot.last_frame_at)
           |> Map.put(:last_error, snapshot.last_error)}
        else
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :invalid_source}
    end
  end

  @impl true
  def stop_pipeline(%{runtime: runtime}) do
    if is_pid(runtime[:publisher_pid]) and Process.alive?(runtime.publisher_pid) do
      GenServer.stop(runtime.publisher_pid, :normal)
    end

    if is_pid(runtime[:writer_pid]) and Process.alive?(runtime.writer_pid) do
      GenServer.stop(runtime.writer_pid, :normal)
    end

    :ok
  end

  def stop_pipeline(_descriptor), do: :ok

  @impl true
  def health(%{runtime: %{publisher_pid: pid, source_path: path}})
      when is_pid(pid) and is_binary(path) do
    if Process.alive?(pid) do
      snapshot = FramePublisher.snapshot(pid)

      %{
        healthy: snapshot.healthy,
        source_path: path,
        last_frame_at: snapshot.last_frame_at,
        last_error: snapshot.last_error
      }
    else
      %{healthy: false, source_path: path, last_error: :publisher_down}
    end
  end

  def health(_), do: %{healthy: false}

  defp validate_source(:libcamera, _path), do: :ok
  defp validate_source(_, _path), do: {:error, :invalid_source}
end
