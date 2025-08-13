defmodule FSMAppWeb.PageController do
  use FSMAppWeb, :controller

  plug :put_layout, false

  def home(conn, _params) do
    render(conn, :home, page_title: "TRAAVIIS")
  end
end
