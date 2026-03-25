defmodule NervesView.Diagnostics do
  @moduledoc false

  @spec camera_status(map()) :: map()
  def camera_status(camera) do
    camera_id = camera.id

    pipeline =
      case NervesView.pipeline_status(camera_id) do
        {:ok, status} -> status
        {:error, :not_found} -> nil
      end

    health =
      case NervesView.pipeline_health(camera_id) do
        {:ok, status} -> status
        {:error, :not_found} -> %{healthy: false}
      end

    %{
      camera_id: camera_id,
      camera_name: camera.name,
      source_type: camera.source_type,
      device_path: camera.device_path,
      configured_status: camera.status,
      pipeline_status: pipeline && pipeline.status,
      healthy: Map.get(health, :healthy, false),
      source_path: Map.get(health, :source_path),
      last_error: pipeline && pipeline[:last_error]
    }
  end
end
