defmodule NervesViewWeb.Router do
  use NervesViewWeb, :router

  import NervesViewWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {NervesViewWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :authenticated_api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:fetch_current_user)
    plug(:require_authenticated_api)
  end

  scope "/", NervesViewWeb do
    pipe_through([:browser])

    get("/", Plugs.RootRedirect, [])
    get("/recordings/:id/playlist.m3u8", RecordingController, :playlist)
    get("/recordings/:id/segments/:segment", RecordingController, :segment)
    get("/recordings/:id/download", RecordingController, :download)
    get("/cameras/:camera_id/live.m3u8", RecordingController, :live_playlist)
    get("/cameras/:camera_id/segments/:segment", RecordingController, :live_segment)
    post("/login", SessionController, :create)
    post("/register", RegistrationController, :create)
    get("/logout", SessionController, :delete)
  end

  scope "/api", NervesViewWeb do
    pipe_through([:api])

    post("/webrtc/offer", WebRTCController, :offer)
    post("/webrtc/answer", WebRTCController, :answer)
    post("/webrtc/ice-candidate", WebRTCController, :ice_candidate)
    post("/webrtc/close", WebRTCController, :close)
  end

  scope "/api", NervesViewWeb do
    pipe_through([:authenticated_api])

    get("/dvr/:camera_id/playlist.m3u8", DVRController, :playlist)
    get("/dvr/:camera_id/segments/:filename", DVRController, :segment)
    get("/dvr/:camera_id/timeline", DVRController, :timeline)
  end

  scope "/", NervesViewWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{NervesViewWeb.UserAuth, :mount_current_user}] do
      live("/setup", Auth.SetupLive, :new)
      live("/login", Auth.LoginLive, :new)
      live("/register", Auth.RegisterLive, :new)
    end
  end

  scope "/", NervesViewWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :require_authenticated_user,
      on_mount: [{NervesViewWeb.UserAuth, :ensure_authenticated}] do
      live("/dashboard", DashboardLive, :index)
      live("/cameras/:id", CameraLive, :show)
      live("/recordings", RecordingsLive, :index)
      live("/recordings/:id/play", ClipPlayerLive, :show)
    end

    live_session :require_admin_user,
      on_mount: [{NervesViewWeb.UserAuth, :ensure_admin}] do
      live("/settings", SettingsLive, :index)
    end
  end
end
