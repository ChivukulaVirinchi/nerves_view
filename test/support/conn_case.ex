defmodule NervesViewWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint NervesViewWeb.Endpoint

      use NervesViewWeb, :verified_routes
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      @doc "Sign a handoff token for controller auth tests."
      def auth_handoff_token(user_id) do
        Phoenix.Token.sign(NervesViewWeb.Endpoint, "auth_handoff", user_id)
      end

      @doc "Log in via POST with a valid handoff token."
      def login_via_post(conn, email, password) do
        {:ok, %{user: user}} = NervesView.login(email, password)
        token = auth_handoff_token(user.id)
        post(conn, ~p"/login", %{"user" => %{"handoff_token" => token}})
      end

      @doc "Register + login via POST with a valid handoff token."
      def register_via_post(conn, email, password) do
        role = if NervesView.first_boot?(), do: :admin, else: :viewer
        {:ok, user} = NervesView.register_user(email, password, role)
        token = auth_handoff_token(user.id)
        post(conn, ~p"/register", %{"user" => %{"handoff_token" => token}})
      end
    end
  end

  setup _tags do
    :ok = NervesView.Security.RateLimiter.clear()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
