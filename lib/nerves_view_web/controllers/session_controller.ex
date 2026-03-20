defmodule NervesViewWeb.SessionController do
  use NervesViewWeb, :controller

  alias NervesView
  alias NervesViewWeb.UserAuth

  def create(conn, %{"email" => email, "password" => password} = params) do
    opts = if Map.get(params, "remember_me") == "true", do: [remember_me: true], else: []

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
end
