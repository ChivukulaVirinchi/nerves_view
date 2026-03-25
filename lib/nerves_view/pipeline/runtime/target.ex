defmodule NervesView.Pipeline.Runtime.Target do
  @moduledoc false

  @behaviour NervesView.Pipeline.Runtime

  alias NervesView.Pipeline.Runtime.FramePublisher
  alias NervesView.Pipeline.Runtime.TargetWorker

  @impl true
  def start_pipeline(descriptor, _opts) do
    case descriptor do
      %{source: %{device_path: path}, source_type: source_type}
      when is_binary(path) and path != "" ->
        with :ok <- validate_source(source_type, path),
             {:ok, pid} <- TargetWorker.start_link(source_type: source_type, source_path: path),
             {:ok, publisher_pid} <- FramePublisher.start_link(camera_id: descriptor.camera_id) do
          snapshot = TargetWorker.snapshot(pid)

          {:ok,
           descriptor
           |> Map.put(:runtime, %{
             module: __MODULE__,
             worker_pid: pid,
             publisher_pid: publisher_pid,
             source_path: path
           })
           |> Map.put(:status, :running)
           |> Map.put(:started_at, snapshot.started_at)
           |> Map.put(:last_frame_at, snapshot.last_frame_at)
           |> Map.put(:last_error, snapshot.last_error)}
        else
          {:error, :invalid_rtsp_url} -> {:error, :invalid_source}
          {:error, :device_not_found} -> {:error, :invalid_source}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :invalid_source}
    end
  end

  @impl true
  def stop_pipeline(%{runtime: %{worker_pid: pid, publisher_pid: publisher_pid}})
      when is_pid(pid) and is_pid(publisher_pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    if Process.alive?(publisher_pid), do: Process.exit(publisher_pid, :normal)
    :ok
  end

  def stop_pipeline(%{runtime: %{worker_pid: pid}}) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  def stop_pipeline(_descriptor), do: :ok

  @impl true
  def health(%{runtime: %{worker_pid: pid, source_path: path}})
      when is_pid(pid) and is_binary(path) do
    if Process.alive?(pid) do
      snapshot = TargetWorker.snapshot(pid)

      %{
        healthy: snapshot.healthy,
        source_path: path,
        last_frame_at: snapshot.last_frame_at,
        last_error: snapshot.last_error
      }
    else
      %{healthy: false, source_path: path, last_error: :worker_down}
    end
  end

  def health(_), do: %{healthy: false}

  defp validate_source(:libcamera, _path), do: :ok

  defp validate_source(:v4l2, path) do
    if File.exists?(path), do: :ok, else: {:error, :device_not_found}
  end

  defp validate_source(:rtsp, path) do
    if String.starts_with?(path, "rtsp://"), do: :ok, else: {:error, :invalid_rtsp_url}
  end

  defp validate_source(_, _path), do: {:error, :invalid_source}
end
