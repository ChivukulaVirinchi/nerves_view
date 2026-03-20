defmodule NervesView.Cluster.NodeRegistryTest do
  use ExUnit.Case, async: false

  alias NervesView.Cluster.NodeRegistry

  setup do
    :ok = NodeRegistry.clear()
    :ok
  end

  test "register/list/filter nodes" do
    assert {:ok, _hub} =
             NodeRegistry.register(%{id: "hub-1", mode: :hub, host: "hub.local", port: 4000})

    assert {:ok, _node} =
             NodeRegistry.register(%{id: "node-1", mode: :node, host: "node.local", port: 5000})

    assert [%{id: "hub-1", mode: :hub}, %{id: "node-1", mode: :node}] = NodeRegistry.list()
    assert [%{id: "node-1", mode: :node}] = NodeRegistry.list(mode: :node)
  end

  test "heartbeat updates last_seen_at and prune removes stale" do
    base = 1_700_000_000

    assert {:ok, _} =
             NodeRegistry.register(%{
               id: "node-2",
               mode: :node,
               host: "node2.local",
               port: 5001,
               last_seen_at: base
             })

    assert :ok = NodeRegistry.heartbeat("node-2", base + 10)
    assert {:ok, rec} = NodeRegistry.get("node-2")
    assert rec.last_seen_at == base + 10

    assert ["node-2"] = NodeRegistry.prune_stale(5, base + 20)
    assert [] = NodeRegistry.list()
  end

  test "rejects invalid node attrs" do
    assert {:error, :invalid_mode} =
             NodeRegistry.register(%{id: "bad", mode: :invalid, host: "x", port: 1})
  end
end
