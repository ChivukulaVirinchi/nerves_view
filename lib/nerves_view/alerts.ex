defmodule NervesView.Alerts do
  @moduledoc "Phase-6 alerts for motion notifications with throttling."

  use GenServer

  @name __MODULE__

  @type alert :: %{
          required(:id) => String.t(),
          required(:camera_id) => String.t(),
          required(:event_type) => :motion,
          required(:inserted_at) => non_neg_integer(),
          required(:message) => String.t()
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{alerts: [], by_camera: %{}}, name: @name)
  end

  @spec notify_motion(String.t(), non_neg_integer(), keyword()) ::
          {:ok, alert()} | {:error, atom()}
  def notify_motion(camera_id, timestamp \\ now(), opts \\ [])
      when is_binary(camera_id) and is_integer(timestamp) do
    GenServer.call(@name, {:notify_motion, camera_id, timestamp, opts})
  end

  @spec list(keyword()) :: [alert()]
  def list(opts \\ []) do
    GenServer.call(@name, {:list, opts})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:notify_motion, camera_id, timestamp, opts}, _from, state) do
    throttle_seconds = Keyword.get(opts, :throttle_seconds, 15)
    last_ts = Map.get(state.by_camera, camera_id)

    case throttled?(last_ts, timestamp, throttle_seconds) do
      true ->
        {:reply, {:error, :throttled}, state}

      false ->
        alert = %{
          id: alert_id(),
          camera_id: camera_id,
          event_type: :motion,
          inserted_at: timestamp,
          message: "Motion detected on #{camera_id}"
        }

        next_state = %{
          alerts: [alert | state.alerts],
          by_camera: Map.put(state.by_camera, camera_id, timestamp)
        }

        Phoenix.PubSub.broadcast(NervesView.PubSub, "alerts:motion", {:motion_alert, alert})

        {:reply, {:ok, alert}, next_state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    camera_id = Keyword.get(opts, :camera_id)

    alerts =
      state.alerts
      |> Enum.filter(fn alert -> is_nil(camera_id) or alert.camera_id == camera_id end)
      |> Enum.sort_by(& &1.inserted_at, :desc)

    {:reply, alerts, state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{alerts: [], by_camera: %{}}}
  end

  defp alert_id do
    :crypto.strong_rand_bytes(10)
    |> Base.url_encode64(padding: false)
  end

  defp now, do: System.system_time(:second)

  defp throttled?(last_ts, timestamp, throttle_seconds)
       when is_integer(last_ts) and is_integer(timestamp) and is_integer(throttle_seconds) do
    timestamp - last_ts < throttle_seconds
  end

  defp throttled?(_last_ts, _timestamp, _throttle_seconds), do: false
end
