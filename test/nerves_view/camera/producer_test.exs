defmodule NervesView.Camera.ProducerTest do
  use ExUnit.Case, async: true

  alias NervesView.Camera.Producer

  test "resolves producer modules by source type" do
    assert Producer.module_for(:libcamera) == NervesView.Camera.Producer.Libcamera
    assert Producer.module_for(:v4l2) == NervesView.Camera.Producer.V4L2
    assert Producer.module_for(:rtsp) == NervesView.Camera.Producer.RTSP
    assert Producer.module_for(:unknown) == NervesView.Camera.Producer.Synthetic
  end
end
