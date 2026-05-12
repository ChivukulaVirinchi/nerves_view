defmodule NervesViewWeb.DashboardLive do
  use NervesViewWeb, :live_view

  import NervesViewWeb.Helpers
  import NervesViewWeb.WebRTCSignaling

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesView.PubSub, "alerts:motion")
      :timer.send_interval(5_000, self(), :tick)
    end

    cameras = NervesView.list_cameras()
    Enum.each(cameras, &NervesView.start_camera_pipeline(&1.id))

    token =
      Phoenix.Token.sign(NervesViewWeb.Endpoint, "webrtc_stream", socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign_peer_ip()
     |> assign(page_title: "Dashboard")
     |> assign(cameras: cameras)
     |> assign(diags: diag_map())
     |> assign(motions: %{})
     |> assign(token: token)
     |> assign(grid: 4)
     |> assign(stats: sys_stats())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, socket |> assign(diags: diag_map()) |> assign(stats: sys_stats())}
  end

  def handle_info({:motion_alert, alert}, socket) do
    {:noreply, assign(socket, :motions, Map.put(socket.assigns.motions, alert.camera_id, alert))}
  end

  def handle_info({:ex_webrtc, _, _} = msg, socket), do: handle_webrtc_info(msg, socket)
  def handle_info({:pipeline_frame, _, _} = msg, socket), do: handle_webrtc_info(msg, socket)
  def handle_info({:webrtc_negotiated, _, _, _, _} = msg, socket), do: handle_webrtc_info(msg, socket)

  @impl true
  def handle_event("webrtc:" <> _ = event, params, socket),
    do: handle_webrtc_event(event, params, socket)

  def handle_event("grid", %{"n" => n}, socket) do
    v =
      case Integer.parse(n) do
        {v, _} when v in [1, 2, 4, 9] -> v
        _ -> 4
      end

    {:noreply, assign(socket, :grid, v)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-3 mb-5">
        <div>
          <h1 class="pg-title">Live Feed</h1>
          <p class="pg-sub">
            {length(@cameras)} source{if length(@cameras) != 1, do: "s"}
            · <span class="text-sage">{n_healthy(@diags)} online</span>
          </p>
        </div>

        <div class="flex items-center gap-2 flex-wrap">
          <div class="hidden md:flex items-center gap-1.5">
            <span class="sys-pill">{@stats.mem} MB</span>
            <span class="sys-pill">Load {@stats.load}</span>
            <span class="sys-pill">Up {@stats.up}</span>
          </div>
          <div class="flex p-0.5 bg-muted rounded-lg gap-0.5">
            <.button
              :for={n <- [1, 2, 4, 9]}
              variant={if @grid == n, do: "secondary", else: "ghost"}
              size="sm"
              phx-click="grid"
              phx-value-n={n}
            >{n}</.button>
          </div>
        </div>
      </div>

      <div class={"cam-grid g#{@grid}"}>
        <%= for cam <- @cameras do %>
          <% d = Map.get(@diags, cam.id, %{}) %>
          <% ok? = Map.get(d, :healthy, false) %>
          <% pipe = Map.get(d, :pipeline_status) %>
          <% frm = Map.get(d, :last_frame_at) %>
          <.link navigate={~p"/cameras/#{cam.id}"} class="block">
            <.card class={"cam-card overflow-hidden #{if ok?, do: "cam-live"}"}>
              <:content class="p-0">
                <div class="cam-vp">
                  <video
                    id={"v-#{cam.id}"}
                    class="cam-vid"
                    autoplay muted playsinline
                    phx-hook="CameraPlayer"
                    data-camera-id={cam.id}
                    data-viewer-id={"v-#{@current_user.id}"}
                    data-stream-token={@token}
                  />
                  <%= unless ok? do %><div class="cam-ns">No Signal</div><% end %>
                  <div class="cam-hud">
                    <div class="cam-hud-r">
                      <span class="cam-hud-t">{cam.name}</span>
                      <%= if ok? do %><span class="cam-rec">REC</span><% end %>
                    </div>
                    <div class="cam-hud-r">
                      <span class="cam-hud-t">{cam.id}</span>
                      <span class="cam-hud-t">{fmt_ts(frm)}</span>
                    </div>
                  </div>
                </div>

                <div class="px-3 py-2 flex items-center justify-between gap-2 border-t text-sm">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class={"dot #{if ok?, do: "dot-live", else: "dot-dead"}"} />
                    <span class="font-display font-semibold truncate">{cam.name}</span>
                  </div>
                  <div class="flex items-center gap-1.5 shrink-0">
                    <%= if Map.get(@motions, cam.id) do %>
                      <.badge variant="outline">Motion</.badge>
                    <% end %>
                    <.badge variant={pipe_variant(pipe, ok?)}>{pipe_label(pipe, ok?)}</.badge>
                  </div>
                </div>
              </:content>
            </.card>
          </.link>
        <% end %>
      </div>

      <%= if @cameras == [] do %>
        <.empty class="mt-12">
          <:title>No cameras connected</:title>
          <:description>Plug in a camera or add one in Settings.</:description>
          <:actions><.button navigate={~p"/settings"}>Open Settings</.button></:actions>
        </.empty>
      <% end %>
    </div>
    """
  end

  defp diag_map, do: NervesView.camera_diagnostics() |> Map.new(&{&1.camera_id, &1})
  defp n_healthy(d), do: d |> Map.values() |> Enum.count(& &1.healthy)

end
