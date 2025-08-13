defmodule FSMAppWeb.SessionController do
  use FSMAppWeb, :controller

  alias FSMApp.Accounts

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign in")
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Welcome back")
        |> redirect(to: ~p"/control-panel")

      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid credentials")
        |> render(:new, page_title: "Sign in")
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
    create(conn, %{"user" => %{"email" => email, "password" => password}})
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/")
  end
end
