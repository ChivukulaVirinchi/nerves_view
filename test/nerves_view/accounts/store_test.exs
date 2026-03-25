defmodule NervesView.Accounts.StoreTest do
  use ExUnit.Case, async: false

  alias NervesView.Accounts.Store

  setup do
    File.rm_rf!("tmp/persistence")
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

  test "persists users to disk" do
    assert {:ok, user} = Store.register("persist@example.com", "password123", :viewer)
    path = NervesView.Persistence.path_for("users.term")
    assert File.exists?(path)
    assert {:ok, bin} = File.read(path)
    persisted = :erlang.binary_to_term(bin)
    assert persisted[user.id].email == "persist@example.com"
  end
end
