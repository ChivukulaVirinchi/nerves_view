import Config

config :logger, level: :info

config :nerves_view, NervesViewWeb.Endpoint,
  url: [host: "nervesview.local", port: 80],
  cache_static_manifest: "priv/static/cache_manifest.json"
