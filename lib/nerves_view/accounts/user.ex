defmodule NervesView.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles [:admin, :viewer]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          email: String.t(),
          role: :admin | :viewer,
          password_hash: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :string, autogenerate: false}
  schema "users" do
    field(:email, :string)
    field(:role, Ecto.Enum, values: @roles, default: :viewer)
    field(:password_hash, :string)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for inserting a new user. Accepts the cleartext password
  and hashes it. Performs the same validations as the in-form RegistrationParams
  (email format, password length) plus the schema-level :email uniqueness.
  """
  def registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :role])
    |> put_change(:id, generate_id())
    |> validate_required([:email])
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
    |> put_password_hash(attrs)
  end

  defp put_password_hash(changeset, %{password: password}) when is_binary(password),
    do: do_put_password_hash(changeset, password)

  defp put_password_hash(changeset, %{"password" => password}) when is_binary(password),
    do: do_put_password_hash(changeset, password)

  defp put_password_hash(changeset, _attrs),
    do: add_error(changeset, :password, "can't be blank")

  defp do_put_password_hash(changeset, password) do
    cond do
      String.length(password) < 8 ->
        add_error(changeset, :password, "must be at least 8 characters")

      true ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(other), do: other

  defp generate_id do
    :crypto.strong_rand_bytes(10) |> Base.url_encode64(padding: false)
  end
end
