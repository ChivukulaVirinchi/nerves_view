defmodule NervesViewWeb.CameraLive do
  use NervesViewWeb, :live_view

  import NervesViewWeb.Helpers
  import NervesViewWeb.WebRTCSignaling

  @impl true
  def mount(%{"id" => camera_id}, _session, socket) do
    case NervesView.Camera.Registry.get(camera_id) do
      {:ok, camera} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(NervesView.PubSub, "alerts:motion")
          :timer.send_interval(5_000, self(), :tick)
        end

        NervesView.start_camera_pipeline(camera_id)

        token =
          Phoenix.Token.sign(
            NervesViewWeb.Endpoint,
            "webrtc_stream",
            socket.assigns.current_user.id
          )

        diag = get_diag(camera_id)
        retention = NervesView.dvr_retention_window(camera_id)

        {:ok,
         socket
         |> assign_peer_ip()
         |> assign(page_title: camera.name)
         |> assign(camera: camera)
         |> assign(diag: diag)
         |> assign(token: token)
         |> assign(retention: retention)
         |> assign(mode: :live)
         |> assign(playback_start_ts: nil)
         |> assign(motion: nil)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Camera not found")
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    cam_id = socket.assigns.camera.id
    diag = get_diag(cam_id)
    retention = NervesView.dvr_retention_window(cam_id)
    alerts = NervesView.Alerts.list(camera_id: cam_id, since: System.system_time(:second) - dvr_window_seconds())
    markers = Enum.map(alerts, &%{ts: &1.inserted_at})

    {:noreply,
     socket
     |> assign(diag: diag)
     |> assign(retention: retention)
     |> push_event("dvr:markers", %{markers: markers, append: false})}
  end

  def handle_info({:motion_alert, alert}, socket) do
    if alert.camera_id == socket.assigns.camera.id do
      marker = %{ts: alert.inserted_at}

      {:noreply,
       socket
       |> assign(:motion, alert)
       |> push_event("dvr:markers", %{markers: [marker], append: true})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ex_webrtc, _, _} = msg, socket), do: handle_webrtc_info(msg, socket)
  def handle_info({:pipeline_frame, _, _} = msg, socket), do: handle_webrtc_info(msg, socket)
  def handle_info({:webrtc_negotiated, _, _, _, _} = msg, socket), do: handle_webrtc_info(msg, socket)

  @impl true
  def handle_event("webrtc:" <> _ = event, params, socket),
    do: handle_webrtc_event(event, params, socket)

  def handle_event("dvr:seek", %{"camera_id" => cam_id, "from" => from_ts}, socket) do
    from = ensure_int(from_ts)
    hls_url = "/api/dvr/#{cam_id}/playlist.m3u8?from=#{from}&to=#{from + 600}"

    {:noreply,
     socket
     |> assign(:mode, :playback)
     |> assign(:playback_start_ts, from)
     |> push_event("dvr:play", %{url: hls_url})
     |> push_event("dvr:mode", %{mode: "playback"})}
  end

  def handle_event("dvr:go_live", _params, socket) do
    {:noreply,
     socket
     |> assign(:mode, :live)
     |> assign(:playback_start_ts, nil)
     |> push_event("dvr:live", %{})
     |> push_event("dvr:mode", %{mode: "live"})}
  end

  def handle_event("dvr:time_update", %{"current_time" => ct}, socket) do
    case socket.assigns.playback_start_ts do
      nil ->
        {:noreply, socket}

      start_ts when is_integer(start_ts) ->
        ts = start_ts + round(ct)
        {:noreply, push_event(socket, "dvr:playback_pos", %{ts: ts})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-3 mb-4">
        <.button variant="ghost" size="sm" navigate={~p"/dashboard"}>
          &larr; Back
        </.button>
        <div>
          <h1 class="pg-title">{@camera.name}</h1>
          <p class="pg-sub">{@camera.id} · {@camera.source_type}</p>
        </div>
      </div>

      <% ok? = @diag && @diag.healthy %>
      <% {tl_oldest, tl_newest} = @retention || {0, 0} %>

      <.card class="overflow-hidden">
        <:content class="p-0">
          <%!-- Video viewport — full width --%>
          <div class="cam-vp cam-vp-full">
            <video
              id={"v-#{@camera.id}"}
              class="cam-vid"
              autoplay muted playsinline
              phx-hook="CameraPlayer"
              data-camera-id={@camera.id}
              data-viewer-id={"v-#{@current_user.id}"}
              data-stream-token={@token}
            />
            <%= unless ok? do %><div class="cam-ns">No Signal</div><% end %>
            <div class="cam-hud">
              <div class="cam-hud-r">
                <span class="cam-hud-t">{@camera.name}</span>
                <%= if ok? do %><span class="cam-rec">REC</span><% end %>
              </div>
              <div class="cam-hud-r">
                <span class="cam-hud-t">{@camera.id}</span>
                <span class="cam-hud-t">{fmt_ts(@diag && @diag.last_frame_at)}</span>
              </div>
            </div>
          </div>

          <%!-- Timeline scrubber --%>
          <div
            id={"tl-#{@camera.id}"}
            class="cam-tl"
            phx-hook="TimelineScrubber"
            data-camera-id={@camera.id}
            data-oldest={tl_oldest}
            data-newest={tl_newest}
            data-server-time={System.system_time(:second)}
          />
        </:content>
      </.card>

      <%!-- Status bar --%>
      <div class="flex flex-wrap items-center gap-2 mt-3">
        <div class="flex items-center gap-2">
          <span class={"dot #{if ok?, do: "dot-live", else: "dot-dead"}"} />
          <span class="text-sm font-semibold">
            {if ok?, do: "Online", else: "Offline"}
          </span>
        </div>

        <%= if @mode == :playback do %>
          <.badge variant="outline">Playback</.badge>
        <% end %>

        <%= if @motion do %>
          <.badge variant="outline">Motion</.badge>
        <% end %>

        <.badge variant={pipe_variant(@diag)}>
          {pipe_label(@diag)}
        </.badge>
      </div>

      <%!-- Camera details --%>
      <.card class="mt-4">
        <:content>
          <div class="kv">
            <span class="kv-k">Camera ID</span><span>{@camera.id}</span>
            <span class="kv-k">Source</span><span>{@camera.source_type}</span>
            <span class="kv-k">Device</span><span>{@camera.device_path || "—"}</span>
            <span class="kv-k">Pipeline</span><span>{(@diag && @diag.pipeline_status) || "stopped"}</span>
            <span class="kv-k">Last Frame</span><span class="tabular-nums">{fmt_ts(@diag && @diag.last_frame_at)}</span>
            <%= if @diag && @diag.last_error do %>
              <span class="kv-k">Error</span>
              <span class="text-destructive">{inspect(@diag.last_error)}</span>
            <% end %>
          </div>
        </:content>
      </.card>
    </div>
    """
  end

  defp get_diag(camera_id) do
    NervesView.camera_diagnostics()
    |> Enum.find(&(&1.camera_id == camera_id))
  end

  defp dvr_window_seconds, do: 30 * 24 * 3600

  defp ensure_int(v) when is_integer(v), do: v
  defp ensure_int(v) when is_binary(v), do: String.to_integer(v)

end
