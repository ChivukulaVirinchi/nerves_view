defmodule NervesView.Accounts.LoginParams do
  @moduledoc "Embedded schema + changeset for login form validation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:email, :string, default: "")
    field(:password, :string, default: "")
    field(:remember_me, :boolean, default: false)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:email, :password, :remember_me])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
  end
end
