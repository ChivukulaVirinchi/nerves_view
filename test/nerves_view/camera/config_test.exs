defmodule NervesView.Camera.ConfigTest do
  use ExUnit.Case, async: true

  alias NervesView.Camera.Config

  test "casts known white balance and exposure values from strings" do
    assert {:ok, config} =
             Config.new(%{
               "awb_mode" => "daylight",
               "exposure_mode" => "short",
               "saturation" => "1.4"
             })

    assert config.awb_mode == :daylight
    assert config.exposure_mode == :short
    assert config.saturation == 1.4
  end

  test "falls back for unknown string values without creating atoms" do
    assert {:ok, config} =
             Config.new(%{
               "awb_mode" => "not-a-mode",
               "exposure_mode" => "not-an-exposure"
             })

    assert config.awb_mode == :auto
    assert config.exposure_mode == :normal
  end
end
