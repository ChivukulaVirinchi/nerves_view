import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4000")

  secret_key_base =
    case System.get_env("SECRET_KEY_BASE") do
      value when is_binary(value) and value != "" -> value
      _ -> "nerves_view_fallback_secret_key_base_set_SECRET_KEY_BASE_for_prod"
    end

  config :nerves_view, NervesViewWeb.Endpoint,
    server: true,
    http: [ip: {0, 0, 0, 0}, port: port],
    check_origin: false,
    secret_key_base: secret_key_base
end
