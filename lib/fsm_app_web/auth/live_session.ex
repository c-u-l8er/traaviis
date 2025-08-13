defmodule FSMAppWeb.Auth.LiveSession do
  @moduledoc false
  import Plug.Conn

  # Builds the session map that will be available to LiveViews as `session`
  # under the configured live_session in the router.
  def session(conn) do
    %{"user_id" => get_session(conn, :user_id)}
  end
end
