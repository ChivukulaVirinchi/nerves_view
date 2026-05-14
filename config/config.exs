# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

if config_env() == :dev and Mix.target() != :host and "phx.server" in System.argv() do
  Mix.raise("""
  mix phx.server must run with MIX_TARGET=host.

  Run:
      MIX_TARGET=host mix phx.server

  Target builds are for firmware/upload/burn and can start target-only networking
  or cross-compile native dependencies that cannot run on this machine.
  """)
end

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1774002223"

config :nerves_view,
  ecto_repos: [NervesView.Repo],
  mode: :standalone,
  recordings_path: "tmp/recordings",
  persistence_dir: "tmp/persistence",
  recording_segment_duration: 6,
  recording_retention_hours: 720,
  ice_servers: [%{urls: "stun:stun.l.google.com:19302"}],
  # Display timezone offset (minutes east of UTC). IST = 330. Set on the
  # firmware install; everything in the UI is rendered against this. One
  # source of truth — no browser-detection dance, no LiveSocket race.
  # Change here + rebuild firmware to deploy in a different zone.
  tz_offset_minutes: 330

config :nerves_view, NervesView.Repo,
  database: "tmp/nerves_view.db",
  journal_mode: :wal,
  busy_timeout: 5_000,
  pool_size: 5

config :libcluster, topologies: []

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
