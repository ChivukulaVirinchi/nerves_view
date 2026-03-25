defmodule NervesViewWeb.Auth.SetupLive do
  use NervesViewWeb, :live_view

  alias NervesViewWeb.RegistrationController

  @impl true
  def mount(_params, _session, socket) do
    case RegistrationController.first_boot?() do
      true ->
        {:ok, assign(socket, page_title: "Initial Setup")}

      false ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="auth-wrap">
      <div class="auth-card">
        <h1>Initial setup</h1>
        <p class="muted">Create the first admin account to start using NervesView.</p>

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

          <button type="submit">Create admin account</button>
        </form>
      </div>
    </section>
    """
  end
end
