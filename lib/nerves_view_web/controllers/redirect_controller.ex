defmodule NervesViewWeb.RedirectController do
  use NervesViewWeb, :controller

  alias NervesViewWeb.RegistrationController

  def home(conn, _params) do
    cond do
      conn.assigns[:current_user] -> redirect(conn, to: ~p"/dashboard")
      RegistrationController.first_boot?() -> redirect(conn, to: ~p"/setup")
      true -> redirect(conn, to: ~p"/login")
    end
  end
end
