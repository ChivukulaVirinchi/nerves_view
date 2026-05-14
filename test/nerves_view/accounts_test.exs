defmodule NervesView.AccountsTest do
  use ExUnit.Case, async: false

  alias NervesView.Accounts

  setup do
    :ok = Accounts.clear()
    :ok
  end

  test "register and authenticate user" do
    assert {:ok, user} = Accounts.register("Admin@Example.com", "strongpass", :admin)
    assert user.email == "admin@example.com"
    assert user.role == :admin

    assert {:ok, auth_user} = Accounts.authenticate("admin@example.com", "strongpass")
    assert auth_user.id == user.id
  end

  test "rejects duplicate email and short password" do
    assert {:ok, _} = Accounts.register("viewer@example.com", "password123", :viewer)

    assert {:error, :email_taken} =
             Accounts.register("viewer@example.com", "password123", :viewer)

    assert {:error, :password_too_short} = Accounts.register("x@example.com", "short", :viewer)
  end

  test "authenticate rejects wrong password" do
    assert {:ok, _} = Accounts.register("wrong@example.com", "password123", :viewer)
    assert {:error, :invalid_credentials} = Accounts.authenticate("wrong@example.com", "nope")
  end

  test "authenticate rejects unknown email" do
    assert {:error, :invalid_credentials} =
             Accounts.authenticate("nobody@example.com", "whatever")
  end

  test "rejects invalid email format" do
    assert {:error, :invalid_email} = Accounts.register("not-an-email", "password123", :viewer)
  end

  test "list_users returns registered users sorted by email" do
    {:ok, _} = Accounts.register("b@example.com", "password123", :viewer)
    {:ok, _} = Accounts.register("a@example.com", "password123", :admin)

    emails = Accounts.list_users() |> Enum.map(& &1.email)
    assert emails == ["a@example.com", "b@example.com"]
  end
end
