defmodule NervesViewWeb.RecordingsLive do
  use NervesViewWeb, :live_view

  import NervesViewWeb.Helpers

  alias NervesView.DVR.SegmentIndex

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Recordings")
     |> assign(cameras: NervesView.list_cameras())
     |> assign(camera_filter: "")
     |> assign(date_filter: "")
     |> assign(page: 1)
     |> assign(tz_offset: 0)
     |> assign_filter_form()
     |> load_clips()}
  end

  defp assign_filter_form(socket) do
    assign(socket, :filter_form,
      to_form(%{
        "camera_id" => socket.assigns.camera_filter,
        "date" => socket.assigns.date_filter
      }, as: "filter")
    )
  end

  @impl true
  def handle_event("tz:offset", %{"offset_minutes" => offset}, socket) do
    off = String.to_integer(offset)
    {:noreply, assign(socket, tz_offset: off)}
  end

  def handle_event("filter", %{"filter" => %{"camera_id" => cam, "date" => date}}, socket) do
    {:noreply,
     socket
     |> assign(camera_filter: cam, date_filter: date, page: 1)
     |> assign_filter_form()
     |> load_clips()}
  end

  def handle_event("page", %{"to" => to}, socket) do
    n = max(String.to_integer(to), 1)
    {:noreply, socket |> assign(page: n) |> paginate_visible()}
  end

  defp load_clips(socket) do
    {from, to} = date_window(socket.assigns.date_filter, socket.assigns.tz_offset)

    clips =
      socket.assigns.camera_filter
      |> case do
        "" -> SegmentIndex.all_clips(from: from, to: to)
        cam -> SegmentIndex.clips_for(cam, from: from, to: to)
      end
      |> Enum.sort_by(& &1.started_at, :desc)

    socket
    |> assign(all_clips: clips)
    |> assign(total: length(clips))
    |> paginate_visible()
  end

  defp paginate_visible(socket) do
    page = socket.assigns.page
    visible = socket.assigns.all_clips |> Enum.slice((page - 1) * @page_size, @page_size)

    socket
    |> assign(visible_clips: visible)
    |> assign(total_bytes: Enum.sum(Enum.map(socket.assigns.all_clips, & &1.size_bytes)))
  end

  defp date_window("", _tz_offset), do: {nil, nil}

  defp date_window(date_str, tz_offset) do
    date_to_utc_window(date_str, tz_offset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Recordings
        <:subtitle>{@total} clips · {format_bytes(@total_bytes)} on disk</:subtitle>
      </.header>

      <%!-- Filter row --%>
      <.card class="mt-5">
        <:content>
          <.form
            for={@filter_form}
            phx-change="filter"
            class="grid grid-cols-1 sm:grid-cols-3 gap-3"
          >
            <div>
              <label class="text-xs font-medium text-muted-foreground">Camera</label>
              <select
                name={@filter_form[:camera_id].name}
                class="input mt-1 w-full"
              >
                <option value="" selected={@camera_filter == ""}>All cameras</option>
                <%= for cam <- @cameras do %>
                  <option value={cam.id} selected={@camera_filter == cam.id}>{cam.name}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-muted-foreground">Date</label>
              <input
                type="date"
                name={@filter_form[:date].name}
                value={@filter_form[:date].value}
                class="input mt-1 w-full"
              />
            </div>
            <div class="self-end">
              <span class="text-xs text-muted-foreground">
                Page {@page} of {max(ceil(@total / 50), 1)}
              </span>
            </div>
          </.form>
        </:content>
      </.card>

      <%!-- Clips list --%>
      <%= if @visible_clips == [] do %>
        <.empty class="mt-8">
          <:title>No recordings match your filters</:title>
          <:description>
            Adjust the date or camera, or wait for fresh footage to be written.
          </:description>
        </.empty>
      <% else %>
        <.data_table rows={@visible_clips} class="mt-5">
          <:col :let={clip} label="Started">{format_ts(clip.started_at, @tz_offset)}</:col>
          <:col :let={clip} label="Camera">{clip.camera_id}</:col>
          <:col :let={clip} label="Length">{format_duration(clip.started_at, clip.ended_at)}</:col>
          <:col :let={clip} label="Size">{format_bytes(clip.size_bytes)}</:col>
          <:col :let={clip} label="Segments">{length(clip.segments)}</:col>
          <:action :let={clip}>
            <.button variant="outline" size="sm" navigate={~p"/recordings/#{clip.id}/play"}>
              Open
            </.button>
          </:action>
        </.data_table>

        <%!-- Pagination --%>
        <div class="flex items-center justify-between mt-4">
          <.button
            variant="ghost" size="sm"
            phx-click="page" phx-value-to={@page - 1}
            disabled={@page <= 1}>
            ← Prev
          </.button>
          <span class="text-xs text-muted-foreground">
            Showing {(@page - 1) * 50 + 1}–{min(@page * 50, @total)} of {@total}
          </span>
          <.button
            variant="ghost" size="sm"
            phx-click="page" phx-value-to={@page + 1}
            disabled={@page * 50 >= @total}>
            Next →
          </.button>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_ts(unix, tz_offset) when is_integer(unix) do
    fmt_ts_local(unix, tz_offset, "%b %d, %H:%M:%S")
  end

  defp format_ts(_, _tz_offset), do: "—"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_duration(started, ended) when is_integer(started) and is_integer(ended) do
    secs = max(ended - started, 0)

    cond do
      secs < 60 -> "#{secs}s"
      secs < 3600 -> "#{div(secs, 60)}m #{rem(secs, 60)}s"
      true -> "#{div(secs, 3600)}h #{div(rem(secs, 3600), 60)}m"
    end
  end

  defp format_duration(_, _), do: "—"
end
