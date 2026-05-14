defmodule NervesView.Pipeline.Camera do
  @moduledoc """
  Target camera pipeline descriptor used by manager and UI.
  """

  alias NervesView.Camera.Source

  @spec build(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def build(camera, opts \\ []) when is_map(camera) do
    with {:ok, normalized} <- Source.normalize(camera) do
      {def_w, def_h, def_fps, def_bitrate} = default_stream_params()
      resolution = Keyword.get(opts, :resolution, {def_w, def_h})
      fps = Keyword.get(opts, :fps, def_fps)
      bitrate = Keyword.get(opts, :bitrate, def_bitrate)

      {:ok,
       %{
         camera_id: normalized.id,
         camera_name: Map.get(normalized, :name),
         source_type: normalized.source_type,
         source: %{device_path: normalized.device_path, backend: normalized.capture_backend},
         encoder: %{codec: :h264, mode: :hardware_preferred, bitrate: bitrate, keyint: fps * 2},
         outputs: %{webrtc: true, motion_detector: true},
         stream: %{resolution: resolution, fps: fps},
         color_config:
           Keyword.get_lazy(opts, :color_config, fn ->
             case NervesView.Camera.Registry.get_config(normalized.id) do
               {:ok, config} -> config
               _ -> %NervesView.Camera.Config{}
             end
           end)
       }}
    end
  end

  @is_host Mix.target() == :host
  defp default_stream_params do
    if @is_host do
      {1280, 720, 30, 2_000_000}
    else
      {640, 480, 15, 800_000}
    end
  end
end
