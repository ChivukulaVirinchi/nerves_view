defmodule NervesView.Pipeline.Runtime.Host do
  @moduledoc false

  @behaviour NervesView.Pipeline.Runtime

  alias NervesView.Pipeline.TestSource

  @impl true
  def start_pipeline(descriptor, opts) do
    case Map.get(descriptor, :camera_id) do
      camera_id when is_binary(camera_id) and camera_id != "" ->
        frame_count = Keyword.get(opts, :frame_count, 30)
        interval_ms = Keyword.get(opts, :interval_ms, 33)
        start_ts = System.system_time(:second)

        {:ok, pid} = TestSource.start_link(frame_count: frame_count, interval_ms: interval_ms)

        {:ok,
         descriptor
         |> Map.put(:runtime, %{module: __MODULE__, source_pid: pid})
         |> Map.put(:status, :running)
         |> Map.put(:started_at, start_ts)
         |> Map.put(:last_frame_at, start_ts)}

      _ ->
        {:error, :invalid_camera_id}
    end
  end

  @impl true
  def stop_pipeline(%{runtime: %{source_pid: pid}}) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :normal)
    :ok
  end

  def stop_pipeline(_descriptor), do: :ok

  @impl true
  def health(%{runtime: %{source_pid: pid}}) when is_pid(pid) do
    %{healthy: Process.alive?(pid)}
  end

  def health(_), do: %{healthy: false}
end
