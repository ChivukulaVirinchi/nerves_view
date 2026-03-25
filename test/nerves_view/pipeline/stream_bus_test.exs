defmodule NervesView.Pipeline.StreamBusTest do
  use ExUnit.Case, async: false

  alias NervesView.Pipeline.StreamBus

  test "subscribes and receives published frame" do
    assert :ok = StreamBus.subscribe("cam-bus")

    StreamBus.publish("cam-bus", %{payload: <<1, 2, 3>>, sequence_number: 1, timestamp: 90_000})

    assert_receive {:pipeline_frame, "cam-bus", frame}
    assert frame.payload == <<1, 2, 3>>

    assert :ok = StreamBus.unsubscribe("cam-bus")
  end
end
