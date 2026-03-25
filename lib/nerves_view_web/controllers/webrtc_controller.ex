defmodule NervesViewWeb.WebRTCController do
  use NervesViewWeb, :controller

  alias NervesView.Camera.Registry
  alias NervesView.Streaming.MediaBridge
  alias NervesView.Streaming.Signaling

  def offer(conn, %{"camera_id" => camera_id, "viewer_id" => viewer_id}) do
    with {:ok, _camera} <- Registry.get(camera_id),
         {:ok, session_id, offer_sdp} <-
           Signaling.create_offer(camera_id, viewer_id, MediaBridge.offer_sdp(camera_id)) do
      json(conn, %{session_id: session_id, offer_sdp: offer_sdp})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "camera_not_found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason)})
    end
  end

  def offer(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "camera_id_and_viewer_id_required"})
  end

  def answer(conn, %{"session_id" => session_id, "answer_sdp" => answer_sdp}) do
    case Signaling.apply_answer(session_id, answer_sdp) do
      :ok ->
        :ok = Signaling.mark_connected(session_id)
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session_not_found"})
    end
  end

  def answer(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "session_id_and_answer_sdp_required"})
  end

  def ice_candidate(conn, %{"session_id" => session_id, "role" => role, "candidate" => candidate}) do
    with {:ok, role_atom} <- parse_role(role),
         :ok <- Signaling.add_ice_candidate(session_id, role_atom, candidate) do
      json(conn, %{ok: true})
    else
      {:error, :invalid_role} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_role"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session_not_found"})
    end
  end

  def ice_candidate(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "session_id_role_candidate_required"})
  end

  defp parse_role("viewer"), do: {:ok, :viewer}
  defp parse_role("publisher"), do: {:ok, :publisher}
  defp parse_role(_), do: {:error, :invalid_role}
end
