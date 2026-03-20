defmodule NervesViewWeb.Plugs.RateLimit do
  import Plug.Conn
  import Phoenix.Controller

  alias NervesView.Security.RateLimiter

  def init(opts), do: opts

  def call(conn, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 8)
    window = Keyword.get(opts, :window_seconds, 60)
    ip = to_string(:inet.ntoa(conn.remote_ip || {127, 0, 0, 1}))
    key = "auth:#{ip}"

    case RateLimiter.check(key, max_attempts: max_attempts, window_seconds: window) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many attempts, try again shortly.")
        |> redirect(to: "/login")
        |> halt()
    end
  end
end
