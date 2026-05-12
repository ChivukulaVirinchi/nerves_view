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
         |> assign(playback_from: nil)
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
    {:noreply, socket |> assign(diag: diag) |> assign(retention: retention)}
  end

  def handle_info({:motion_alert, alert}, socket) do
    if alert.camera_id == socket.assigns.camera.id do
      {:noreply, assign(socket, :motion, alert)}
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
    from = if is_binary(from_ts), do: String.to_integer(from_ts), else: from_ts
    url = "/api/dvr/#{cam_id}/playlist.m3u8?from=#{from}"

    {:noreply,
     socket
     |> assign(:playback_from, from)
     |> push_event("dvr:play", %{url: url})}
  end

  def handle_event("dvr:go_live", _params, socket) do
    {:noreply,
     socket
     |> assign(:playback_from, nil)
     |> push_event("dvr:live", %{})}
  end

  def handle_event("dvr:time_update", _params, socket) do
    {:noreply, socket}
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

        <%= if @playback_from do %>
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

end
