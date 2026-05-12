defmodule NervesView.Camera.Producer do
  @moduledoc "Behaviour and module selection for camera frame producers."

  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback snapshot(pid()) :: map()
  @callback stop(pid()) :: :ok

  @spec module_for(atom()) :: module()
  def module_for(:libcamera), do: NervesView.Camera.Producer.Libcamera
  def module_for(:synthetic), do: NervesView.Camera.Producer.Synthetic
  def module_for(other), do: raise("Unsupported camera source type: #{inspect(other)}")
end
