defmodule NervesView.Camera.Producer do
  @moduledoc "Behaviour and module selection for camera frame producers."

  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback snapshot(pid()) :: map()
  @callback stop(pid()) :: :ok

  @spec module_for(atom()) :: module()
  def module_for(:libcamera), do: NervesView.Camera.Producer.Libcamera
  def module_for(:v4l2), do: NervesView.Camera.Producer.V4L2
  def module_for(:rtsp), do: NervesView.Camera.Producer.RTSP
  def module_for(_), do: NervesView.Camera.Producer.Synthetic
end
