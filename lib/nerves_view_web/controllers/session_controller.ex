defmodule NervesViewWeb.SessionController do
  use NervesViewWeb, :controller

  alias NervesView.Accounts.SessionStore
  alias NervesViewWeb.UserAuth

  @handoff_max_age 30

  @doc """
  Creates a session. Called via phx-trigger-action after LiveView
  validates and authenticates the user. The LiveView passes a signed
  handoff token so we don't re-authenticate here.
  """
  def create(conn, %{"user" => %{"handoff_token" => token} = params}) when is_binary(token) do
    case Phoenix.Token.verify(NervesViewWeb.Endpoint, "auth_handoff", token,
           max_age: @handoff_max_age
         ) do
      {:ok, user_id} ->
        {:ok, session} = SessionStore.create(user_id, remember_opts(params))

        conn
        |> put_session(UserAuth.session_key(), session.token)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/dashboard")

      {:error, _} ->
        conn
        |> put_flash(:error, "Session expired. Please try again.")
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
  defp remember_opts(_), do: []
end
