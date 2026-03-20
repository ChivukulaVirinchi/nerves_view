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

  scope "/", NervesViewWeb do
    pipe_through([:browser])

    get("/", RedirectController, :home)
    get("/recordings/:id/playlist.m3u8", RecordingController, :playlist)
    post("/login", SessionController, :create)
    post("/register", RegistrationController, :create)
    get("/logout", SessionController, :delete)
  end

  scope "/api", NervesViewWeb do
    pipe_through([:api])

    post("/webrtc/offer", WebRTCController, :offer)
    post("/webrtc/answer", WebRTCController, :answer)
    post("/webrtc/ice-candidate", WebRTCController, :ice_candidate)
  end

  scope "/", NervesViewWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{NervesViewWeb.UserAuth, :mount_current_user}] do
      live("/login", Auth.LoginLive, :new)
      live("/register", Auth.RegisterLive, :new)
    end
  end

  scope "/", NervesViewWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :require_authenticated_user,
      on_mount: [{NervesViewWeb.UserAuth, :ensure_authenticated}] do
      live("/dashboard", DashboardLive, :index)
      live("/settings", SettingsLive, :index)
      live("/recordings", RecordingsLive, :index)
    end
  end
end
