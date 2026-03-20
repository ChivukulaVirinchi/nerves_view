defmodule NervesView.Streaming.PeerManager do
  @moduledoc """
  Starts and tracks per-session peer connection processes.
  """

  alias NervesView.Streaming.PeerConnection

  @spec start_session(String.t(), String.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def start_session(session_id, camera_id, viewer_id) do
    spec = {PeerConnection, session_id: session_id, camera_id: camera_id, viewer_id: viewer_id}
    DynamicSupervisor.start_child(NervesView.Streaming.PeerSupervisor, spec)
  end

  @spec stop_session(String.t()) :: :ok
  def stop_session(session_id) do
    case Registry.lookup(NervesView.Streaming.Registry, session_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(NervesView.Streaming.PeerSupervisor, pid)

      [] ->
        :ok
    end
  end

  @spec get_session(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_session(session_id) do
    case Registry.lookup(NervesView.Streaming.Registry, session_id) do
      [{_pid, _}] ->
        try do
          PeerConnection.snapshot(session_id)
        catch
          :exit, _reason -> {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end
end
