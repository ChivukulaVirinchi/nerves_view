import Config

config :nerves_view, NervesViewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_please_change_me_1234567890_abcdefghijklmnopqrstuvwxyz_1234",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:nerves_view, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:nerves_view, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/nerves_view_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
