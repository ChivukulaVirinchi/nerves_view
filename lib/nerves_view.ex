defmodule NervesView do
  @moduledoc """
  Public API for the NervesView foundation phase.
  """

  alias NervesView.Camera.Registry

  @spec list_cameras() :: [NervesView.Camera.t()]
  def list_cameras do
    Registry.list()
  end

  @spec register_camera(map()) :: {:ok, NervesView.Camera.t()} | {:error, term()}
  def register_camera(attrs) when is_map(attrs) do
    Registry.upsert(attrs)
  end
end
