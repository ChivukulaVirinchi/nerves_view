defmodule NervesViewTest do
  use ExUnit.Case
  doctest NervesView

  test "greets the world" do
    assert NervesView.hello() == :world
  end
end
