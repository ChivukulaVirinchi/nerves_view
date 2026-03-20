defmodule NervesViewWeb.Plugs.RateLimitTest do
  use NervesViewWeb.ConnCase, async: false

  alias NervesView.Security.RateLimiter

  setup do
    :ok = RateLimiter.clear()
    :ok
  end

  test "login endpoint eventually rate limits", %{conn: conn} do
    for _ <- 1..10 do
      _ = post(conn, ~p"/login", %{"email" => "none@example.com", "password" => "bad"})
    end

    conn = post(conn, ~p"/login", %{"email" => "none@example.com", "password" => "bad"})
    assert redirected_to(conn) == ~p"/login"
  end
end
