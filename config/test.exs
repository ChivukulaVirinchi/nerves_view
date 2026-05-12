import Config

config :nerves_view, NervesViewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_please_change_me_1234567890_abcdefghijklmnopqrstuvwxyz_1234",
  server: false,
  adapter: Bandit.PhoenixAdapter,
  live_view: [signing_salt: "nervesviewsalt"]

# Isolate test data from dev — tests call Store.clear() which would
# otherwise wipe your dev accounts and sessions.
config :nerves_view,
  persistence_dir: "tmp/test_persistence",
  recordings_path: "tmp/test_recordings"

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
