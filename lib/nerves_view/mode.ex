defmodule NervesView.Mode do
  @moduledoc "Runtime mode helper (:hub | :node | :standalone)."

  @type t :: :hub | :node | :standalone

  @spec current() :: t()
  def current do
    Application.get_env(:nerves_view, :mode, :standalone)
  end

  @spec set(t()) :: :ok
  def set(mode) when mode in [:hub, :node, :standalone] do
    Application.put_env(:nerves_view, :mode, mode)
    :ok
  end
end
