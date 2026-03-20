defmodule NervesViewWeb.RegistrationController do
  use NervesViewWeb, :controller

  alias NervesView
  alias NervesViewWeb.UserAuth

  def create(conn, %{"email" => email, "password" => password}) do
    role = registration_role()

    with {:ok, _user} <- NervesView.register_user(email, password, role),
         {:ok, %{session: session}} <- NervesView.login(email, password) do
      conn
      |> put_session(UserAuth.session_key(), session.token)
      |> put_flash(:info, "Account created.")
      |> redirect(to: ~p"/dashboard")
    else
      {:error, :email_taken} ->
        conn
        |> put_flash(:error, "Email already registered.")
        |> redirect(to: ~p"/register")

      {:error, :password_too_short} ->
        conn
        |> put_flash(:error, "Password must be at least 8 characters.")
        |> redirect(to: ~p"/register")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Unable to create account.")
        |> redirect(to: ~p"/register")
    end
  end

  defp registration_role do
    if NervesView.list_users() == [] do
      :admin
    else
      :viewer
    end
  end
end
