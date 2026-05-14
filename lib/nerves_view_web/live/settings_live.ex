defmodule NervesViewWeb.SettingsLive do
  use NervesViewWeb, :live_view

  import NervesViewWeb.Helpers, only: [fmt_ts: 2]

  alias NervesView.CameraParams

  @impl true
  def mount(_params, _session, socket) do
    changeset = CameraParams.changeset()

    {:ok,
     socket
     |> assign(page_title: "Settings")
     |> assign(cameras: NervesView.list_cameras())
     |> assign(diagnostics: NervesView.camera_diagnostics())
     |> assign_cam_form(changeset)
     |> assign(node_info: node_info())
     |> assign(invite_url: nil)}
  end

  def handle_event("generate_invite", _, socket) do
    token = NervesView.generate_invite_token()
    path = ~p"/register?token=#{token}"
    url = NervesViewWeb.Endpoint.url() <> path
    {:noreply, assign(socket, invite_url: url)}
  end

  @impl true
  def handle_event("validate_cam", %{"camera" => params}, socket) do
    changeset =
      params
      |> CameraParams.changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign_cam_form(socket, changeset)}
  end

  def handle_event("add_camera", %{"camera" => params}, socket) do
    changeset = CameraParams.changeset(params)

    if changeset.valid? do
      attrs = Ecto.Changeset.apply_changes(changeset)
      source_type = String.to_existing_atom(attrs.source_type)

      case NervesView.register_camera(%{
             id: attrs.id,
             name: attrs.name,
             source_type: source_type,
             status: :streaming,
             device_path: attrs.device_path
           }) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Camera \"#{attrs.name}\" added")
           |> assign(cameras: NervesView.list_cameras())
           |> assign(diagnostics: NervesView.camera_diagnostics())
           |> assign_cam_form(CameraParams.changeset())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add camera")}
      end
    else
      {:noreply, assign_cam_form(socket, %{changeset | action: :validate})}
    end
  end

  def handle_event("remove_camera", %{"id" => id}, socket) do
    :ok = NervesView.remove_camera(id)

    {:noreply,
     socket
     |> put_flash(:info, "Camera removed")
     |> assign(cameras: NervesView.list_cameras())
     |> assign(diagnostics: NervesView.camera_diagnostics())}
  end

  def handle_event("restart_camera", %{"id" => id}, socket) do
    case NervesView.restart_camera_pipeline(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pipeline restarted")
         |> assign(diagnostics: NervesView.camera_diagnostics())}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not restart pipeline")
         |> assign(diagnostics: NervesView.camera_diagnostics())}
    end
  end

  def handle_event("clear_recordings", params, socket) do
    confirmed? =
      params["confirm_delete"] == "true" and
        String.trim(params["confirm_phrase"] || "") == "DELETE RECORDINGS"

    if confirmed? do
      case NervesView.clear_all_recordings() do
        {:ok, %{files: files, bytes: bytes}} ->
          {:noreply,
           socket
           |> put_flash(:info, "Deleted #{files} recording files (#{format_bytes(bytes)}).")
           |> assign(diagnostics: NervesView.camera_diagnostics())}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not clear recordings: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Confirm the checkbox and type DELETE RECORDINGS.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="pg-title">Settings</h1>
      <p class="pg-sub mb-5">System configuration and camera management</p>

      <.tabs id="stabs" default_value="cameras">
        <:tab value="cameras">Cameras</:tab>
        <:tab value="system">System</:tab>
        <:tab value="diagnostics">Diagnostics</:tab>

        <%!-- ─ Cameras ─ --%>
        <:panel value="cameras">
          <.card class="mt-4">
            <:header>
              <h3 class="font-display font-semibold text-sm">Add Camera Source</h3>
              <p class="text-xs text-muted-foreground">Pipeline auto-starts on registration.</p>
            </:header>
            <:content>
              <.form for={@cam_form} id="cam-form" phx-change="validate_cam" phx-submit="add_camera" class="grid gap-4">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <.input field={@cam_form[:id]} label="Camera ID" required
                    placeholder="cam-front" />
                  <.input field={@cam_form[:name]} label="Display Name" required
                    placeholder="Front Door" />
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <.input field={@cam_form[:source_type]} type="select" label="Source"
                    options={[{"libcamera", "libcamera"}, {"rtsp", "rtsp"}]} />
                  <.input field={@cam_form[:device_path]} label="Device Path" required
                    placeholder="/dev/video0 or rtsp://camera/stream" />
                </div>
                <div><.button type="submit">Add Camera</.button></div>
              </.form>
            </:content>
          </.card>

          <%= if @cameras != [] do %>
            <div class="grid gap-3 mt-4 sm:grid-cols-2 lg:grid-cols-3">
              <%= for cam <- @cameras do %>
                <% d = Enum.find(@diagnostics, &(&1.camera_id == cam.id)) %>
                <% ok? = d && d.healthy %>
                <.card>
                  <:content>
                    <div class="flex items-center gap-2 mb-3">
                      <span class={"dot #{if ok?, do: "dot-live", else: "dot-dead"}"} />
                      <h3 class="font-display font-semibold text-sm">{cam.name}</h3>
                      <.badge variant={if ok?, do: "success", else: "secondary"} class="ml-auto">
                        {if ok?, do: "Online", else: "Offline"}
                      </.badge>
                    </div>
                    <div class="kv mb-3">
                      <span class="kv-k">ID</span><span>{cam.id}</span>
                      <span class="kv-k">Source</span><span>{cam.source_type}</span>
                      <span class="kv-k">Path</span><span>{cam.device_path || "—"}</span>
                    </div>
                    <div class="flex gap-2">
                      <.button variant="outline" size="sm" phx-click="restart_camera" phx-value-id={cam.id}>Restart</.button>
                      <.button variant="destructive" size="sm" phx-click="remove_camera" phx-value-id={cam.id}>Remove</.button>
                    </div>
                  </:content>
                </.card>
              <% end %>
            </div>
          <% else %>
            <.empty class="mt-4" variant="outline">
              <:title>No cameras</:title>
              <:description>Use the form above to register a source.</:description>
            </.empty>
          <% end %>
        </:panel>

        <%!-- ─ System ─ --%>
        <:panel value="system">
          <div class="grid gap-3 mt-4 grid-cols-2 sm:grid-cols-3">
            <.card><:content>
              <p class="stat-num">{@node_info.mode}</p>
              <p class="stat-lbl">Mode</p>
            </:content></.card>
            <.card><:content>
              <p class="stat-num">{length(@cameras)}</p>
              <p class="stat-lbl">Cameras</p>
            </:content></.card>
            <.card><:content>
              <p class="stat-num">{@node_info.otp_apps}</p>
              <p class="stat-lbl">OTP Apps</p>
            </:content></.card>
          </div>

          <.card class="mt-4">
            <:header><h3 class="font-display font-semibold text-sm">Invite a viewer</h3></:header>
            <:content>
              <p class="pg-sub mb-3">
                Generate a one-time link to let someone else create an account. Valid for 24 hours.
              </p>
              <.button phx-click="generate_invite" variant="outline">
                Generate invite link
              </.button>
              <%= if @invite_url do %>
                <div class="mt-3 p-2 rounded bg-muted">
                  <div class="font-mono text-xs break-all">{@invite_url}</div>
                  <p class="pg-sub mt-2 text-xs">Copy and send this link. It expires in 24 hours.</p>
                </div>
              <% end %>
            </:content>
          </.card>

          <.card class="mt-4">
            <:header><h3 class="font-display font-semibold text-sm">Node Details</h3></:header>
            <:content>
              <div class="kv">
                <span class="kv-k">Hostname</span><span>{@node_info.hostname}</span>
                <span class="kv-k">Node</span><span>{@node_info.node_name}</span>
                <span class="kv-k">Arch</span><span>{@node_info.arch}</span>
                <span class="kv-k">OTP</span><span>{@node_info.otp_release}</span>
                <span class="kv-k">Elixir</span><span>{@node_info.elixir_version}</span>
                <span class="kv-k">Network</span><span>mDNS active · port 4000</span>
              </div>
            </:content>
          </.card>

          <.card class="mt-4 border-destructive/40">
            <:header><h3 class="font-display font-semibold text-sm text-destructive">Danger Zone</h3></:header>
            <:content>
              <.form for={%{}} phx-submit="clear_recordings" class="grid gap-3">
                <label class="flex items-start gap-2 text-sm">
                  <input type="checkbox" name="confirm_delete" value="true" class="mt-1" />
                  <span>Delete all recorded video and reset DVR indexes.</span>
                </label>
                <input
                  type="text"
                  name="confirm_phrase"
                  class="input"
                  placeholder="DELETE RECORDINGS"
                  autocomplete="off"
                />
                <div>
                  <.button type="submit" variant="destructive">
                    Clear all recordings
                  </.button>
                </div>
              </.form>
            </:content>
          </.card>
        </:panel>

        <%!-- ─ Diagnostics ─ --%>
        <:panel value="diagnostics">
          <%= if @diagnostics == [] do %>
            <.empty class="mt-4" variant="outline">
              <:title>No diagnostics</:title>
              <:description>Add a camera to see health data.</:description>
            </.empty>
          <% else %>
            <div class="grid gap-3 mt-4">
              <%= for d <- @diagnostics do %>
                <.card>
                  <:content>
                    <div class="flex items-center gap-2 mb-3">
                      <span class={"dot #{if d.healthy, do: "dot-live", else: "dot-dead"}"} />
                      <h3 class="font-display font-semibold text-sm">{d.camera_name}</h3>
                      <.badge variant={if d.healthy, do: "success", else: "destructive"} class="ml-auto">
                        {if d.healthy, do: "Healthy", else: "Unhealthy"}
                      </.badge>
                    </div>
                    <div class="kv">
                      <span class="kv-k">Camera</span><span>{d.camera_id}</span>
                      <span class="kv-k">Backend</span><span>{d.source_type}</span>
                      <span class="kv-k">Device</span><span>{d.device_path || "—"}</span>
                      <span class="kv-k">Pipeline</span><span>{d.pipeline_status || "stopped"}</span>
                      <span class="kv-k">Source</span><span>{d.source_path || "—"}</span>
                      <span class="kv-k">Last Frame</span><span class="tabular-nums">{fmt_ts(d.last_frame_at, "%Y-%m-%d %H:%M:%S")}</span>
                      <%= if d.last_error do %>
                        <span class="kv-k">Error</span>
                        <span class="text-destructive">{inspect(d.last_error)}</span>
                      <% end %>
                    </div>
                  </:content>
                </.card>
              <% end %>
            </div>
          <% end %>
        </:panel>
      </.tabs>
    </div>
    """
  end

  defp assign_cam_form(socket, changeset) do
    assign(socket, :cam_form, to_form(changeset, as: "camera"))
  end

  defp node_info do
    %{
      mode: NervesView.Mode.current(),
      hostname: node() |> Atom.to_string() |> String.split("@") |> List.last(),
      node_name: node(),
      arch: :erlang.system_info(:system_architecture) |> to_string(),
      otp_release: :erlang.system_info(:otp_release) |> to_string(),
      elixir_version: System.version(),
      otp_apps: length(Application.started_applications())
    }
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1_048_576,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
