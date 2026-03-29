defmodule NervesView.Accounts.Store do
  @moduledoc "In-memory account store for phase-5 auth and roles."

  use GenServer

  alias NervesView.Persistence

  @name __MODULE__
  @roles [:admin, :viewer]
  @persist_file "users.term"

  @type user :: %{
          required(:id) => String.t(),
          required(:email) => String.t(),
          required(:role) => :admin | :viewer,
          required(:password_hash) => String.t(),
          required(:inserted_at) => non_neg_integer()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec register(String.t(), String.t(), atom()) :: {:ok, user()} | {:error, atom()}
  def register(email, password, role \\ :viewer)
      when is_binary(email) and is_binary(password) and is_atom(role) do
    GenServer.call(@name, {:register, email, password, role})
  end

  @spec authenticate(String.t(), String.t()) :: {:ok, user()} | {:error, atom()}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    GenServer.call(@name, {:authenticate, email, password})
  end

  @spec list_users() :: [user()]
  def list_users do
    GenServer.call(@name, :list_users)
  end

  @spec get_user(String.t()) :: {:ok, user()} | {:error, :not_found}
  def get_user(user_id) when is_binary(user_id) do
    GenServer.call(@name, {:get_user, user_id})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @impl true
  def init(_state), do: {:ok, Persistence.load(@persist_file, %{})}

  @impl true
  def handle_call({:register, email, password, role}, _from, state) do
    normalized = String.downcase(String.trim(email))

    cond do
      normalized == "" ->
        {:reply, {:error, :invalid_email}, state}

      String.length(password) < 8 ->
        {:reply, {:error, :password_too_short}, state}

      role not in @roles ->
        {:reply, {:error, :invalid_role}, state}

      email_taken?(state, normalized) ->
        {:reply, {:error, :email_taken}, state}

      true ->
        user = %{
          id: user_id(),
          email: normalized,
          role: role,
          password_hash: hash_password(password),
          inserted_at: System.system_time(:second)
        }

        next_state = Map.put(state, user.id, user)
        :ok = Persistence.save(@persist_file, next_state)
        {:reply, {:ok, user}, next_state}
    end
  end

  def handle_call({:authenticate, email, password}, _from, state) do
    normalized = String.downcase(String.trim(email))

    case find_by_email(state, normalized) do
      nil ->
        {:reply, {:error, :invalid_credentials}, state}

      user ->
        if verify_password(password, user.password_hash) do
          {:reply, {:ok, user}, state}
        else
          {:reply, {:error, :invalid_credentials}, state}
        end
    end
  end

  def handle_call(:list_users, _from, state) do
    users = state |> Map.values() |> Enum.sort_by(& &1.email)
    {:reply, users, state}
  end

  def handle_call({:get_user, user_id}, _from, state) do
    case Map.fetch(state, user_id) do
      {:ok, user} -> {:reply, {:ok, user}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:clear, _from, _state) do
    :ok = Persistence.save(@persist_file, %{})
    {:reply, :ok, %{}}
  end

  defp email_taken?(state, email) do
    Enum.any?(state, fn {_id, user} -> user.email == email end)
  end

  defp find_by_email(state, email) do
    state
    |> Map.values()
    |> Enum.find(&(&1.email == email))
  end

  defp user_id do
    :crypto.strong_rand_bytes(10)
    |> Base.url_encode64(padding: false)
  end

  defp hash_password(password) do
    Bcrypt.hash_pwd_salt(password, log_rounds: 4)
  end

  defp verify_password(password, "$2" <> _ = hash) do
    Bcrypt.verify_pass(password, hash)
  end

  # Legacy SHA256 hash migration — verify and return true so caller can re-hash
  defp verify_password(password, legacy_hash) when is_binary(legacy_hash) do
    sha_hash =
      :sha256
      |> :crypto.hash(password)
      |> Base.encode16(case: :lower)

    sha_hash == legacy_hash
  end
end
