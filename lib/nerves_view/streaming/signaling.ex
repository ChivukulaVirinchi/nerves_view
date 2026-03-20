defmodule NervesView.Streaming.Signaling do
  @moduledoc """
  In-memory signaling session manager for phase-2 WebRTC bootstrapping.
  """

  use GenServer

  @name __MODULE__

  @type session :: %{
          required(:camera_id) => String.t(),
          required(:offer_sdp) => String.t(),
          optional(:answer_sdp) => String.t(),
          required(:ice_candidates) => [map()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec create_offer(String.t(), String.t()) :: {:ok, String.t(), String.t()}
  def create_offer(camera_id, offer_sdp)
      when is_binary(camera_id) and is_binary(offer_sdp) do
    GenServer.call(@name, {:create_offer, camera_id, offer_sdp})
  end

  @spec apply_answer(String.t(), String.t()) :: :ok | {:error, :not_found}
  def apply_answer(session_id, answer_sdp)
      when is_binary(session_id) and is_binary(answer_sdp) do
    GenServer.call(@name, {:apply_answer, session_id, answer_sdp})
  end

  @spec add_ice_candidate(String.t(), map()) :: :ok | {:error, :not_found}
  def add_ice_candidate(session_id, candidate)
      when is_binary(session_id) and is_map(candidate) do
    GenServer.call(@name, {:add_ice_candidate, session_id, candidate})
  end

  @spec get_session(String.t()) :: {:ok, session()} | {:error, :not_found}
  def get_session(session_id) when is_binary(session_id) do
    GenServer.call(@name, {:get_session, session_id})
  end

  @spec remove_session(String.t()) :: :ok
  def remove_session(session_id) when is_binary(session_id) do
    GenServer.call(@name, {:remove_session, session_id})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:create_offer, camera_id, offer_sdp}, _from, state) do
    session_id = unique_session_id()

    session = %{
      camera_id: camera_id,
      offer_sdp: offer_sdp,
      ice_candidates: []
    }

    {:reply, {:ok, session_id, offer_sdp}, Map.put(state, session_id, session)}
  end

  def handle_call({:apply_answer, session_id, answer_sdp}, _from, state) do
    case Map.fetch(state, session_id) do
      {:ok, session} ->
        next_state = Map.put(state, session_id, Map.put(session, :answer_sdp, answer_sdp))
        {:reply, :ok, next_state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_ice_candidate, session_id, candidate}, _from, state) do
    case Map.fetch(state, session_id) do
      {:ok, session} ->
        next_session = Map.update!(session, :ice_candidates, &[candidate | &1])
        {:reply, :ok, Map.put(state, session_id, next_session)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_session, session_id}, _from, state) do
    case Map.fetch(state, session_id) do
      {:ok, session} -> {:reply, {:ok, session}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:remove_session, session_id}, _from, state) do
    {:reply, :ok, Map.delete(state, session_id)}
  end

  defp unique_session_id do
    :crypto.strong_rand_bytes(12)
    |> Base.url_encode64(padding: false)
  end
end
