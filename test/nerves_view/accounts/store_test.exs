defmodule NervesView.Accounts.StoreTest do
  use ExUnit.Case, async: false

  alias NervesView.Accounts.Store

  setup do
    :ok = Store.clear()
    :ok
  end

  test "register and authenticate user" do
    assert {:ok, user} = Store.register("Admin@Example.com", "strongpass", :admin)
    assert user.email == "admin@example.com"
    assert user.role == :admin

    assert {:ok, auth_user} = Store.authenticate("admin@example.com", "strongpass")
    assert auth_user.id == user.id
  end

  test "rejects duplicate email and short password" do
    assert {:ok, _} = Store.register("viewer@example.com", "password123", :viewer)
    assert {:error, :email_taken} = Store.register("viewer@example.com", "password123", :viewer)
    assert {:error, :password_too_short} = Store.register("x@example.com", "short", :viewer)
  end
end
