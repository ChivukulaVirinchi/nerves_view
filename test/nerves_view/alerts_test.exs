defmodule NervesView.AlertsTest do
  use ExUnit.Case, async: false

  alias NervesView.Alerts
  alias NervesView.PubSub

  setup do
    :ok = Alerts.clear()
    :ok
  end

  test "creates motion alert and lists it" do
    now = 1_700_300_000
    assert {:ok, alert} = Alerts.notify_motion("front-door", now)
    assert alert.camera_id == "front-door"

    assert [%{camera_id: "front-door"}] = Alerts.list()
    assert [%{camera_id: "front-door"}] = Alerts.list(camera_id: "front-door")
  end

  test "throttles rapid notifications per camera" do
    now = 1_700_300_100

    assert {:ok, _alert} = Alerts.notify_motion("garage", now, throttle_seconds: 10)
    assert {:error, :throttled} = Alerts.notify_motion("garage", now + 5, throttle_seconds: 10)
    assert {:ok, _alert} = Alerts.notify_motion("garage", now + 11, throttle_seconds: 10)
  end

  test "broadcasts motion alerts over pubsub" do
    Phoenix.PubSub.subscribe(PubSub, "alerts:motion")

    assert {:ok, alert} = Alerts.notify_motion("yard", 1_700_300_222)
    assert_receive {:motion_alert, %{camera_id: "yard", id: id}}
    assert id == alert.id
  end
end
