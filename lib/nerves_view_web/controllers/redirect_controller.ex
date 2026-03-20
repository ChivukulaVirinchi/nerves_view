defmodule NervesViewWeb.RedirectController do
  use NervesViewWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/login")
    end
  end
end
