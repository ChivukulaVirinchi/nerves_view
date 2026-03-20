defmodule NervesView.Cluster.HeartbeatTest do
  use ExUnit.Case, async: false

  alias NervesView.Cluster.Heartbeat
  alias NervesView.Cluster.NodeRegistry

  setup do
    :ok = NodeRegistry.clear()
    :ok
  end

  test "heartbeat worker registers current node" do
    :ok = Heartbeat.beat_now()
    nodes = NodeRegistry.list()
    assert Enum.any?(nodes, &(&1.id == Atom.to_string(node())))
  end
end
