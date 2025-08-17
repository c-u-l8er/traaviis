defmodule FSMAppWeb.Auth.OnMountCurrentUser do
  @moduledoc false
  import Phoenix.Component
  alias FSMApp.Accounts

  def on_mount(:default, _params, session, socket) do
    current_user = case session["user_id"] do
      nil -> nil
      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} -> user
          {:error, _reason} -> nil
        end
    end

    {:cont, assign(socket, current_user: current_user)}
  end
end
