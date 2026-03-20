defmodule NervesView do
  @moduledoc """
  Public API for the NervesView foundation phase.
  """

  alias NervesView.Camera.Registry
  alias NervesView.Motion
  alias NervesView.Recording.Store
  alias NervesView.Streaming.Signaling

  @spec list_cameras() :: [NervesView.Camera.t()]
  def list_cameras do
    Registry.list()
  end

  @spec register_camera(map()) :: {:ok, NervesView.Camera.t()} | {:error, term()}
  def register_camera(attrs) when is_map(attrs) do
    Registry.upsert(attrs)
  end

  @spec create_stream_offer(String.t()) :: {:ok, %{session_id: String.t(), sdp: String.t()}}
  def create_stream_offer(camera_id) when is_binary(camera_id) do
    offer = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=NervesView\r\nt=0 0\r\n"

    with {:ok, _camera} <- Registry.get(camera_id),
         {:ok, session_id, sdp} <- Signaling.create_offer(camera_id, offer) do
      {:ok, %{session_id: session_id, sdp: sdp}}
    else
      {:error, :not_found} -> {:error, :camera_not_found}
    end
  end

  @spec apply_stream_answer(String.t(), String.t()) :: :ok | {:error, :session_not_found}
  def apply_stream_answer(session_id, answer_sdp)
      when is_binary(session_id) and is_binary(answer_sdp) do
    case Signaling.apply_answer(session_id, answer_sdp) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :session_not_found}
    end
  end

  @spec add_stream_ice_candidate(String.t(), map()) :: :ok | {:error, :session_not_found}
  def add_stream_ice_candidate(session_id, candidate)
      when is_binary(session_id) and is_map(candidate) do
    case Signaling.add_ice_candidate(session_id, candidate) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :session_not_found}
    end
  end

  @spec detect_motion([number()], [number()], keyword()) :: {:ok, map()} | {:error, atom()}
  def detect_motion(previous_frame, current_frame, opts \\ []) do
    Motion.detect(previous_frame, current_frame, opts)
  end

  @spec store_recording(map()) :: {:ok, map()} | {:error, atom()}
  def store_recording(recording) when is_map(recording) do
    Store.put(recording)
  end

  @spec list_recordings(keyword()) :: [map()]
  def list_recordings(opts \\ []) do
    Store.list(opts)
  end

  @spec trim_recordings(pos_integer()) :: non_neg_integer()
  def trim_recordings(max_count) when is_integer(max_count) and max_count > 0 do
    Store.trim_by_count(max_count)
  end
end
