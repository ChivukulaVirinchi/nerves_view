defmodule NervesView.Accounts.SessionStoreTest do
  use ExUnit.Case, async: false

  alias NervesView.Accounts.SessionStore

  setup do
    File.rm_rf!("tmp/persistence")
    :ok = SessionStore.clear()
    :ok
  end

  test "creates and validates session" do
    now = 1_700_000_100
    assert {:ok, session} = SessionStore.create("user-1", now: now)
    assert is_binary(session.token)
    assert {:ok, fetched} = SessionStore.fetch(session.token, now)
    assert fetched.user_id == "user-1"
  end

  test "remember_me creates longer lived session" do
    now = 1_700_000_200
    assert {:ok, normal} = SessionStore.create("user-1", now: now)
    assert {:ok, remembered} = SessionStore.create("user-1", remember_me: true, now: now)
    assert remembered.expires_at > normal.expires_at
  end

  test "prunes expired sessions" do
    base = 1_700_000_000
    assert {:ok, s1} = SessionStore.create("user-1", now: base)
    assert {:ok, s2} = SessionStore.create("user-2", remember_me: true, now: base)

    assert [expired_token] = SessionStore.prune_expired(base + 86_401)
    assert expired_token == s1.token
    assert {:error, :not_found} = SessionStore.fetch(s1.token, base + 86_401)
    assert {:ok, _} = SessionStore.fetch(s2.token, base + 86_401)
  end

  test "persists sessions to disk" do
    assert {:ok, session} = SessionStore.create("user-3", now: 100)
    path = NervesView.Persistence.path_for("sessions.term")
    assert File.exists?(path)
    assert {:ok, bin} = File.read(path)
    persisted = :erlang.binary_to_term(bin)
    assert persisted[session.token].user_id == "user-3"
  end
end
