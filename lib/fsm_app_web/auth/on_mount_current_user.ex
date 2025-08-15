defmodule FSMAppWeb.Auth.OnMountCurrentUser do
  @moduledoc false
  import Phoenix.Component
  alias FSMApp.Accounts

  def on_mount(:default, _params, session, socket) do
    current_user = case session["user_id"] do
      nil -> nil
      user_id -> Accounts.get_user!(user_id)
    end

    {:cont, assign(socket, current_user: current_user)}
  end
end
