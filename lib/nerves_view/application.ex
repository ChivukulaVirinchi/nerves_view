defmodule NervesView.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: NervesView.PubSub},
        {Cluster.Supervisor,
         [Application.get_env(:libcluster, :topologies, []), [name: NervesView.ClusterSupervisor]]},
        NervesViewWeb.Endpoint,
        {Registry, keys: :unique, name: NervesView.Streaming.Registry},
        {NervesView.Streaming.PeerSupervisor, []},

        # Shared runtime services
        {NervesView.Camera.Registry, []},
        {NervesView.Pipeline.Manager, []},
        {NervesView.Streaming.Signaling, []},
        {NervesView.Recording.Store, []},
        {NervesView.Storage.Manager, []},
        {NervesView.Security.RateLimiter, []},
        {NervesView.Cluster.NodeRegistry, []},
        {NervesView.Cluster.Heartbeat, []},
        {NervesView.Network.Discovery, []},
        {NervesView.Accounts.Store, []},
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
end
