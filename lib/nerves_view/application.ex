defmodule NervesView.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = maybe_configure_target_logger()
    :ok = ensure_repo_dir!()
    :ok = migrate_repo!()
    :ok = maybe_bootstrap_wifi()

    children =
      [
        NervesView.Repo,
        {Phoenix.PubSub, name: NervesView.PubSub},
        {Cluster.Supervisor,
         [Application.get_env(:libcluster, :topologies, []), [name: NervesView.ClusterSupervisor]]},
        NervesViewWeb.Endpoint,
        {Registry, keys: :unique, name: NervesView.Streaming.Registry},
        {NervesView.Streaming.PeerSupervisor, []},

        # Pipeline services — rest_for_one ensures downstream processes restart
        # if an upstream dependency (e.g., StreamBus) crashes.
        %{
          id: NervesView.PipelineSupervisor,
          type: :supervisor,
          start:
            {Supervisor, :start_link,
             [
               [
                 {NervesView.Camera.Registry, []},
                 {NervesView.Pipeline.StreamBus, []},
                 {NervesView.Pipeline.Manager, []},
                 {NervesView.Streaming.Signaling, []}
               ],
               [strategy: :rest_for_one, name: NervesView.PipelineSupervisor]
             ]}
        },
        {NervesView.Recording.Store, []},
        {NervesView.Recording.PlaylistManager, []},
        {NervesView.Recording.SegmentReaper, []},
        {NervesView.DVR.SegmentIndex, []},
        {NervesView.Storage.Manager, []},
        {NervesView.Security.RateLimiter, []},
        {NervesView.Cluster.NodeRegistry, []},
        {NervesView.Cluster.Heartbeat, []},
        {NervesView.Network.Discovery, []},
        {NervesView.Accounts.SessionStore, []},
        {NervesView.Alerts, []}
      ] ++ target_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesView.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = ok ->
        :ok = ensure_default_camera_started()
        ok

      other ->
        other
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    NervesViewWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp ensure_default_camera_started do
    if libcamera_available?() do
      # Load CSI camera sensor kernel modules that may not auto-load
      for mod <- ~w(ov5647 imx219 imx477 imx708) do
        safe_cmd("modprobe", [mod])
      end

      # Wait for the sensor to finish probing after modprobe
      await_camera_sensor()
    end

    cameras = NervesView.list_cameras()

    if cameras == [] do
      _ =
        NervesView.register_camera(%{
          id: "cam-local",
          name: "Local Camera",
          source_type: :libcamera,
          status: :streaming,
          device_path: "/dev/video0"
        })
    end

    Enum.each(NervesView.list_cameras(), &NervesView.start_camera_pipeline(&1.id))
    :ok
  end

  defp libcamera_available?, do: System.find_executable("libcamera-vid") != nil

  defp safe_cmd(cmd, args) do
    case System.find_executable(cmd) do
      nil -> :ok
      _ -> System.cmd(cmd, args, stderr_to_stdout: true)
    end
  rescue
    _ -> :ok
  end

  defp await_camera_sensor(attempts \\ 10)
  defp await_camera_sensor(0), do: :ok

  defp await_camera_sensor(attempts) do
    case safe_cmd("libcamera-vid", ["--list-cameras"]) do
      {output, 0} when output != "No cameras available!\n" ->
        :ok

      _ ->
        Process.sleep(500)
        await_camera_sensor(attempts - 1)
    end
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
        #
        # Starts a worker by calling: Host.Worker.start_link(arg)
        # {Host.Worker, arg},
      ]
    end
  else
    defp target_children() do
      [
        # Children for all targets except host
        # Starts a worker by calling: Target.Worker.start_link(arg)
        # {Target.Worker, arg},
      ]
    end
  end

  # On Nerves targets only, read /data/wifi.conf and configure wlan0 via
  # VintageNet so the Pi can auto-join home WiFi without rebuilding firmware.
  if Mix.target() == :host do
    defp maybe_bootstrap_wifi, do: :ok
    defp maybe_configure_target_logger, do: :ok
  else
    defp maybe_bootstrap_wifi, do: NervesView.Network.WiFiBootstrap.ensure_configured()

    defp maybe_configure_target_logger do
      if Code.ensure_loaded?(LoggerBackends) and Code.ensure_loaded?(RingLogger) do
        case LoggerBackends.add(RingLogger) do
          {:ok, _pid} -> :ok
          {:error, :already_present} -> :ok
          {:error, _reason} -> :ok
        end
      else
        :ok
      end
    end
  end

  defp ensure_repo_dir! do
    case Application.get_env(:nerves_view, NervesView.Repo)[:database] do
      nil ->
        :ok

      path ->
        File.mkdir_p!(Path.dirname(path))
        :ok
    end
  end

  # Boot-time migration: Nerves doesn't have `mix ecto.migrate` at runtime, so
  # we run pending migrations before the Repo starts accepting queries. SQLite
  # serialises writes, so this is safe to do during boot.
  defp migrate_repo! do
    if Code.ensure_loaded?(NervesView.Repo) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(NervesView.Repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    :ok
  end
end
