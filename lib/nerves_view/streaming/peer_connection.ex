defmodule NervesView.Streaming.PeerConnection do
  @moduledoc """
  Per-viewer signaling state for a camera stream session.
  """

  use GenServer

  @type role :: :viewer | :publisher
  @timeout_seconds 45

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def set_offer(session_id, sdp), do: GenServer.call(via(session_id), {:set_offer, sdp})
  def set_answer(session_id, sdp), do: GenServer.call(via(session_id), {:set_answer, sdp})

  def add_ice_candidate(session_id, role, candidate)
      when role in [:viewer, :publisher] and is_map(candidate) do
    GenServer.call(via(session_id), {:add_ice, role, candidate})
  end

  def snapshot(session_id), do: GenServer.call(via(session_id), :snapshot)
  def mark_connected(session_id), do: GenServer.call(via(session_id), :mark_connected)
  def close(session_id, reason \\ :normal), do: GenServer.call(via(session_id), {:close, reason})
  def stop(session_id), do: GenServer.stop(via(session_id), :normal)

  @impl true
  def init(opts) do
    now = System.system_time(:second)

    state = %{
      session_id: Keyword.fetch!(opts, :session_id),
      camera_id: Keyword.fetch!(opts, :camera_id),
      viewer_id: Keyword.fetch!(opts, :viewer_id),
      offer_sdp: nil,
      answer_sdp: nil,
      ice_candidates: %{viewer: [], publisher: []},
      state: :new,
      state_reason: nil,
      timeout_at: now + @timeout_seconds,
      inserted_at: now,
      updated_at: now
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:set_offer, sdp}, _from, state) do
    now = System.system_time(:second)

    next = %{
      state
      | offer_sdp: sdp,
        state: :connecting,
        updated_at: now,
        timeout_at: now + @timeout_seconds
    }

    {:reply, :ok, next}
  end

  def handle_call({:set_answer, sdp}, _from, state) do
    now = System.system_time(:second)

    next = %{
      state
      | answer_sdp: sdp,
        state: :connecting,
        updated_at: now,
        timeout_at: now + @timeout_seconds
    }

    {:reply, :ok, next}
  end

  def handle_call({:add_ice, role, candidate}, _from, state) do
    next_candidates = Map.update!(state.ice_candidates, role, &[candidate | &1])
    now = System.system_time(:second)

    next = %{
      state
      | ice_candidates: next_candidates,
        updated_at: now,
        timeout_at: now + @timeout_seconds
    }

    {:reply, :ok, next}
  end

  def handle_call(:mark_connected, _from, state) do
    next = %{
      state
      | state: :connected,
        state_reason: nil,
        updated_at: System.system_time(:second)
    }

    {:reply, :ok, next}
  end

  def handle_call({:close, reason}, _from, state) do
    next = %{
      state
      | state: :closed,
        state_reason: reason,
        updated_at: System.system_time(:second)
    }

    {:reply, :ok, next}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, state}, state}
  end

  defp via(session_id), do: {:via, Registry, {NervesView.Streaming.Registry, session_id}}
end
