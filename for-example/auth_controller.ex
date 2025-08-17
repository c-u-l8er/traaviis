defmodule BrokenRecordWeb.AuthController do
  use BrokenRecordWeb, :controller

  @doc """
  Handles user logout by clearing authentication session and redirecting to login.
  """
  def logout(conn, _params) do
    conn
    |> BrokenRecordWeb.AuthPlug.clear_session()
    |> put_flash(:info, "You have been logged out successfully.")
    |> redirect(to: ~p"/auth")
  end

  @doc """
  Handles tenant switching by updating session with new tenant context token.
  """
  def switch_tenant(conn, %{"token" => token} = params) do
    return_to = params["return_to"] || "/dashboard"

    conn
    |> BrokenRecordWeb.AuthPlug.put_token_session(token)
    |> put_flash(:info, "Organization switched successfully.")
    |> redirect(to: return_to)
  end

  def switch_tenant(conn, _params) do
    conn
    |> put_flash(:error, "Invalid tenant switch request.")
    |> redirect(to: ~p"/dashboard")
  end
end
