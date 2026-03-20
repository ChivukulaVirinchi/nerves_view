defmodule NervesViewWeb.RecordingsLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Recordings")
     |> assign(recordings: NervesView.list_recordings())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>Recordings</h1>
      <p class="muted">Recording browser placeholder (Phase 7).</p>

      <div class="card-list">
        <%= for rec <- @recordings do %>
          <article class="camera-card">
            <h2>{rec.id}</h2>
            <p>Camera: {rec.camera_id}</p>
            <p>Mode: {rec.mode}</p>
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
