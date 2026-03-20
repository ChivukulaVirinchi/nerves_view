defmodule NervesView.Accounts.PermissionsTest do
  use ExUnit.Case, async: true

  alias NervesView.Accounts.Permissions

  test "admin has management permissions" do
    assert Permissions.allowed?(:admin, :manage_users)
    assert Permissions.allowed?(:admin, :manage_cameras)
  end

  test "viewer has read-only permissions" do
    assert Permissions.allowed?(:viewer, :view_live)
    assert Permissions.allowed?(:viewer, :view_recordings)
    refute Permissions.allowed?(:viewer, :manage_users)
  end
end
