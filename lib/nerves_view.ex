defmodule NervesView do
  @moduledoc """
  Public API for the NervesView foundation phase.
  """

  alias NervesView.Alerts
  alias NervesView.Camera.Registry
  alias NervesView.Cluster.NodeRegistry
  alias NervesView.Accounts.Permissions
  alias NervesView.Accounts.SessionStore
  alias NervesView.Accounts.Store
  alias NervesView.Motion
  alias NervesView.Network.Discovery
  alias NervesView.Pipeline.Manager, as: PipelineManager
  alias NervesView.Recording.Store, as: RecordingStore
  alias NervesView.Streaming.Signaling

  @spec list_cameras() :: [NervesView.Camera.t()]
  def list_cameras do
    Registry.list()
  end

  @spec register_camera(map()) :: {:ok, NervesView.Camera.t()} | {:error, term()}
  def register_camera(attrs) when is_map(attrs) do
    Registry.upsert(attrs)
  end

  @spec create_stream_offer(String.t(), String.t()) ::
          {:ok, %{session_id: String.t(), sdp: String.t()}} | {:error, :camera_not_found}
  def create_stream_offer(camera_id, viewer_id \\ "viewer") when is_binary(camera_id) do
    offer = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=NervesView\r\nt=0 0\r\n"

    with {:ok, _camera} <- Registry.get(camera_id),
         {:ok, session_id, sdp} <- Signaling.create_offer(camera_id, viewer_id, offer) do
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

  @spec add_stream_ice_candidate(String.t(), :viewer | :publisher, map()) ::
          :ok | {:error, :session_not_found}
  def add_stream_ice_candidate(session_id, role, candidate)
      when is_binary(session_id) and role in [:viewer, :publisher] and is_map(candidate) do
    case Signaling.add_ice_candidate(session_id, role, candidate) do
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
    RecordingStore.put(recording)
  end

  @spec list_recordings(keyword()) :: [map()]
  def list_recordings(opts \\ []) do
    RecordingStore.list(opts)
  end

  @spec trim_recordings(pos_integer()) :: non_neg_integer()
  def trim_recordings(max_count) when is_integer(max_count) and max_count > 0 do
    RecordingStore.trim_by_count(max_count)
  end

  @spec register_node(map()) :: {:ok, map()} | {:error, atom()}
  def register_node(attrs) when is_map(attrs) do
    NodeRegistry.register(attrs)
  end

  @spec list_nodes(keyword()) :: [map()]
  def list_nodes(opts \\ []) do
    NodeRegistry.list(opts)
  end

  @spec node_heartbeat(String.t(), non_neg_integer()) :: :ok | {:error, :not_found}
  def node_heartbeat(node_id, timestamp \\ System.system_time(:second)) do
    NodeRegistry.heartbeat(node_id, timestamp)
  end

  @spec prune_stale_nodes(pos_integer(), non_neg_integer()) :: [String.t()]
  def prune_stale_nodes(max_age_seconds, now_ts \\ System.system_time(:second))
      when is_integer(max_age_seconds) and max_age_seconds > 0 and is_integer(now_ts) do
    NodeRegistry.prune_stale(max_age_seconds, now_ts)
  end

  @spec announce_camera_service(map()) :: {:ok, map()} | {:error, atom()}
  def announce_camera_service(attrs) when is_map(attrs) do
    Discovery.announce(attrs)
  end

  @spec list_camera_services() :: [map()]
  def list_camera_services do
    Discovery.list()
  end

  @spec prune_stale_services(pos_integer(), non_neg_integer()) :: [String.t()]
  def prune_stale_services(max_age_seconds, now_ts \\ System.system_time(:second))
      when is_integer(max_age_seconds) and max_age_seconds > 0 and is_integer(now_ts) do
    Discovery.prune_stale(max_age_seconds, now_ts)
  end

  @spec register_user(String.t(), String.t(), :admin | :viewer) :: {:ok, map()} | {:error, atom()}
  def register_user(email, password, role \\ :viewer) do
    Store.register(email, password, role)
  end

  @spec login(String.t(), String.t(), keyword()) ::
          {:ok, %{user: map(), session: map()}} | {:error, atom()}
  def login(email, password, opts \\ []) do
    with {:ok, user} <- Store.authenticate(email, password),
         {:ok, session} <- SessionStore.create(user.id, opts) do
      {:ok, %{user: user, session: session}}
    end
  end

  @spec authorize(atom(), atom()) :: :ok | {:error, :forbidden}
  def authorize(role, action) when is_atom(role) and is_atom(action) do
    if Permissions.allowed?(role, action), do: :ok, else: {:error, :forbidden}
  end

  @spec validate_session(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def validate_session(token, now_ts \\ System.system_time(:second)) do
    SessionStore.fetch(token, now_ts)
  end

  @spec logout(String.t()) :: :ok
  def logout(token), do: SessionStore.revoke(token)

  @spec list_users() :: [map()]
  def list_users, do: Store.list_users()

  @spec notify_motion_event(String.t(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def notify_motion_event(camera_id, timestamp \\ System.system_time(:second), opts \\ []) do
    Alerts.notify_motion(camera_id, timestamp, opts)
  end

  @spec list_alerts(keyword()) :: [map()]
  def list_alerts(opts \\ []) do
    Alerts.list(opts)
  end

  @spec start_test_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_test_pipeline(camera_id, opts \\ []) when is_binary(camera_id) do
    PipelineManager.start_pipeline(camera_id, opts)
  end

  @spec stop_test_pipeline(String.t()) :: :ok
  def stop_test_pipeline(camera_id) when is_binary(camera_id) do
    PipelineManager.stop_pipeline(camera_id)
  end

  @spec pipeline_status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def pipeline_status(camera_id) when is_binary(camera_id) do
    PipelineManager.status(camera_id)
  end
end
