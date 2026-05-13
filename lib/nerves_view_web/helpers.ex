defmodule NervesViewWeb.Helpers do
  @moduledoc "Shared helpers for LiveViews."

  @doc "Format a unix timestamp for display."
  def fmt_ts(value, format \\ "%H:%M:%S")
  def fmt_ts(nil, _format), do: "--:--:--"

  def fmt_ts(u, format) when is_integer(u) do
    case DateTime.from_unix(u) do
      {:ok, dt} -> Calendar.strftime(dt, format)
      _ -> "--:--:--"
    end
  end

  def fmt_ts(_, _format), do: "--:--:--"

  @doc """
  Format a unix timestamp shifted by the browser's tz offset (minutes).
  Positive offset = east of UTC (IST +330, EST -300).
  """
  def fmt_ts_local(unix, tz_offset_minutes, format \\ "%H:%M:%S")
  def fmt_ts_local(nil, _tz, _fmt), do: "--:--:--"

  def fmt_ts_local(unix, tz_offset_minutes, format) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, dt} ->
        local_dt = DateTime.add(dt, tz_offset_minutes * 60, :second)
        Calendar.strftime(local_dt, format)

      _ ->
        "--:--:--"
    end
  end

  def fmt_ts_local(_, _tz, _fmt), do: "--:--:--"

  @doc "Convert a naive Date + tz offset (minutes) into a {from_unix, to_unix} UTC window."
  def date_to_utc_window(date_iso8601, tz_offset_minutes) do
    with {:ok, date} <- Date.from_iso8601(date_iso8601),
         {:ok, local_start} <- DateTime.new(date, ~T[00:00:00]),
         {:ok, local_end} <- DateTime.new(date, ~T[23:59:59]) do
      from_utc = DateTime.add(local_start, -tz_offset_minutes * 60, :second)
      to_utc = DateTime.add(local_end, -tz_offset_minutes * 60, :second)
      {DateTime.to_unix(from_utc), DateTime.to_unix(to_utc)}
    else
      _ -> {nil, nil}
    end
  end

  @doc "Badge variant for pipeline status."
  def pipe_variant(nil), do: "destructive"

  def pipe_variant(%{pipeline_status: status, healthy: healthy?}),
    do: pipe_variant(status, healthy?)

  def pipe_variant(status, healthy?) when is_atom(status) and is_boolean(healthy?) do
    cond do
      healthy? and status == :running -> "success"
      status == :running -> "outline"
      true -> "destructive"
    end
  end

  @doc "Label for pipeline status."
  def pipe_label(nil), do: "Stopped"

  def pipe_label(%{pipeline_status: status, healthy: healthy?}),
    do: pipe_label(status, healthy?)

  def pipe_label(status, healthy?) when is_atom(status) and is_boolean(healthy?) do
    cond do
      healthy? and status == :running -> "Streaming"
      status == :running -> "Degraded"
      status -> Atom.to_string(status)
      true -> "Stopped"
    end
  end

  @doc "System stats for the HUD."
  def sys_stats do
    mem = div(:erlang.memory(:total), 1_048_576)

    load =
      case File.read("/proc/loadavg") do
        {:ok, c} -> c |> String.split() |> List.first("0.00")
        _ -> "—"
      end

    secs = div(:erlang.statistics(:wall_clock) |> elem(0), 1000)

    up =
      cond do
        secs < 60 -> "#{secs}s"
        secs < 3600 -> "#{div(secs, 60)}m"
        true -> "#{div(secs, 3600)}h#{div(rem(secs, 3600), 60)}m"
      end

    %{mem: mem, load: load, up: up}
  end
end
