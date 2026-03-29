defmodule NervesViewWeb.RecordingsLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Recordings")
     |> assign(recordings: NervesView.list_recordings())
     |> assign(storage: NervesView.storage_usage())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>Recordings</h1>
      <p class="muted">Total recordings: {@storage.recording_count}, bytes: {@storage.total_bytes}</p>

      <div class="card-list">
        <%= for rec <- @recordings do %>
          <article class="camera-card">
            <h2>{rec.id}</h2>
            <p>Camera: {rec.camera_id}</p>
            <p>Mode: {rec.mode}</p>
            <p>Playlist: <a href={~p"/recordings/#{rec.id}/playlist.m3u8"}>open m3u8</a></p>
          </article>
        <% end %>

        <%= if @recordings == [] do %>
          <article class="camera-card empty">
            <h2>No recordings yet</h2>
            <p>Recorded clips appear here once recording pipeline is added.</p>
          </article>
        <% end %>
      </div>
    </section>
    """
  end
end
