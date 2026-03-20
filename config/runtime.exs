import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :nerves_view, NervesViewWeb.Endpoint,
    server: true,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base:
      System.get_env("SECRET_KEY_BASE") ||
        "prod_secret_key_base_please_replace_for_real_deployment_123456_abcdefghijklmnopqrstuvwxyz_1234"
end

config :nerves_view, NervesViewWeb.Endpoint, force_ssl: [hsts: true]
