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
        NervesViewWeb.Endpoint,
        {Registry, keys: :unique, name: NervesView.Streaming.Registry},
        {NervesView.Streaming.PeerSupervisor, []},

        # Shared runtime services
        {NervesView.Camera.Registry, []},
        {NervesView.Pipeline.Manager, []},
        {NervesView.Streaming.Signaling, []},
        {NervesView.Recording.Store, []},
        {NervesView.Cluster.NodeRegistry, []},
        {NervesView.Network.Discovery, []},
        {NervesView.Accounts.Store, []},
        {NervesView.Accounts.SessionStore, []},
        {NervesView.Alerts, []}
      ] ++ target_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesView.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NervesViewWeb.Endpoint.config_change(changed, removed)
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
