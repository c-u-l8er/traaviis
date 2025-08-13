defmodule FSMAppWeb.Auth.RequireAuth do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_user: nil}} = conn, _opts) do
    conn
    |> put_flash(:error, "Please sign in to continue")
    |> redirect(to: "/sign-in")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
