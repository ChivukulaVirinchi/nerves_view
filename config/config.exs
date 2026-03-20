# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1774002223"

config :nerves_view,
  ecto_repos: [],
  mode: :standalone

config :libcluster,
  topologies: [
    nervesview_local: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"nervesview@127.0.0.1"]]
    ]
  ]

config :phoenix, :json_library, Jason

config :nerves_view, NervesViewWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NervesViewWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: NervesView.PubSub,
  live_view: [signing_salt: "nervesviewsalt"]

config :esbuild,
  version: "0.25.11",
  nerves_view: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.13",
  nerves_view: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/app.css),
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
