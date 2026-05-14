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
        color_config = NervesView.get_camera_color_config(camera_id)

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
         |> assign(playback_base_ts: nil)
         |> assign(motion: nil)
         |> assign(tz_offset: 0)
         |> assign(scrubber_day: nil)
         |> assign(scrubber_day_iso: "")
         |> assign(color_config: color_config)
         |> assign(show_color_popover: false)}

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

    {oldest, newest} =
      scrubber_bounds(socket.assigns.scrubber_day, retention, socket.assigns.tz_offset)

    alerts = NervesView.Alerts.list(camera_id: cam_id, since: oldest)

    markers =
      alerts
      |> Enum.filter(&(&1.inserted_at <= newest))
      |> Enum.map(&%{ts: &1.inserted_at})

    {:noreply,
     socket
     |> assign(diag: diag)
     |> assign(retention: retention)
     |> push_event("dvr:markers", %{markers: markers, append: false})
     |> push_event("dvr:bounds", %{
       server_time: System.system_time(:second),
       oldest: oldest,
       newest: newest
     })}
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

  def handle_info({:webrtc_negotiated, _, _, _, _} = msg, socket),
    do: handle_webrtc_info(msg, socket)

  @impl true
  def handle_event("tz:offset", %{"offset_minutes" => offset}, socket) do
    off = ensure_int(offset)
    {oldest, newest} = scrubber_bounds(socket.assigns.scrubber_day, socket.assigns.retention, off)

    {:noreply,
     socket
     |> assign(tz_offset: off)
     |> push_event("dvr:bounds", %{
       server_time: System.system_time(:second),
       oldest: oldest,
       newest: newest
     })}
  end

  def handle_event("webrtc:" <> _ = event, params, socket),
    do: handle_webrtc_event(event, params, socket)

  def handle_event("dvr:seek", %{"camera_id" => cam_id, "from" => from_ts}, socket) do
    from = ensure_int(from_ts)
    {oldest, newest} = socket.assigns.retention || {0, 0}

    cond do
      cam_id != socket.assigns.camera.id ->
        {:noreply,
         socket
         |> put_flash(:error, "Camera mismatch.")
         |> push_event("dvr:seek_rejected", %{reason: "camera_mismatch"})}

      newest == 0 ->
        {:noreply,
         socket
         |> put_flash(:error, "No recordings to play yet.")
         |> push_event("dvr:seek_rejected", %{reason: "no_recordings"})}

      from < oldest or from > newest ->
        {:noreply,
         socket
         |> put_flash(:error, "That moment is outside the retention window.")
         |> push_event("dvr:seek_rejected", %{
           reason: "out_of_bounds",
           oldest: oldest,
           newest: newest
         })}

      true ->
        to = min(from + 600, newest)
        hls_url = "/api/dvr/#{cam_id}/playlist.m3u8?from=#{from}&to=#{to}"
        {playback_base, start_offset} = compute_playback_base_and_offset(cam_id, from)

        {:noreply,
         socket
         |> assign(:mode, :playback)
         |> assign(:playback_start_ts, from)
         |> assign(:playback_base_ts, playback_base)
         |> push_event("dvr:play", %{url: hls_url, start_offset: start_offset})
         |> push_event("dvr:mode", %{mode: "playback"})}
    end
  end

  def handle_event("dvr:go_live", _params, socket) do
    {:noreply,
     socket
     |> assign(:mode, :live)
     |> assign(:playback_start_ts, nil)
     |> assign(:playback_base_ts, nil)
     |> push_event("dvr:live", %{})
     |> push_event("dvr:mode", %{mode: "live"})}
  end

  def handle_event("dvr:time_update", %{"current_time" => ct}, socket) do
    case socket.assigns.playback_base_ts do
      nil ->
        {:noreply, socket}

      base_ts when is_integer(base_ts) ->
        ts = base_ts + round(ct)
        {:noreply, push_event(socket, "dvr:playback_pos", %{ts: ts})}
    end
  end

  def handle_event("dvr:set_day", %{"day" => day_iso}, socket) do
    case Date.from_iso8601(day_iso) do
      {:ok, day} ->
        {oldest, newest} =
          scrubber_bounds(day, socket.assigns.retention, socket.assigns.tz_offset)

        {:noreply,
         socket
         |> assign(scrubber_day: day)
         |> assign(scrubber_day_iso: day_iso)
         |> push_event("dvr:bounds", %{
           server_time: System.system_time(:second),
           oldest: oldest,
           newest: newest
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_color_popover", _params, socket) do
    {:noreply, assign(socket, show_color_popover: !socket.assigns.show_color_popover)}
  end

  def handle_event("update_color", params, socket) do
    awb =
      parse_known_atom(
        params["awb_mode"],
        ~w(auto indoor daylight cloudy fluorescent tungsten incandescent),
        :auto
      )

    sat = params["saturation"] || "1.0"
    con = params["contrast"] || "1.0"
    sharp = params["sharpness"] || "1.0"
    exp = parse_known_atom(params["exposure_mode"], ~w(normal short long), :normal)

    new_config = %NervesView.Camera.Config{
      awb_mode: awb,
      saturation: parse_param_float(sat, 1.0),
      contrast: parse_param_float(con, 1.0),
      sharpness: parse_param_float(sharp, 1.0),
      exposure_mode: exp
    }

    {:noreply, assign(socket, color_config: new_config)}
  end

  def handle_event("apply_color_config", _params, socket) do
    cam_id = socket.assigns.camera.id
    config = socket.assigns.color_config

    # Persist config, then restart pipeline
    :ok = NervesView.set_camera_color_config(cam_id, Map.from_struct(config))

    case NervesView.restart_camera_pipeline(cam_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(show_color_popover: false)
         |> put_flash(:info, "Color settings applied — pipeline restarted.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(show_color_popover: false)
         |> put_flash(:error, "Pipeline restart failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reset_color_config", _params, socket) do
    defaults = %NervesView.Camera.Config{}
    {:noreply, assign(socket, color_config: defaults)}
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
      <% {tl_oldest, tl_newest} = scrubber_bounds(@scrubber_day, @retention, @tz_offset) %>

      <.card class="overflow-hidden">
        <:content class="p-0">
          <%!-- Video viewport with color-popover toggle --%>
          <div class="cam-vp cam-vp-full relative">
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
                <span class="cam-hud-t">{fmt_ts_local(@diag && @diag.last_frame_at, @tz_offset)}</span>
              </div>
            </div>

            <%!-- Color controls gear button --%>
            <button
              phx-click="toggle_color_popover"
              class="color-toggle-btn group"
              title="Color settings"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
                <path d="M12 3c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 14c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6-8c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zM4.93 6.34l2.83 2.83c.78.78 2.05.78 2.83 0l2.83-2.83c.78-.78.78-2.05 0-2.83L10.59.68c-.78-.78-2.05-.78-2.83 0L4.93 3.51c-.78.78-.78 2.05 0 2.83zm12.14 0l-2.83 2.83c-.78.78-.78 2.05 0 2.83l2.83 2.83c.78.78 2.05.78 2.83 0l2.83-2.83c.78-.78.78-2.05 0-2.83l-2.83-2.83c-.78-.78-2.05-.78-2.83 0zM6.34 19.07l2.83-2.83c.78-.78 2.05-.78 2.83 0l2.83 2.83c.78.78.78 2.05 0 2.83l-2.83 2.83c-.78.78-2.05.78-2.83 0l-2.83-2.83c-.78-.78-.78-2.05 0-2.83z"/>
              </svg>
            </button>

            <%!-- Color popover --%>
            <%= if @show_color_popover do %>
              <div class="color-popover-overlay" phx-click="toggle_color_popover"></div>
              <div class="color-popover" phx-click-away="toggle_color_popover">
                <div class="color-popover-header">
                  <h3 class="color-popover-title">Color Settings</h3>
                  <button
                    phx-click="toggle_color_popover"
                    class="color-popover-close"
                    aria-label="Close"
                  >&times;</button>
                </div>

                <form phx-change="update_color" phx-submit="apply_color_config" class="color-popover-body">
                  <%!-- AWB Mode --%>
                  <label class="color-field">
                    <span class="color-field-label">White Balance</span>
                    <select name="awb_mode" value={Atom.to_string(@color_config.awb_mode)} class="input input-sm w-full">
                      <option value="auto" selected={@color_config.awb_mode == :auto}>Auto (adaptive)</option>
                      <option value="indoor" selected={@color_config.awb_mode == :indoor}>Indoor (2800-4500K)</option>
                      <option value="daylight" selected={@color_config.awb_mode == :daylight}>Daylight (4500-6500K)</option>
                      <option value="cloudy" selected={@color_config.awb_mode == :cloudy}>Cloudy (~6500K)</option>
                      <option value="fluorescent" selected={@color_config.awb_mode == :fluorescent}>Fluorescent</option>
                      <option value="tungsten" selected={@color_config.awb_mode == :tungsten}>Tungsten</option>
                      <option value="incandescent" selected={@color_config.awb_mode == :incandescent}>Incandescent</option>
                    </select>
                  </label>

                  <%!-- Saturation --%>
                  <label class="color-field">
                    <span class="color-field-label">
                      Saturation <span class="color-field-val">{@color_config.saturation}</span>
                    </span>
                    <input type="range" name="saturation" min="0" max="2.0" step="0.1"
                      value={@color_config.saturation} class="color-slider" />
                  </label>

                  <%!-- Contrast --%>
                  <label class="color-field">
                    <span class="color-field-label">
                      Contrast <span class="color-field-val">{@color_config.contrast}</span>
                    </span>
                    <input type="range" name="contrast" min="0" max="2.0" step="0.1"
                      value={@color_config.contrast} class="color-slider" />
                  </label>

                  <%!-- Sharpness --%>
                  <label class="color-field">
                    <span class="color-field-label">
                      Sharpness <span class="color-field-val">{@color_config.sharpness}</span>
                    </span>
                    <input type="range" name="sharpness" min="0" max="2.0" step="0.1"
                      value={@color_config.sharpness} class="color-slider" />
                  </label>

                  <%!-- Exposure Mode --%>
                  <label class="color-field">
                    <span class="color-field-label">Exposure</span>
                    <select name="exposure_mode" value={Atom.to_string(@color_config.exposure_mode)} class="input input-sm w-full">
                      <option value="normal" selected={@color_config.exposure_mode == :normal}>Normal</option>
                      <option value="short" selected={@color_config.exposure_mode == :short}>Short (fast)</option>
                      <option value="long" selected={@color_config.exposure_mode == :long}>Long (bright)</option>
                    </select>
                  </label>

                  <div class="color-popover-actions">
                    <.button type="button" variant="ghost" size="sm" phx-click="reset_color_config">
                      Reset Defaults
                    </.button>
                    <.button type="submit" variant="primary" size="sm">
                      Apply &amp; Restart
                    </.button>
                  </div>
                </form>
              </div>
            <% end %>
          </div>

          <%!-- Day picker above the scrubber --%>
          <div class="cam-day-picker flex items-center gap-2 px-3 pt-2 text-xs">
            <span class="text-muted-foreground">Day:</span>
            <form phx-change="dvr:set_day" class="inline-flex">
              <input
                type="date"
                name="day"
                value={@scrubber_day_iso}
                class="input input-sm"
              />
            </form>
          </div>

          <%!-- Timeline scrubber --%>
          <div
            id={"tl-#{@camera.id}"}
            class="cam-tl"
            phx-hook="TimelineScrubber"
            phx-update="ignore"
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
            <span class="kv-k">Last Frame</span><span class="tabular-nums">{fmt_ts_local(@diag && @diag.last_frame_at, @tz_offset)}</span>
            <span class="kv-k">AWB</span><span>{@color_config.awb_mode} · sat={@color_config.saturation} con={@color_config.contrast} shp={@color_config.sharpness}</span>
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

  defp scrubber_bounds(day, retention, tz_offset_minutes)

  defp scrubber_bounds(nil, retention, _tz_offset_minutes) do
    now = System.system_time(:second)
    fallback_start = now - 24 * 3600

    {ret_oldest, ret_newest} =
      case retention do
        {a, b} -> {a, b}
        _ -> {fallback_start, now}
      end

    {max(fallback_start, ret_oldest), min(now, ret_newest)}
  end

  defp scrubber_bounds(day, retention, tz_offset_minutes) do
    {:ok, local_start} = DateTime.new(day, ~T[00:00:00])
    {:ok, local_end} = DateTime.new(day, ~T[23:59:59])

    day_start_utc = DateTime.add(local_start, -tz_offset_minutes * 60, :second)
    day_end_utc = DateTime.add(local_end, -tz_offset_minutes * 60, :second)

    day_start = DateTime.to_unix(day_start_utc)
    day_end = DateTime.to_unix(day_end_utc)
    now = System.system_time(:second)

    {ret_oldest, ret_newest} =
      case retention do
        {a, b} -> {a, b}
        _ -> {day_start, now}
      end

    oldest = max(day_start, ret_oldest)
    newest = min(min(day_end, now), ret_newest)
    {oldest, newest}
  end

  defp compute_playback_base_and_offset(camera_id, from_ts) do
    segs = NervesView.DVR.SegmentIndex.segments_for(camera_id, from_ts, from_ts + 600)

    case segs do
      [] -> {from_ts, 0}
      [first | _] -> {first.started_at, max(0, from_ts - first.started_at)}
    end
  end

  defp ensure_int(v) when is_integer(v), do: v
  defp ensure_int(v) when is_binary(v), do: String.to_integer(v)

  defp parse_param_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> Float.round(f, 1)
      :error -> default
    end
  end

  defp parse_param_float(_, default), do: default

  defp parse_known_atom(value, allowed, default) when is_binary(value) do
    if value in allowed, do: String.to_existing_atom(value), else: default
  end

  defp parse_known_atom(_, _allowed, default), do: default
end
