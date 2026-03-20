defmodule NervesView.Security.RateLimiterTest do
  use ExUnit.Case, async: false

  alias NervesView.Security.RateLimiter

  setup do
    :ok = RateLimiter.clear()
    :ok
  end

  test "allows up to limit and blocks after" do
    for n <- 1..3 do
      assert :ok =
               RateLimiter.check("auth:127.0.0.1",
                 now: 100 + n,
                 max_attempts: 3,
                 window_seconds: 60
               )
    end

    assert {:error, :rate_limited} =
             RateLimiter.check("auth:127.0.0.1", now: 105, max_attempts: 3, window_seconds: 60)
  end
end
