defmodule NervesViewWeb.SettingsLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Settings")
     |> assign(cameras: NervesView.list_cameras())
     |> assign(diagnostics: NervesView.camera_diagnostics())
     |> assign(form: default_camera_form())}
  end

  @impl true
  def handle_event("add_camera", %{"camera" => params}, socket) do
    attrs = %{
      id: String.trim(params["id"] || ""),
      name: String.trim(params["name"] || ""),
      source_type: parse_source_type(params["source_type"]),
      status: :streaming,
      device_path: String.trim(params["device_path"] || "")
    }

    case NervesView.register_camera(attrs) do
      {:ok, _camera} ->
        {:noreply,
         socket
         |> put_flash(:info, "Camera added")
         |> assign(cameras: NervesView.list_cameras())
         |> assign(diagnostics: NervesView.camera_diagnostics())
         |> assign(form: default_camera_form())}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add camera")}
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
      {:ok, _pipeline} ->
        {:noreply,
         socket
         |> put_flash(:info, "Camera pipeline restarted")
         |> assign(diagnostics: NervesView.camera_diagnostics())}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not restart camera pipeline")
         |> assign(diagnostics: NervesView.camera_diagnostics())}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>Settings</h1>
      <p class="muted">System settings UI placeholder (Phase 7).</p>

      <div class="card-list">
        <article class="camera-card">
          <h2>Node mode</h2>
          <p>{NervesView.Mode.current()}</p>
        </article>

        <article class="camera-card">
          <h2>Network</h2>
          <p>mDNS broadcast enabled</p>
        </article>
      </div>

      <h2>Add camera</h2>
      <form phx-submit="add_camera" class="auth-form camera-form">
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <label for="camera_id">ID</label>
        <input id="camera_id" name="camera[id]" value={@form.id} required />

        <label for="camera_name">Name</label>
        <input id="camera_name" name="camera[name]" value={@form.name} required />

        <label for="camera_source">Source type</label>
        <select id="camera_source" name="camera[source_type]">
          <option value="libcamera" selected={@form.source_type == "libcamera"}>libcamera</option>
          <option value="v4l2" selected={@form.source_type == "v4l2"}>v4l2</option>
          <option value="rtsp" selected={@form.source_type == "rtsp"}>rtsp</option>
        </select>

        <label for="camera_path">Device path / URL</label>
        <input id="camera_path" name="camera[device_path]" value={@form.device_path} required />

        <button type="submit">Add camera</button>
      </form>

      <h2>Configured cameras</h2>
      <div class="card-list">
        <%= for camera <- @cameras do %>
          <article class="camera-card">
            <h3>{camera.name}</h3>
            <p>ID: {camera.id}</p>
            <p>Type: {camera.source_type}</p>
            <p>Path: {camera.device_path || "n/a"}</p>
            <button phx-click="remove_camera" phx-value-id={camera.id}>Remove</button>
            <button phx-click="restart_camera" phx-value-id={camera.id}>Restart pipeline</button>
          </article>
        <% end %>
      </div>

      <h2>Diagnostics</h2>
      <div class="card-list">
        <%= for diag <- @diagnostics do %>
          <article class="camera-card">
            <h3>{diag.camera_name}</h3>
            <p>Camera ID: {diag.camera_id}</p>
            <p>Backend: {diag.source_type}</p>
            <p>Path: {diag.device_path || "n/a"}</p>
            <p>Pipeline: {diag.pipeline_status || :stopped}</p>
            <p>Healthy: {if diag.healthy, do: "yes", else: "no"}</p>
            <p>Last frame: {diag.last_frame_at || "n/a"}</p>
            <p>Runtime source: {diag.source_path || "n/a"}</p>
            <p :if={diag.last_error}>Last error: {inspect(diag.last_error)}</p>
          </article>
        <% end %>

        <%= if @diagnostics == [] do %>
          <article class="camera-card empty">
            <h3>No diagnostics yet</h3>
            <p>Add a camera to see runtime health details.</p>
          </article>
        <% end %>
      </div>
    </section>
    """
  end

  defp parse_source_type("libcamera"), do: :libcamera
  defp parse_source_type("v4l2"), do: :v4l2
  defp parse_source_type("rtsp"), do: :rtsp
  defp parse_source_type(_), do: :libcamera

  defp default_camera_form do
    %{id: "", name: "", source_type: "libcamera", device_path: "/dev/video0"}
  end
end
