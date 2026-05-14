Application.put_env(:phoenix, :plug_init_mode, :runtime)

# Fresh test DB each run: delete the SQLite file, then bring up the Repo
# (without starting the full Application) and run migrations.
case Application.get_env(:nerves_view, NervesView.Repo)[:database] do
  nil ->
    :ok

  path ->
    File.mkdir_p!(Path.dirname(path))
    File.rm(path)
end

{:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

case NervesView.Repo.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

{:ok, _, _} =
  Ecto.Migrator.with_repo(NervesView.Repo, fn repo ->
    Ecto.Migrator.run(repo, :up, all: true)
  end)

ExUnit.start()
