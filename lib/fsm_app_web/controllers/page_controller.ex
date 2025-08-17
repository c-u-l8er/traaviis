defmodule FSMAppWeb.PageController do
  use FSMAppWeb, :controller

  plug :put_layout, false

  def home(conn, _params) do
    render(conn, :home, page_title: "TRAAVIIS")
  end

  def health(conn, _params) do
    # Simple health check for fly.io monitoring
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }))
  end
end
