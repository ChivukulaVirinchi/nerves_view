defmodule NervesView.Streaming.Signaling do
  @moduledoc """
  In-memory signaling session manager with per-session peer lifecycle.
  """

  use GenServer

  alias NervesView.Streaming.PeerConnection
  alias NervesView.Streaming.PeerManager

  @name __MODULE__

  @type session :: %{
          required(:camera_id) => String.t(),
          required(:viewer_id) => String.t(),
          optional(:offer_sdp) => String.t(),
          optional(:answer_sdp) => String.t(),
          required(:ice_candidates) => %{viewer: [map()], publisher: [map()]},
          required(:inserted_at) => non_neg_integer(),
          required(:updated_at) => non_neg_integer()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec create_session(String.t(), String.t()) :: {:ok, String.t()}
  def create_session(camera_id, viewer_id)
      when is_binary(camera_id) and is_binary(viewer_id) do
    GenServer.call(@name, {:create_session, camera_id, viewer_id})
  end

  @spec create_offer(String.t(), String.t(), String.t()) :: {:ok, String.t(), String.t()}
  def create_offer(camera_id, viewer_id, offer_sdp)
      when is_binary(camera_id) and is_binary(viewer_id) and is_binary(offer_sdp) do
    GenServer.call(@name, {:create_offer, camera_id, viewer_id, offer_sdp})
  end

  @spec apply_answer(String.t(), String.t()) :: :ok | {:error, :not_found}
  def apply_answer(session_id, answer_sdp)
      when is_binary(session_id) and is_binary(answer_sdp) do
    GenServer.call(@name, {:apply_answer, session_id, answer_sdp})
  end

  @spec add_ice_candidate(String.t(), :viewer | :publisher, map()) :: :ok | {:error, :not_found}
  def add_ice_candidate(session_id, role, candidate)
      when is_binary(session_id) and role in [:viewer, :publisher] and is_map(candidate) do
    GenServer.call(@name, {:add_ice_candidate, session_id, role, candidate})
  end

  @spec get_session(String.t()) :: {:ok, session()} | {:error, :not_found}
  def get_session(session_id) when is_binary(session_id) do
    GenServer.call(@name, {:get_session, session_id})
  end

  @spec remove_session(String.t()) :: :ok
  def remove_session(session_id) when is_binary(session_id) do
    GenServer.call(@name, {:remove_session, session_id})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:create_session, camera_id, viewer_id}, _from, state) do
    session_id = unique_session_id()

    case PeerManager.start_session(session_id, camera_id, viewer_id) do
      {:ok, _pid} ->
        session = session_from_peer!(session_id)
        {:reply, {:ok, session_id}, Map.put(state, session_id, session)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_offer, camera_id, viewer_id, offer_sdp}, _from, state) do
    session_id = unique_session_id()

    with {:ok, _pid} <- PeerManager.start_session(session_id, camera_id, viewer_id),
         :ok <- PeerConnection.set_offer(session_id, offer_sdp) do
      session = session_from_peer!(session_id)
      {:reply, {:ok, session_id, offer_sdp}, Map.put(state, session_id, session)}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:apply_answer, session_id, answer_sdp}, _from, state) do
    case PeerManager.get_session(session_id) do
      {:ok, _session} ->
        :ok = PeerConnection.set_answer(session_id, answer_sdp)
        {:reply, :ok, Map.put(state, session_id, session_from_peer!(session_id))}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_ice_candidate, session_id, role, candidate}, _from, state) do
    case PeerManager.get_session(session_id) do
      {:ok, _session} ->
        :ok = PeerConnection.add_ice_candidate(session_id, role, candidate)
        {:reply, :ok, Map.put(state, session_id, session_from_peer!(session_id))}

      {:error, :not_found} ->
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
    :ok = PeerManager.stop_session(session_id)
    {:reply, :ok, Map.delete(state, session_id)}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(Map.keys(state), &PeerManager.stop_session/1)
    {:reply, :ok, %{}}
  end

  defp session_from_peer!(session_id) do
    {:ok, peer} = PeerManager.get_session(session_id)

    %{
      camera_id: peer.camera_id,
      viewer_id: peer.viewer_id,
      offer_sdp: peer.offer_sdp,
      answer_sdp: peer.answer_sdp,
      ice_candidates: peer.ice_candidates,
      inserted_at: peer.inserted_at,
      updated_at: peer.updated_at
    }
  end

  defp unique_session_id do
    :crypto.strong_rand_bytes(12)
    |> Base.url_encode64(padding: false)
  end
end
