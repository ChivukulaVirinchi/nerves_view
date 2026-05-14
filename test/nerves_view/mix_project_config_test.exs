defmodule NervesView.MixProjectConfigTest do
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)

  test "phx.server defaults to the host target and code reloader listener is configured" do
    assert NervesView.MixProject.cli()[:preferred_targets][:"phx.server"] == :host
    assert Phoenix.CodeReloader in NervesView.MixProject.project()[:listeners]
  end

  test "config refuses to run phx.server under target dev" do
    config = File.read!(Path.join(@root, "config/config.exs"))

    assert config =~ "config_env() == :dev"
    assert config =~ "Mix.target() != :host"
    assert config =~ "\"phx.server\" in System.argv()"
    assert config =~ "MIX_TARGET=host mix phx.server"
  end

  test "target-only Nerves runtime applications do not start during host test/dev runs" do
    deps = NervesView.MixProject.project()[:deps]

    assert {:logger_backends, "~> 1.0"} in deps

    assert {:nerves_runtime, "~> 0.13.0", nerves_runtime_opts} =
             Enum.find(deps, &match?({:nerves_runtime, _, _}, &1))

    assert nerves_runtime_opts[:runtime] == false

    assert {:nerves_pack, "~> 0.7.1", nerves_pack_opts} =
             Enum.find(deps, &match?({:nerves_pack, _, _}, &1))

    assert nerves_pack_opts[:runtime] == false
  end

  test "dev endpoint watchers are opt-in and live reload avoids generated build paths" do
    previous = System.get_env("NERVES_VIEW_DEV_WATCHERS")

    try do
      System.delete_env("NERVES_VIEW_DEV_WATCHERS")
      config = read_config("config/dev.exs", env: :dev, target: :host)
      endpoint = config[:nerves_view][NervesViewWeb.Endpoint]
      assert endpoint[:watchers] == []

      live_reload = config[:phoenix_live_reload]
      assert live_reload[:backend] == :fs_poll
      assert live_reload[:dirs] == ["assets", "lib", "priv/static"]

      System.put_env("NERVES_VIEW_DEV_WATCHERS", "1")
      config = read_config("config/dev.exs", env: :dev, target: :host)
      endpoint = config[:nerves_view][NervesViewWeb.Endpoint]
      assert Keyword.has_key?(endpoint[:watchers], :esbuild)
      assert Keyword.has_key?(endpoint[:watchers], :tailwind)
    after
      restore_env("NERVES_VIEW_DEV_WATCHERS", previous)
    end
  end

  test "target config does not use deprecated logger backends config" do
    target_config = File.read!(Path.join(@root, "config/target.exs"))

    refute target_config =~ "config :logger, backends:"
    refute target_config =~ "backends: [RingLogger]"
  end

  defp read_config(path, opts) do
    @root
    |> Path.join(path)
    |> Config.Reader.read!(opts)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
