defmodule NervesView.Pipeline.MotionDetectorTest do
  use ExUnit.Case, async: true

  alias NervesView.Pipeline.MotionDetector

  test "detects movement above threshold" do
    prev = [0, 0, 0, 0, 0, 0]
    curr = [0, 2, 2, 0, 0, 0]

    assert {:ok, result} = MotionDetector.detect(prev, curr, threshold: 0.2, min_delta: 1)
    assert result.motion? == true
    assert result.changed_pixels == 2
  end

  test "handles invalid frame payload" do
    assert {:error, :invalid_frames} = MotionDetector.detect([0], [], [])
  end
end
