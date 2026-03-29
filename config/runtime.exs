import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4000")

  secret_key_base =
    case System.get_env("SECRET_KEY_BASE") do
      nil -> raise "SECRET_KEY_BASE is required in production"
      "" -> raise "SECRET_KEY_BASE is required in production"
      value -> value
    end

  config :nerves_view, NervesViewWeb.Endpoint,
    server: true,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
