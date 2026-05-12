defmodule NervesViewWeb.Plugs.RootRedirect do
  use NervesViewWeb, :controller

  def init(opts), do: opts

  def call(conn, _opts) do
    to =
      cond do
        conn.assigns[:current_user] -> ~p"/dashboard"
        NervesView.first_boot?() -> ~p"/setup"
        true -> ~p"/login"
      end

    conn
    |> redirect(to: to)
    |> halt()
  end
end
