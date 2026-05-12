defmodule NervesViewWeb.Auth.RegisterLive do
  use NervesViewWeb, :live_view

  alias NervesView.Accounts.RegistrationParams

  @impl true
  def mount(_params, _session, socket) do
    role_hint =
      if NervesView.first_boot?(),
        do: "First account becomes admin.",
        else: "New account will have viewer access."

    changeset = RegistrationParams.changeset()

    {:ok,
     socket
     |> assign(page_title: "Register", role_hint: role_hint)
     |> assign_form(changeset)
     |> assign(trigger_submit: false)
     |> assign(handoff_token: nil)
     |> assign(check_errors: false)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      params
      |> RegistrationParams.changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    changeset = RegistrationParams.changeset(params)

    if changeset.valid? do
      email = Ecto.Changeset.get_field(changeset, :email)
      password = Ecto.Changeset.get_field(changeset, :password)
      role = if NervesView.first_boot?(), do: :admin, else: :viewer

      case NervesView.register_user(email, password, role) do
        {:ok, user} ->
          handoff = Phoenix.Token.sign(NervesViewWeb.Endpoint, "auth_handoff", user.id)

          {:noreply,
           socket
           |> assign(trigger_submit: true)
           |> assign(handoff_token: handoff)
           |> assign_form(changeset)}

        {:error, :email_taken} ->
          changeset =
            changeset
            |> Ecto.Changeset.add_error(:email, "already registered")
            |> Map.put(:action, :validate)

          {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

        {:error, reason} ->
          changeset =
            changeset
            |> Ecto.Changeset.add_error(:email, to_string(reason))
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
          <h1 class="pg-title">Create account</h1>
          <p class="pg-sub mt-1">{@role_hint}</p>
        </div>

        <.card>
          <:content>
            <.form
              for={@form}
              id="register-form"
              action={~p"/register"}
              phx-change="validate"
              phx-submit="submit"
              phx-trigger-action={@trigger_submit}
              class="grid gap-4"
            >
              <input type="hidden" name="user[handoff_token]" value={@handoff_token} />
              <.input field={@form[:email]} type="email" label="Email"
                autocomplete="email" placeholder="you@example.com" required />
              <.input field={@form[:password]} type="password" label="Password"
                description="Minimum 8 characters"
                autocomplete="new-password" placeholder="Choose a password" required />

              <.button type="submit" class="w-full" phx-disable-with="Creating account...">
                Create account
              </.button>
            </.form>
          </:content>
          <:footer>
            <p class="text-sm text-muted-foreground text-center w-full">
              Already registered?
              <.link navigate={~p"/login"} class="text-primary underline underline-offset-4 hover:opacity-80">Sign in</.link>
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
