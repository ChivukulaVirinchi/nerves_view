defmodule NervesView.Accounts.RegistrationParams do
  @moduledoc "Embedded schema + changeset for registration form validation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:email, :string, default: "")
    field(:password, :string, default: "")
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, message: "must be at least 8 characters")
  end
end
