defmodule NervesViewWeb.SessionController do
  use NervesViewWeb, :controller

  alias NervesView
  alias NervesView.Security.RateLimiter
  alias NervesViewWeb.UserAuth

  def create(conn, %{"email" => email, "password" => password} = params) do
    with :ok <- rate_limit(conn, 10) do
      do_create(conn, email, password, params)
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many attempts, try again shortly.")
        |> redirect(to: ~p"/login")
    end
  end

  defp do_create(conn, email, password, params) do
    opts = remember_opts(params)

    case NervesView.login(email, password, opts) do
      {:ok, %{session: session}} ->
        conn
        |> put_session(UserAuth.session_key(), session.token)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/dashboard")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    case get_session(conn, UserAuth.session_key()) do
      nil -> :ok
      token -> NervesView.logout(token)
    end

    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out.")
    |> redirect(to: ~p"/login")
  end

  defp remember_opts(%{"remember_me" => "true"}), do: [remember_me: true]
  defp remember_opts(_params), do: []

  defp rate_limit(conn, max_attempts) do
    ip = to_string(:inet.ntoa(conn.remote_ip || {127, 0, 0, 1}))
    RateLimiter.check("auth:#{ip}", max_attempts: max_attempts, window_seconds: 60)
  end
end
