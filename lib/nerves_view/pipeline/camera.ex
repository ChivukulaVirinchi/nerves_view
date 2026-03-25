defmodule NervesView.Pipeline.Camera do
  @moduledoc """
  Target camera pipeline descriptor used by manager and UI.
  """

  alias NervesView.Camera.Source

  @spec build(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def build(camera, opts \\ []) when is_map(camera) do
    with {:ok, normalized} <- Source.normalize(camera) do
      resolution = Keyword.get(opts, :resolution, {1280, 720})
      fps = Keyword.get(opts, :fps, 30)
      bitrate = Keyword.get(opts, :bitrate, 2_000_000)

      {:ok,
       %{
         camera_id: normalized.id,
         camera_name: Map.get(normalized, :name),
         source_type: normalized.source_type,
         source: %{device_path: normalized.device_path, backend: normalized.capture_backend},
         encoder: %{codec: :h264, mode: :hardware_preferred, bitrate: bitrate, keyint: fps * 2},
         outputs: %{webrtc: true, motion_detector: true},
         stream: %{resolution: resolution, fps: fps}
       }}
    end
  end
end
