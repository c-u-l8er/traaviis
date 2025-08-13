defmodule FSMAppWeb.Auth.RequireAuthLive do
  @moduledoc false
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if is_nil(socket.assigns[:current_user]) do
      {:halt, redirect(socket, to: "/sign-in")}
    else
      {:cont, socket}
    end
  end
end
