defmodule NervesView.Pipeline.Runtime.TargetWorker do
  @moduledoc false

  use GenServer

  @tick_ms 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def snapshot(pid) when is_pid(pid) do
    GenServer.call(pid, :snapshot)
  end

  @impl true
  def init(opts) do
    source_type = Keyword.fetch!(opts, :source_type)
    source_path = Keyword.fetch!(opts, :source_path)
    now = System.system_time(:second)

    with :ok <- validate_source(source_type, source_path) do
      Process.send_after(self(), :tick, @tick_ms)

      {:ok,
       %{
         source_type: source_type,
         source_path: source_path,
         started_at: now,
         last_frame_at: now,
         healthy: true,
         last_error: nil
       }}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.system_time(:second)

    next_state =
      case validate_source(state.source_type, state.source_path) do
        :ok ->
          %{state | healthy: true, last_error: nil, last_frame_at: now}

        {:error, reason} ->
          %{state | healthy: false, last_error: reason}
      end

    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, next_state}
  end

  defp validate_source(:libcamera, _source_path), do: :ok

  defp validate_source(:v4l2, source_path) do
    if File.exists?(source_path), do: :ok, else: {:error, :device_not_found}
  end

  defp validate_source(:rtsp, source_path) do
    if String.starts_with?(source_path, "rtsp://"), do: :ok, else: {:error, :invalid_rtsp_url}
  end

  defp validate_source(_, _), do: {:error, :unsupported_source}
end
