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
