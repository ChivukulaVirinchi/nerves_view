defmodule NervesView.Accounts.Permissions do
  @moduledoc "Role-based permission checks for phase-5."

  @matrix %{
    admin:
      MapSet.new([:view_live, :view_recordings, :manage_cameras, :manage_users, :manage_system]),
    viewer: MapSet.new([:view_live, :view_recordings])
  }

  @type action :: :view_live | :view_recordings | :manage_cameras | :manage_users | :manage_system

  @spec allowed?(atom(), action()) :: boolean()
  def allowed?(role, action) when is_atom(role) and is_atom(action) do
    @matrix
    |> Map.get(role, MapSet.new())
    |> MapSet.member?(action)
  end
end
