defmodule NervesViewWeb.CoreComponents do
  use Phoenix.Component

  attr(:flash, :map, default: %{})

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" class="flash-group">
      <%= if info = Phoenix.Flash.get(@flash, :info) do %>
        <p class="flash flash-info">{info}</p>
      <% end %>
      <%= if error = Phoenix.Flash.get(@flash, :error) do %>
        <p class="flash flash-error">{error}</p>
      <% end %>
    </div>
    """
  end
end
