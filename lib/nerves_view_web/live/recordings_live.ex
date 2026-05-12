defmodule NervesViewWeb.RecordingsLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesView.PubSub, "recordings")
      :timer.send_interval(30_000, self(), :refresh)
    end

    storage = NervesView.storage_usage()

    {:ok,
     socket
     |> assign(page_title: "Recordings")
     |> assign(recordings: NervesView.list_recordings())
     |> assign(storage: storage)
     |> assign(cameras: NervesView.list_cameras())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> assign(recordings: NervesView.list_recordings())
     |> assign(storage: NervesView.storage_usage())}
  end

  def handle_info({:recording_stored, _rec}, socket) do
    {:noreply,
     socket
     |> assign(recordings: NervesView.list_recordings())
     |> assign(storage: NervesView.storage_usage())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Recordings
        <:subtitle>Clip archive and storage overview</:subtitle>
      </.header>

      <%!-- Stats row --%>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mt-5">
        <.card>
          <:content>
            <p class="stat-value">{@storage.recording_count}</p>
            <p class="stat-label">Total Clips</p>
          </:content>
        </.card>
        <.card>
          <:content>
            <p class="stat-value">{format_bytes(@storage.total_bytes)}</p>
            <p class="stat-label">Storage Used</p>
          </:content>
        </.card>
        <.card>
          <:content>
            <p class="stat-value">{length(@cameras)}</p>
            <p class="stat-label">Sources</p>
          </:content>
        </.card>
        <.card>
          <:content>
            <p class="stat-value">{avg_clip_size(@storage)}</p>
            <p class="stat-label">Avg Clip Size</p>
          </:content>
        </.card>
      </div>

      <%!-- Recordings list --%>
      <%= if @recordings == [] do %>
        <.empty class="mt-8">
          <:title>No recordings yet</:title>
          <:description>
            Clips will appear here once the recording pipeline captures footage.
          </:description>
        </.empty>
      <% else %>
        <.data_table rows={@recordings} class="mt-5">
          <:col :let={rec} label="Recording">{rec.id}</:col>
          <:col :let={rec} label="Camera">{rec.camera_id}</:col>
          <:col :let={rec} label="Mode">
            <.badge variant={mode_variant(rec.mode)}>{rec.mode}</.badge>
          </:col>
          <:col :let={rec} label="Started">{format_ts(rec.started_at)}</:col>
          <:col :let={rec} label="Duration">{format_duration(rec.started_at, rec.ended_at)}</:col>
          <:action :let={rec}>
            <.button variant="outline" size="sm" href={~p"/recordings/#{rec.id}/playlist.m3u8"}>
              Open
            </.button>
          </:action>
        </.data_table>
      <% end %>
    </div>
    """
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp avg_clip_size(%{recording_count: 0}), do: "—"

  defp avg_clip_size(%{recording_count: count, total_bytes: bytes}) do
    format_bytes(div(bytes, count))
  end

  defp mode_variant(:motion), do: "outline"
  defp mode_variant(:continuous), do: "secondary"
  defp mode_variant(_), do: "secondary"

  defp format_ts(nil), do: "—"

  defp format_ts(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, dt} -> Calendar.strftime(dt, "%b %d, %H:%M")
      _ -> "—"
    end
  end

  defp format_ts(_), do: "—"

  defp format_duration(nil, _), do: "—"
  defp format_duration(_, nil), do: "—"

  defp format_duration(started, ended) when is_integer(started) and is_integer(ended) do
    secs = max(ended - started, 0)

    cond do
      secs < 60 -> "#{secs}s"
      secs < 3600 -> "#{div(secs, 60)}m #{rem(secs, 60)}s"
      true -> "#{div(secs, 3600)}h #{div(rem(secs, 3600), 60)}m"
    end
  end

  defp format_duration(_, _), do: "—"
end
