defmodule NervesView do
  @moduledoc """
  Public API for the NervesView foundation phase.
  """

  alias NervesView.Alerts
  alias NervesView.Camera.Registry
  alias NervesView.Diagnostics
  alias NervesView.Cluster.NodeRegistry
  alias NervesView.Accounts
  alias NervesView.Accounts.Permissions
  alias NervesView.Accounts.SessionStore
  alias NervesView.Motion
  alias NervesView.Network.Discovery
  alias NervesView.Pipeline.Manager, as: PipelineManager
  alias NervesView.Pipeline.MotionDetector
  alias NervesView.Recording.Store, as: RecordingStore
  alias NervesView.Storage.Manager, as: StorageManager
  alias NervesView.Streaming.Signaling

  @spec list_cameras() :: [NervesView.Camera.t()]
  def list_cameras do
    Registry.list()
  end

  @spec remove_camera(String.t()) :: :ok
  def remove_camera(camera_id) when is_binary(camera_id) do
    Registry.remove(camera_id)
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
    case MotionDetector.detect(previous_frame, current_frame, opts) do
      {:ok, result} -> {:ok, result}
      {:error, _reason} -> Motion.detect(previous_frame, current_frame, opts)
    end
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
    Accounts.register(email, password, role)
  end

  @spec login(String.t(), String.t(), keyword()) ::
          {:ok, %{user: map(), session: map()}} | {:error, atom()}
  def login(email, password, opts \\ []) do
    with {:ok, user} <- Accounts.authenticate(email, password),
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
  def list_users, do: Accounts.list_users()

  @spec first_boot?() :: boolean()
  def first_boot?, do: list_users() == []

  @invite_max_age 86_400

  @doc """
  Mint a one-time invite link nonce. Signed with a 24-hour TTL. The admin
  hands the resulting URL (`/register?token=...`) to whoever they're letting in.
  """
  @spec generate_invite_token() :: String.t()
  def generate_invite_token do
    nonce = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    Phoenix.Token.sign(NervesViewWeb.Endpoint, "invite", nonce)
  end

  @doc """
  Verify an invite token. Valid for `@invite_max_age` seconds after minting.
  Returns `:ok` or `{:error, :invalid_token}`.
  """
  @spec validate_invite_token(any()) :: :ok | {:error, :invalid_token}
  def validate_invite_token(token) when is_binary(token) do
    case Phoenix.Token.verify(NervesViewWeb.Endpoint, "invite", token, max_age: @invite_max_age) do
      {:ok, _nonce} -> :ok
      _ -> {:error, :invalid_token}
    end
  end

  def validate_invite_token(_), do: {:error, :invalid_token}

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

  @spec pipeline_health(String.t()) :: {:ok, map()} | {:error, :not_found}
  def pipeline_health(camera_id) when is_binary(camera_id) do
    PipelineManager.health(camera_id)
  end

  @spec restart_camera_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def restart_camera_pipeline(camera_id, opts \\ []) when is_binary(camera_id) do
    PipelineManager.restart_pipeline(camera_id, opts)
  end

  @spec get_camera_color_config(String.t()) :: NervesView.Camera.Config.t()
  def get_camera_color_config(camera_id) when is_binary(camera_id) do
    case Registry.get_config(camera_id) do
      {:ok, config} -> config
      _ -> %NervesView.Camera.Config{}
    end
  end

  @spec set_camera_color_config(String.t(), map()) :: :ok | {:error, term()}
  def set_camera_color_config(camera_id, attrs) when is_binary(camera_id) and is_map(attrs) do
    Registry.put_config(camera_id, attrs)
  end

  @spec camera_diagnostics() :: [map()]
  def camera_diagnostics do
    list_cameras()
    |> Enum.map(&Diagnostics.camera_status/1)
    |> Enum.sort_by(& &1.camera_id)
  end

  @spec start_camera_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_camera_pipeline(camera_id, opts \\ []) when is_binary(camera_id) do
    with {:ok, camera} <- Registry.get(camera_id) do
      PipelineManager.start_camera_pipeline(Map.from_struct(camera), opts)
    end
  end

  @spec storage_usage() :: %{recording_count: non_neg_integer(), total_bytes: non_neg_integer()}
  def storage_usage do
    StorageManager.usage()
  end

  @spec enforce_recording_retention(keyword()) :: %{
          trimmed: non_neg_integer(),
          max_count: pos_integer()
        }
  def enforce_recording_retention(opts \\ []) do
    StorageManager.enforce_retention(opts)
  end

  # ── DVR ──

  @spec dvr_segments(String.t(), non_neg_integer(), non_neg_integer()) :: [map()]
  def dvr_segments(camera_id, from_ts, to_ts) do
    NervesView.DVR.SegmentIndex.segments_for(camera_id, from_ts, to_ts)
  end

  @spec dvr_retention_window(String.t()) :: {non_neg_integer(), non_neg_integer()} | nil
  def dvr_retention_window(camera_id) do
    NervesView.DVR.SegmentIndex.retention_window(camera_id)
  end

  @spec dvr_playlist(String.t(), non_neg_integer()) :: String.t()
  def dvr_playlist(camera_id, from_ts) do
    now = System.system_time(:second)
    segments = NervesView.DVR.SegmentIndex.segments_for(camera_id, from_ts, now + 60)
    NervesView.DVR.PlaylistBuilder.build_vod(camera_id, segments)
  end
end
