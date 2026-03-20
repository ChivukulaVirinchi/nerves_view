defmodule NervesViewWeb.Auth.RegisterLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    role_hint =
      if NervesView.list_users() == [] do
        "First account becomes admin."
      else
        "New account will have viewer access."
      end

    {:ok, assign(socket, page_title: "Register", role_hint: role_hint)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="auth-wrap">
      <div class="auth-card">
        <h1>Create account</h1>
        <p class="muted">{@role_hint}</p>

        <form action={~p"/register"} method="post" class="auth-form">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <label for="email">Email</label>
          <input id="email" type="email" name="email" required autocomplete="email" />

          <label for="password">Password</label>
          <input
            id="password"
            type="password"
            name="password"
            minlength="8"
            required
            autocomplete="new-password"
          />

          <button type="submit">Register</button>
        </form>

        <p class="muted">Already have an account? <a href={~p"/login"}>Sign in</a></p>
      </div>
    </section>
    """
  end
end
