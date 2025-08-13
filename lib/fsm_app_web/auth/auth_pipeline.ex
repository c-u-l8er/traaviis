defmodule FSMAppWeb.Auth.Pipeline do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller

  alias FSMApp.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil -> assign(conn, :current_user, nil)
      user_id -> assign(conn, :current_user, Accounts.get_user!(user_id))
    end
  end
end
