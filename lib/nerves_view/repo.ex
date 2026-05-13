defmodule NervesView.Repo do
  use Ecto.Repo,
    otp_app: :nerves_view,
    adapter: Ecto.Adapters.SQLite3
end
