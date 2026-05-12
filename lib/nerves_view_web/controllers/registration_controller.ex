defmodule NervesViewWeb.RegistrationController do
  use NervesViewWeb, :controller

  alias NervesView.Accounts.SessionStore
  alias NervesViewWeb.UserAuth

  @handoff_max_age 30

  @doc """
  Creates a session after registration. Called via phx-trigger-action after
  LiveView validates and registers the user. The LiveView passes a signed
  handoff token so we don't re-register or re-authenticate here.
  """
  def create(conn, %{"user" => %{"handoff_token" => token}}) when is_binary(token) do
    case Phoenix.Token.verify(NervesViewWeb.Endpoint, "auth_handoff", token,
           max_age: @handoff_max_age
         ) do
      {:ok, user_id} ->
        {:ok, session} = SessionStore.create(user_id)

        conn
        |> put_session(UserAuth.session_key(), session.token)
        |> put_flash(:info, "Account created.")
        |> redirect(to: ~p"/dashboard")

      {:error, _} ->
        conn
        |> put_flash(:error, "Registration failed. Please try again.")
        |> redirect(to: ~p"/register")
    end
  end
end
