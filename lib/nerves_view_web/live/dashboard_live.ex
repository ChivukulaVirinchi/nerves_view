defmodule NervesViewWeb.DashboardLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesView.PubSub, "alerts:motion")
    end

    Enum.each(NervesView.list_cameras(), &NervesView.start_camera_pipeline(&1.id))

    {:ok,
     socket
     |> assign(page_title: "Dashboard")
     |> assign(cameras: NervesView.list_cameras())
     |> assign(last_motion: %{})
     |> assign(grid_layout: 4)}
  end

  @impl true
  def handle_info({:motion_alert, alert}, socket) do
    {:noreply,
     assign(socket, :last_motion, Map.put(socket.assigns.last_motion, alert.camera_id, alert))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>Dashboard</h1>
      <p class="muted">Live multi-camera dashboard.</p>

      <div class="grid-picker">
        <button phx-click="set_layout" phx-value-layout="1">1</button>
        <button phx-click="set_layout" phx-value-layout="2">2</button>
        <button phx-click="set_layout" phx-value-layout="4">4</button>
        <button phx-click="set_layout" phx-value-layout="9">9</button>
      </div>

      <div class={"camera-grid layout-#{@grid_layout}"}>
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
            <%= if motion = Map.get(@last_motion, camera.id) do %>
              <p class="motion-pill">Motion at {motion.inserted_at}</p>
            <% end %>
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

  @impl true
  def handle_event("set_layout", %{"layout" => layout}, socket) do
    parsed =
      case Integer.parse(layout || "") do
        {value, _} when value in [1, 2, 4, 9] -> value
        _ -> 4
      end

    {:noreply, assign(socket, :grid_layout, parsed)}
  end
end
