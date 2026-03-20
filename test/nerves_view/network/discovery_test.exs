defmodule NervesView.Network.DiscoveryTest do
  use ExUnit.Case, async: false

  alias NervesView.Network.Discovery

  setup do
    :ok = Discovery.clear()
    :ok
  end

  test "announce and list services" do
    assert {:ok, _svc} =
             Discovery.announce(%{
               service_id: "svc-1",
               node_id: "node-1",
               camera_id: "cam-1",
               host: "node-1.local",
               port: 4100
             })

    assert [%{service_id: "svc-1", camera_id: "cam-1"}] = Discovery.list()
  end

  test "prune stale services" do
    base = 1_700_000_000

    assert {:ok, _svc} =
             Discovery.announce(%{
               service_id: "svc-2",
               node_id: "node-2",
               camera_id: "cam-2",
               host: "node-2.local",
               port: 4101,
               last_seen_at: base
             })

    assert ["svc-2"] = Discovery.prune_stale(5, base + 10)
    assert [] = Discovery.list()
  end
end
