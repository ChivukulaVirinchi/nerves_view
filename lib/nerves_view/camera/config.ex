defmodule NervesView.Camera.Config do
  @moduledoc """
  Per-camera color + stream tuning, persisted alongside the camera registry.

  Stream defaults are tuned for Pi Zero 2 W headroom:
    - 640x480 @ 10 fps, 600 kbps — readable detail, smooth-enough, leaves
      CPU for the Elixir-side NAL/RTP/SRTP path
  """

  defstruct awb_mode: :auto,
            saturation: 1.0,
            contrast: 1.0,
            sharpness: 1.0,
            exposure_mode: :normal,
            width: 640,
            height: 480,
            fps: 10,
            bitrate: 600_000

  @valid_awb_modes ~w(auto incandescent tungsten fluorescent indoor daylight cloudy)a
  @valid_exposure_modes ~w(normal short long)a

  @min_fps 1
  @max_fps 30
  @min_bitrate 100_000
  @max_bitrate 4_000_000

  @type t :: %__MODULE__{
          awb_mode: atom(),
          saturation: float(),
          contrast: float(),
          sharpness: float(),
          exposure_mode: atom(),
          width: pos_integer(),
          height: pos_integer(),
          fps: pos_integer(),
          bitrate: pos_integer()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) do
    {:ok,
     %__MODULE__{
       awb_mode: cast_awb(Map.get(attrs, "awb_mode") || Map.get(attrs, :awb_mode)),
       saturation: cast_float(Map.get(attrs, "saturation") || Map.get(attrs, :saturation), 1.0),
       contrast: cast_float(Map.get(attrs, "contrast") || Map.get(attrs, :contrast), 1.0),
       sharpness: cast_float(Map.get(attrs, "sharpness") || Map.get(attrs, :sharpness), 1.0),
       exposure_mode:
         cast_exposure(Map.get(attrs, "exposure_mode") || Map.get(attrs, :exposure_mode)),
       width: cast_resolution(Map.get(attrs, "width") || Map.get(attrs, :width), 640),
       height: cast_resolution(Map.get(attrs, "height") || Map.get(attrs, :height), 480),
       fps: cast_int(Map.get(attrs, "fps") || Map.get(attrs, :fps), 10, @min_fps, @max_fps),
       bitrate:
         cast_int(
           Map.get(attrs, "bitrate") || Map.get(attrs, :bitrate),
           600_000,
           @min_bitrate,
           @max_bitrate
         )
     }}
  end

  @spec from_opts(keyword()) :: t()
  def from_opts(opts) do
    awb = Keyword.get(opts, :awb, :auto)

    %__MODULE__{
      awb_mode: cast_awb(awb),
      saturation: Keyword.get(opts, :saturation, 1.0),
      contrast: Keyword.get(opts, :contrast, 1.0),
      sharpness: Keyword.get(opts, :sharpness, 1.0),
      exposure_mode: cast_exposure(Keyword.get(opts, :exposure, :normal)),
      width: Keyword.get(opts, :width, 640),
      height: Keyword.get(opts, :height, 480),
      fps: Keyword.get(opts, :fps, 10),
      bitrate: Keyword.get(opts, :bitrate, 600_000)
    }
  end

  defp cast_awb(nil), do: :auto
  defp cast_awb(mode) when is_atom(mode), do: if(mode in @valid_awb_modes, do: mode, else: :auto)

  defp cast_awb(mode) when is_binary(mode) do
    mode
    |> String.trim()
    |> String.downcase()
    |> then(fn value ->
      Enum.find(@valid_awb_modes, :auto, &(Atom.to_string(&1) == value))
    end)
  end

  defp cast_exposure(nil), do: :normal

  defp cast_exposure(mode) when is_atom(mode),
    do: if(mode in @valid_exposure_modes, do: mode, else: :normal)

  defp cast_exposure(mode) when is_binary(mode) do
    mode
    |> String.trim()
    |> String.downcase()
    |> then(fn value ->
      Enum.find(@valid_exposure_modes, :normal, &(Atom.to_string(&1) == value))
    end)
  end

  defp cast_float(nil, default), do: default
  defp cast_float(v, _default) when is_float(v), do: v
  defp cast_float(v, _default) when is_integer(v), do: v * 1.0

  defp cast_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> Float.round(f, 1)
      :error -> default
    end
  end

  defp cast_int(nil, default, _lo, _hi), do: default

  defp cast_int(v, _default, lo, hi) when is_integer(v),
    do: v |> Kernel.max(lo) |> Kernel.min(hi)

  defp cast_int(v, default, lo, hi) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n |> Kernel.max(lo) |> Kernel.min(hi)
      :error -> default
    end
  end

  defp cast_int(_, default, _lo, _hi), do: default

  defp cast_resolution(nil, default), do: default

  defp cast_resolution(v, _default) when is_integer(v) and v >= 160 and v <= 1920, do: v

  defp cast_resolution(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} when n >= 160 and n <= 1920 -> n
      _ -> default
    end
  end

  defp cast_resolution(_, default), do: default
end
