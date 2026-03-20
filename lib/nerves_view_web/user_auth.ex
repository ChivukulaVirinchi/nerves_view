defmodule NervesViewWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts.Store

  @session_key "user_token"

  def fetch_current_user(conn, _opts) do
    token = get_session(conn, @session_key)
    user = user_from_token(token)

    conn
    |> assign(:current_user, user)
    |> assign(:user_token, token)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Please log in to continue.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/dashboard")
      |> halt()
    else
      conn
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    token = Map.get(session, @session_key)

    case user_from_token(token) do
      nil ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Please log in to continue.")
         |> Phoenix.LiveView.redirect(to: "/login")}

      user ->
        {:cont,
         socket
         |> Phoenix.Component.assign(:current_user, user)
         |> Phoenix.Component.assign(:user_token, token)}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    token = Map.get(session, @session_key)

    {:cont,
     socket
     |> Phoenix.Component.assign(:current_user, user_from_token(token))
     |> Phoenix.Component.assign(:user_token, token)}
  end

  def session_key, do: @session_key

  defp user_from_token(nil), do: nil

  defp user_from_token(token) when is_binary(token) do
    with {:ok, session} <- SessionStore.fetch(token),
         {:ok, user} <- Store.get_user(session.user_id) do
      user
    else
      _ -> nil
    end
  end
end
