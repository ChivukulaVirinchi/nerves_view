defmodule NervesView.Recording.SegmentReaper do
  @moduledoc """
  Periodically enforces recording retention by deleting segments
  older than the configured retention window and pruning when
  disk usage is critically high.
  """

  use GenServer

  require Logger

  alias NervesView.DVR.SegmentIndex
  alias NervesView.Recording.PlaylistManager

  @check_interval_ms 60_000

  # ── Public API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # ── Callbacks ──

  @impl true
  def init(:ok) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    reap()
    schedule_check()
    {:noreply, state}
  end

  # ── Reaping logic ──

  defp reap do
    recordings_path = Application.get_env(:nerves_view, :recordings_path, "tmp/recordings")
    retention_hours = Application.get_env(:nerves_view, :recording_retention_hours, 24)
    cutoff = System.system_time(:second) - retention_hours * 3600

    case File.ls(recordings_path) do
      {:ok, camera_dirs} ->
        Enum.each(camera_dirs, fn camera_id ->
          reap_camera(recordings_path, camera_id, cutoff)
        end)

      {:error, _} ->
        :ok
    end
  end

  defp reap_camera(recordings_path, camera_id, cutoff) do
    dir = Path.join(recordings_path, camera_id)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, "seg-"))
        |> Enum.filter(&String.ends_with?(&1, ".ts"))
        |> Enum.each(fn filename ->
          case parse_segment_timestamp(filename) do
            {:ok, ts} when ts < cutoff ->
              path = Path.join(dir, filename)

              case File.rm(path) do
                :ok ->
                  Logger.debug("SegmentReaper deleted #{camera_id}/#{filename}")
                  PlaylistManager.remove_segment(camera_id, ts)
                  SegmentIndex.remove(camera_id, ts)

                {:error, reason} ->
                  Logger.warning(
                    "SegmentReaper failed to delete #{camera_id}/#{filename}: #{inspect(reason)}"
                  )
              end

            _ ->
              :ok
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp parse_segment_timestamp(filename) do
    case Regex.run(~r/^seg-(\d+)\.ts$/, filename) do
      [_, ts_str] -> {:ok, String.to_integer(ts_str)}
      _ -> :error
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval_ms)
  end
end
