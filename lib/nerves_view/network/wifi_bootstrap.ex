defmodule NervesView.Network.WiFiBootstrap do
  @moduledoc """
  At boot, read `/data/wifi.conf` (JSON: `{"ssid": "...", "psk": "..."}`) and
  configure `wlan0` via VintageNet so the Pi joins home WiFi automatically.

  Missing file → silent no-op (USB OTG / wired stays as the fallback).
  Malformed file → logged warning, no crash.
  """

  require Logger

  @path "/data/wifi.conf"

  @spec ensure_configured() :: :ok
  def ensure_configured do
    with {:ok, raw} <- File.read(@path),
         {:ok, %{"ssid" => ssid, "psk" => psk}} when is_binary(ssid) and is_binary(psk) <-
           Jason.decode(raw),
         :ok <- configure_wifi(ssid, psk) do
      Logger.info("WiFi configured from #{@path}: SSID=#{ssid}")
      :ok
    else
      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("WiFi bootstrap from #{@path} skipped: #{inspect(reason)}")
        :ok

      other ->
        Logger.warning(
          "WiFi bootstrap from #{@path} skipped: expected %{\"ssid\":..., \"psk\":...}, got #{inspect(other)}"
        )

        :ok
    end
  end

  defp configure_wifi(ssid, psk) do
    if Code.ensure_loaded?(VintageNet) do
      apply(VintageNet, :configure, [
        "wlan0",
        %{
          type: VintageNetWiFi,
          ipv4: %{method: :dhcp},
          vintage_net_wifi: %{
            networks: [%{ssid: ssid, psk: psk, key_mgmt: :wpa_psk}]
          }
        }
      ])
    else
      {:error, :vintage_net_not_loaded}
    end
  end
end
