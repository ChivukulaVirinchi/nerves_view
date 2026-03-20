defmodule NervesViewWeb.DashboardLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    Enum.each(NervesView.list_cameras(), &NervesView.start_test_pipeline(&1.id))

    {:ok,
     socket
     |> assign(page_title: "Dashboard")
     |> assign(cameras: NervesView.list_cameras())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>Dashboard</h1>
      <p class="muted">Live camera grid placeholder (Phase 7).</p>

      <div class="camera-grid">
        <%= for camera <- @cameras do %>
          <article class="camera-card">
            <h2>{camera.name}</h2>
            <video
              id={"video-#{camera.id}"}
              class="camera-video"
              autoplay
              muted
              playsinline
              phx-hook="WebRTCPlayer"
              data-camera-id={camera.id}
              data-viewer-id={"viewer-#{@current_user.id}"}
            ></video>
            <p>ID: {camera.id}</p>
            <p>Status: {camera.status}</p>
          </article>
        <% end %>

        <%= if @cameras == [] do %>
          <article class="camera-card empty">
            <h2>No cameras yet</h2>
            <p>Add camera sources in upcoming phases.</p>
          </article>
        <% end %>
      </div>
    </section>
    """
  end
end
