defmodule NervesView.ModeTest do
  use ExUnit.Case, async: false

  alias NervesView.Mode

  test "reads and sets runtime mode" do
    assert :ok = Mode.set(:standalone)
    assert Mode.current() == :standalone

    assert :ok = Mode.set(:hub)
    assert Mode.current() == :hub
  end
end
