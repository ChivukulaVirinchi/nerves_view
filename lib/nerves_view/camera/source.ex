defmodule NervesView.Camera.Source do
  @moduledoc "Behavior for camera source adapters."

  @callback normalize(map()) :: {:ok, map()} | {:error, atom()}
  @callback source_type() :: :libcamera | :v4l2 | :rtsp

  @spec module_for(:libcamera | :v4l2 | :rtsp) :: module()
  def module_for(:libcamera), do: NervesView.Camera.Source.Libcamera
  def module_for(:v4l2), do: NervesView.Camera.Source.V4L2
  def module_for(:rtsp), do: NervesView.Camera.Source.RTSP

  @spec infer_source_type(String.t()) :: :libcamera | :v4l2 | :rtsp
  def infer_source_type(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "rtsp://") -> :rtsp
      String.starts_with?(path, "/dev/video") -> :v4l2
      true -> :libcamera
    end
  end

  @spec normalize(map()) :: {:ok, map()} | {:error, atom()}
  def normalize(%{source_type: source_type} = attrs)
      when source_type in [:libcamera, :v4l2, :rtsp] do
    source_type
    |> module_for()
    |> apply(:normalize, [attrs])
  end

  def normalize(%{device_path: path} = attrs) when is_binary(path) do
    source_type = infer_source_type(path)
    normalize(Map.put(attrs, :source_type, source_type))
  end

  def normalize(_attrs), do: {:error, :unknown_source}
end
