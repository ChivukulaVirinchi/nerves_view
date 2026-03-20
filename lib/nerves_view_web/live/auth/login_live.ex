defmodule NervesViewWeb.Auth.LoginLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="auth-wrap">
      <div class="auth-card">
        <h1>Sign in</h1>
        <p class="muted">Access your local NervesView dashboard.</p>

        <form action={~p"/login"} method="post" class="auth-form">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <label for="email">Email</label>
          <input id="email" type="email" name="email" required autocomplete="email" />

          <label for="password">Password</label>
          <input
            id="password"
            type="password"
            name="password"
            required
            autocomplete="current-password"
          />

          <label class="check-row" for="remember_me">
            <input id="remember_me" type="checkbox" name="remember_me" value="true" />
            <span>Remember me</span>
          </label>

          <button type="submit">Login</button>
        </form>

        <p class="muted">No account yet? <a href={~p"/register"}>Create one</a></p>
      </div>
    </section>
    """
  end
end
