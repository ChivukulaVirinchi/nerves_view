defmodule NervesView.Camera.Config do
  @moduledoc """
  Per-camera color + stream + orientation tuning, persisted alongside the
  camera registry.

  Stream defaults are tuned for Pi Zero 2 W *unattended* operation:
    - 480x360 @ 8 fps, 400 kbps — keeps the BEAM's per-frame NAL/RTP/SRTP
      load down so the SoC has headroom for the encoder + WiFi stack
      without baking the silicon over months of continuous use.

  Users can dial these up per-camera from the live view popover when their
  particular Pi can take it.
  """

  defstruct awb_mode: :auto,
            saturation: 1.0,
            contrast: 1.0,
            sharpness: 1.0,
            exposure_mode: :normal,
            width: 480,
            height: 360,
            fps: 8,
            bitrate: 400_000,
            rotation: 0,
            hflip: false,
            vflip: false

  @valid_awb_modes ~w(auto incandescent tungsten fluorescent indoor daylight cloudy)a
  @valid_exposure_modes ~w(normal short long)a
  @valid_rotations [0, 180]

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
          bitrate: pos_integer(),
          rotation: 0 | 180,
          hflip: boolean(),
          vflip: boolean()
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
       width: cast_resolution(Map.get(attrs, "width") || Map.get(attrs, :width), 480),
       height: cast_resolution(Map.get(attrs, "height") || Map.get(attrs, :height), 360),
       fps: cast_int(Map.get(attrs, "fps") || Map.get(attrs, :fps), 8, @min_fps, @max_fps),
       bitrate:
         cast_int(
           Map.get(attrs, "bitrate") || Map.get(attrs, :bitrate),
           400_000,
           @min_bitrate,
           @max_bitrate
         ),
       rotation: cast_rotation(Map.get(attrs, "rotation") || Map.get(attrs, :rotation)),
       hflip: cast_bool(Map.get(attrs, "hflip") || Map.get(attrs, :hflip), false),
       vflip: cast_bool(Map.get(attrs, "vflip") || Map.get(attrs, :vflip), false)
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
      width: Keyword.get(opts, :width, 480),
      height: Keyword.get(opts, :height, 360),
      fps: Keyword.get(opts, :fps, 8),
      bitrate: Keyword.get(opts, :bitrate, 400_000),
      rotation: cast_rotation(Keyword.get(opts, :rotation, 0)),
      hflip: Keyword.get(opts, :hflip, false),
      vflip: Keyword.get(opts, :vflip, false)
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

  defp cast_rotation(nil), do: 0
  defp cast_rotation(v) when v in @valid_rotations, do: v

  defp cast_rotation(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} when n in @valid_rotations -> n
      _ -> 0
    end
  end

  defp cast_rotation(_), do: 0

  defp cast_bool(nil, default), do: default
  defp cast_bool(true, _default), do: true
  defp cast_bool(false, _default), do: false
  # HTML checkbox sends "on" / "true". Absent checkbox sends nothing — defaults
  # to false from the `nil` clause above when the form omits the field.
  defp cast_bool("true", _default), do: true
  defp cast_bool("false", _default), do: false
  defp cast_bool("on", _default), do: true
  defp cast_bool("off", _default), do: false
  defp cast_bool(_, default), do: default
end
