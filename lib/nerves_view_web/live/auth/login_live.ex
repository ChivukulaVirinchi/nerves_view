defmodule NervesViewWeb.Auth.LoginLive do
  use NervesViewWeb, :live_view

  alias NervesView.Accounts.LoginParams

  @impl true
  def mount(_params, _session, socket) do
    changeset = LoginParams.changeset()

    {:ok,
     socket
     |> assign(page_title: "Login")
     |> assign_form(changeset)
     |> assign(trigger_submit: false)
     |> assign(handoff_token: nil)
     |> assign(check_errors: false)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      params
      |> LoginParams.changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    changeset = LoginParams.changeset(params)

    if changeset.valid? do
      email = Ecto.Changeset.get_field(changeset, :email)
      password = Ecto.Changeset.get_field(changeset, :password)

      case NervesView.login(email, password) do
        {:ok, %{user: user}} ->
          # Sign a short-lived token so the controller can set the session cookie
          # without re-authenticating
          handoff = Phoenix.Token.sign(NervesViewWeb.Endpoint, "auth_handoff", user.id)

          {:noreply,
           socket
           |> assign(trigger_submit: true)
           |> assign(handoff_token: handoff)
           |> assign_form(changeset)}

        {:error, _} ->
          changeset =
            changeset
            |> Ecto.Changeset.add_error(:email, "invalid email or password")
            |> Map.put(:action, :validate)

          {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
      end
    else
      {:noreply, socket |> assign(check_errors: true) |> assign_form(%{changeset | action: :validate})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="auth-wrap">
      <div class="w-full max-w-sm">
        <div class="text-center mb-6">
          <div class="inline-flex items-center gap-2 mb-3">
            <span class="auth-dot"></span>
            <span class="font-display text-lg font-bold">NervesView</span>
          </div>
          <h1 class="pg-title">Sign in</h1>
          <p class="pg-sub mt-1">Access your camera dashboard.</p>
        </div>

        <.card>
          <:content>
            <.form
              for={@form}
              id="login-form"
              action={~p"/login"}
              phx-change="validate"
              phx-submit="submit"
              phx-trigger-action={@trigger_submit}
              class="grid gap-4"
            >
              <input type="hidden" name="user[handoff_token]" value={@handoff_token} />
              <.input field={@form[:email]} type="email" label="Email"
                autocomplete="email" placeholder="you@example.com" required />
              <.input field={@form[:password]} type="password" label="Password"
                autocomplete="current-password" placeholder="Enter password" required />
              <.input field={@form[:remember_me]} type="checkbox" label="Remember me" />

              <.button type="submit" class="w-full" phx-disable-with="Signing in...">
                Sign in
              </.button>
            </.form>
          </:content>
          <:footer>
            <p class="text-sm text-muted-foreground text-center w-full">
              No account?
              <.link navigate={~p"/register"} class="text-primary underline underline-offset-4 hover:opacity-80">Register</.link>
            </p>
          </:footer>
        </.card>
      </div>
    </div>
    """
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end
end
