defmodule NervesViewWeb.SettingsLive do
  use NervesViewWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>Settings</h1>
      <p class="muted">System settings UI placeholder (Phase 7).</p>

      <div class="card-list">
        <article class="camera-card">
          <h2>Node mode</h2>
          <p>Standalone (default)</p>
        </article>

        <article class="camera-card">
          <h2>Network</h2>
          <p>mDNS broadcast enabled</p>
        </article>
      </div>
    </section>
    """
  end
end
