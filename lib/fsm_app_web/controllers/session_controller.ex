defmodule FSMAppWeb.SessionController do
  use FSMAppWeb, :controller

  alias FSMApp.Accounts
  alias FSMAppWeb.Auth.AuthHelpers
  alias FSMAppWeb.Auth.Guardian

  plug :put_layout, false when action in [:new, :create]

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign in", form_data: %{email: "", password: ""}, errors: [])
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        handle_successful_authentication(conn, user)

      {:error, reason} ->
        error_message = AuthHelpers.format_auth_error(reason)

        conn
        |> put_flash(:error, error_message)
        |> render(:new,
            page_title: "Sign in",
            form_data: %{email: email, password: ""},
            errors: [base: error_message]
          )
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
    create(conn, %{"user" => %{"email" => email, "password" => password}})
  end

  # Handle case where form data is malformed
  def create(conn, _params) do
    error_message = "Please provide both email and password"
    conn
    |> put_flash(:error, error_message)
    |> render(:new,
        page_title: "Sign in",
        form_data: %{email: "", password: ""},
        errors: [base: error_message]
      )
  end

  def delete(conn, _params) do
    conn
    |> AuthHelpers.clear_auth_session()
    |> configure_session(drop: true)
    |> put_flash(:info, "Signed out successfully")
    |> redirect(to: ~p"/")
  end

  # Private helper functions

  # Handle successful authentication with user status checking and tenant logic
  defp handle_successful_authentication(conn, user) do
    case AuthHelpers.check_user_can_login(user) do
      :ok ->
        # Create JWT token for better security
        case AuthHelpers.create_auth_token(user) do
          {:ok, token, _claims} ->
            # Handle tenant selection (future enhancement)
            # case AuthHelpers.handle_tenant_selection(user) do
            #   {:single_tenant, tenant} -> redirect_to_tenant_dashboard(conn, user, tenant, token)
            #   {:multiple_tenants, tenants} -> show_tenant_selection(conn, user, tenants)
            #   {:no_tenants, []} -> show_no_tenants_message(conn, user)
            # end

            # For now, simple login without tenant logic
            conn
            |> Guardian.Plug.sign_in(user)
            |> AuthHelpers.put_auth_session(user, token)
            |> put_flash(:info, "Welcome back, #{user.name || user.email}!")
            |> redirect(to: ~p"/control-panel")

          {:error, reason} ->
            conn
            |> put_flash(:error, AuthHelpers.format_auth_error(reason))
            |> render(:new, page_title: "Sign in")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, AuthHelpers.format_auth_error(reason))
        |> render(:new, page_title: "Sign in")
    end
  end
end
