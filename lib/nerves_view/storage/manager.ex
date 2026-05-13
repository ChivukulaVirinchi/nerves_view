defmodule NervesView.Storage.Manager do
  @moduledoc """
  Tracks recording storage usage and retention limits. Periodically inspects the
  disk holding the recordings directory and, when nearing capacity, logs
  warnings and (at critical levels) enforces count-based retention so the SD
  card doesn't fill up and stall writes.
  """

  use GenServer

  require Logger

  alias NervesView.Recording.Store

  @name __MODULE__
  @check_interval_ms 60_000
  @warn_threshold 0.90
  @critical_threshold 0.95
  @critical_keep_count 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec usage() :: %{recording_count: non_neg_integer(), total_bytes: non_neg_integer()}
  def usage do
    GenServer.call(@name, :usage)
  end

  @spec enforce_retention(keyword()) :: %{trimmed: non_neg_integer(), max_count: pos_integer()}
  def enforce_retention(opts \\ []) do
    GenServer.call(@name, {:enforce_retention, opts})
  end

  @doc """
  Returns the current disk usage of the partition holding the recordings dir.
  `{:ok, %{used_ratio: 0.0..1.0, mount: String.t()}}` or `{:error, term()}`.
  """
  @spec disk_usage() :: {:ok, map()} | {:error, term()}
  def disk_usage do
    case Application.get_env(:nerves_view, :recordings_path) do
      nil -> {:error, :no_path}
      path -> disk_usage_for(path)
    end
  end

  @impl true
  def init(state) do
    Process.send_after(self(), :check_disk, @check_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:usage, _from, state) do
    recordings = Store.list()

    total_bytes =
      Enum.reduce(recordings, 0, fn rec, acc ->
        acc + Map.get(rec, :size_bytes, 0)
      end)

    {:reply, %{recording_count: length(recordings), total_bytes: total_bytes}, state}
  end

  def handle_call({:enforce_retention, opts}, _from, state) do
    max_count = Keyword.get(opts, :max_count, 200)
    to_remove = Enum.drop(Store.list(), max_count)

    Enum.each(to_remove, fn rec ->
      paths = [Map.get(rec, :playlist_path) | Map.get(rec, :segment_paths, [])]

      Enum.each(paths, fn
        nil -> :ok
        path -> File.rm(path)
      end)
    end)

    trimmed = Store.trim_by_count(max_count)
    {:reply, %{trimmed: trimmed, max_count: max_count}, state}
  end

  @impl true
  def handle_info(:check_disk, state) do
    case disk_usage() do
      {:ok, %{used_ratio: ratio}} when ratio >= @critical_threshold ->
        pct = trunc(ratio * 100)
        Logger.error("Recording disk #{pct}% full — trimming to #{@critical_keep_count} recordings")
        _ = enforce_retention(max_count: @critical_keep_count)

      {:ok, %{used_ratio: ratio}} when ratio >= @warn_threshold ->
        Logger.warning("Recording disk #{trunc(ratio * 100)}% full")

      _ ->
        :ok
    end

    Process.send_after(self(), :check_disk, @check_interval_ms)
    {:noreply, state}
  end

  defp disk_usage_for(path) do
    case System.find_executable("df") do
      nil ->
        {:error, :df_not_available}

      _ ->
        # `df -P -k <path>` is the POSIX-stable form: 1024-byte blocks, predictable
        # column layout. Output looks like:
        #   Filesystem  1024-blocks   Used  Available  Capacity  Mounted on
        #   /dev/...    60652764      ...   ...        9%        /data
        case System.cmd("df", ["-P", "-k", path], stderr_to_stdout: true) do
          {output, 0} -> parse_df_output(output)
          {output, code} -> {:error, {:df_failed, code, output}}
        end
    end
  rescue
    e -> {:error, e}
  end

  defp parse_df_output(output) do
    case output |> String.split("\n", trim: true) |> Enum.at(1) do
      nil ->
        {:error, :df_no_data}

      data_line ->
        case String.split(data_line, ~r/\s+/, trim: true) do
          [_fs, _blocks, _used, _avail, capacity, mount | _] ->
            pct_str = String.trim_trailing(capacity, "%")

            case Integer.parse(pct_str) do
              {pct, _} -> {:ok, %{used_ratio: pct / 100, mount: mount}}
              :error -> {:error, :df_unparsable}
            end

          _ ->
            {:error, :df_unparsable}
        end
    end
  end
end
