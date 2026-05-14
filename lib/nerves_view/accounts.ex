defmodule NervesView.Accounts do
  @moduledoc """
  Account context. Backed by Ecto + SQLite at `/data/nerves_view/nerves_view.db`
  on a Nerves target (configured per-env in `config/`).
  """

  import Ecto.Query, only: [from: 2]

  alias NervesView.Accounts.User
  alias NervesView.Repo

  @type user :: %{
          required(:id) => String.t(),
          required(:email) => String.t(),
          required(:role) => :admin | :viewer,
          required(:password_hash) => String.t(),
          required(:inserted_at) => non_neg_integer()
        }

  @spec register(String.t(), String.t(), :admin | :viewer) ::
          {:ok, user()} | {:error, atom()}
  def register(email, password, role \\ :viewer)
      when is_binary(email) and is_binary(password) and is_atom(role) do
    %{email: email, password: password, role: role}
    |> User.registration_changeset()
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        {:ok, to_legacy_map(user)}

      {:error, changeset} ->
        {:error, changeset_to_error(changeset)}
    end
  end

  @spec authenticate(String.t(), String.t()) :: {:ok, user()} | {:error, atom()}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    normalized = email |> String.trim() |> String.downcase()

    case Repo.get_by(User, email: normalized) do
      nil ->
        # Run a dummy bcrypt verify to keep the response time the same as a
        # real check, so we don't leak which emails exist via timing.
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      %User{} = user ->
        if Bcrypt.verify_pass(password, user.password_hash) do
          {:ok, to_legacy_map(user)}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  @spec list_users() :: [user()]
  def list_users do
    User
    |> from(order_by: [asc: :email])
    |> Repo.all()
    |> Enum.map(&to_legacy_map/1)
  end

  @spec get_user(String.t()) :: {:ok, user()} | {:error, :not_found}
  def get_user(user_id) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      %User{} = user -> {:ok, to_legacy_map(user)}
    end
  end

  @spec clear() :: :ok
  def clear do
    Repo.delete_all(User)
    :ok
  end

  # The rest of the app still consumes the legacy plain-map shape produced by
  # the old GenServer-backed Store. Convert here so the public surface in
  # NervesView and callers (e.g. UserAuth, SessionStore) does not change.
  defp to_legacy_map(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      password_hash: user.password_hash,
      inserted_at: DateTime.to_unix(user.inserted_at)
    }
  end

  defp changeset_to_error(%Ecto.Changeset{errors: errors}) do
    cond do
      Keyword.has_key?(errors, :email) ->
        msg = errors |> Keyword.get(:email) |> elem(0)

        cond do
          String.contains?(msg, "taken") -> :email_taken
          String.contains?(msg, "valid email") -> :invalid_email
          String.contains?(msg, "blank") -> :invalid_email
          true -> :invalid_email
        end

      Keyword.has_key?(errors, :password) ->
        :password_too_short

      Keyword.has_key?(errors, :role) ->
        :invalid_role

      true ->
        :invalid
    end
  end
end
