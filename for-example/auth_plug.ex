defmodule BrokenRecordWeb.AuthPlug do
  @moduledoc """
  Authentication plug for LiveViews.

  Handles JWT token verification and sets user/tenant context
  for authenticated LiveView sessions.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, put_private: 3, push_redirect: 2]

  alias BrokenRecord.Guardian

  @doc """
  Assigns authenticated user and tenant context to LiveView socket.

  Expects a valid JWT token in session or redirect to login.
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session do
      %{"token" => token} ->
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            case Guardian.resource_from_claims(claims) do
              {:ok, %{user: user, tenant: tenant_id, member: member}} ->
                # Check if user is allowed to access the system
                case BrokenRecord.Accounts.check_user_can_login(user) do
                  :ok ->
                    # Load the full tenant data
                    case BrokenRecord.Tenants.get_tenant(tenant_id) do
                      {:ok, tenant} ->
                        socket =
                          socket
                          |> assign(:current_user, user)
                          |> assign(:current_tenant_id, tenant_id)
                          |> assign(:current_tenant, tenant)
                          |> assign(:current_member, member)
                          |> put_private(:session_data, %{
                            "user_id" => user.id,
                            "tenant_id" => tenant_id
                          })

                        {:cont, socket}

                      {:error, :not_found} ->
                        {:halt, push_redirect(socket, to: "/auth")}
                    end

                  {:error, :user_suspended} ->
                    # User is suspended - log them out
                    {:halt,
                     socket
                     |> put_flash(:error, "🚫 Your account has been suspended. Please contact support.")
                     |> push_redirect(to: "/auth")}

                  {:error, _} ->
                    # User cannot login for other reasons
                    {:halt, push_redirect(socket, to: "/auth")}
                end

              {:ok, _user} ->
                # User authenticated but no tenant context - redirect to tenant selection
                {:halt, push_redirect(socket, to: "/auth")}

              {:error, _reason} ->
                # Invalid token - redirect to login
                {:halt, push_redirect(socket, to: "/auth")}
            end

          {:error, _reason} ->
            # Invalid token - redirect to login
            {:halt, push_redirect(socket, to: "/auth")}
        end

      %{"user_id" => user_id, "tenant_id" => tenant_id} ->
        # Session-based authentication (fallback)
        case BrokenRecord.Accounts.get_user(user_id) do
          {:ok, user} ->
            # Check if user is allowed to access the system
            case BrokenRecord.Accounts.check_user_can_login(user) do
              :ok ->
                case BrokenRecord.Tenants.get_member(tenant_id, user_id) do
                  {:ok, member} ->
                    case BrokenRecord.Tenants.get_tenant(tenant_id) do
                      {:ok, tenant} ->
                        socket =
                          socket
                          |> assign(:current_user, user)
                          |> assign(:current_tenant_id, tenant_id)
                          |> assign(:current_tenant, tenant)
                          |> assign(:current_member, member)
                          |> put_private(:session_data, %{
                            "user_id" => user_id,
                            "tenant_id" => tenant_id
                          })

                        {:cont, socket}

                      {:error, :not_found} ->
                        {:halt, push_redirect(socket, to: "/auth")}
                    end

                  {:error, _} ->
                    {:halt, push_redirect(socket, to: "/auth")}
                end

              {:error, :user_suspended} ->
                # User is suspended - log them out
                {:halt,
                 socket
                 |> put_flash(:error, "🚫 Your account has been suspended. Please contact support.")
                 |> push_redirect(to: "/auth")}

              {:error, _} ->
                # User cannot login for other reasons
                {:halt, push_redirect(socket, to: "/auth")}
            end

          {:error, _} ->
            {:halt, push_redirect(socket, to: "/auth")}
        end

      _ ->
        # No authentication - redirect to login
        {:halt, push_redirect(socket, to: "/auth")}
    end
  end

  def on_mount(:maybe_authenticated, _params, session, socket) do
    case session do
      %{"token" => token} ->
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            case Guardian.resource_from_claims(claims) do
              {:ok, %{user: user, tenant: tenant_id, member: member}} ->
                # Check if user is allowed to access the system
                case BrokenRecord.Accounts.check_user_can_login(user) do
                  :ok ->
                    case BrokenRecord.Tenants.get_tenant(tenant_id) do
                      {:ok, tenant} ->
                        socket =
                          socket
                          |> assign(:current_user, user)
                          |> assign(:current_tenant_id, tenant_id)
                          |> assign(:current_tenant, tenant)
                          |> assign(:current_member, member)

                        {:cont, socket}

                      {:error, :not_found} ->
                        socket =
                          socket
                          |> assign(:current_user, user)
                          |> assign(:current_tenant_id, nil)
                          |> assign(:current_tenant, nil)
                          |> assign(:current_member, nil)

                        {:cont, socket}
                    end

                  {:error, _} ->
                    # User cannot login - treat as unauthenticated
                    socket =
                      socket
                      |> assign(:current_user, nil)
                      |> assign(:current_tenant_id, nil)
                      |> assign(:current_tenant, nil)
                      |> assign(:current_member, nil)

                    {:cont, socket}
                end

              {:ok, user} ->
                socket =
                  socket
                  |> assign(:current_user, user)
                  |> assign(:current_tenant_id, nil)
                  |> assign(:current_tenant, nil)
                  |> assign(:current_member, nil)
                {:cont, socket}

              {:error, _} ->
                socket =
                  socket
                  |> assign(:current_user, nil)
                  |> assign(:current_tenant_id, nil)
                  |> assign(:current_member, nil)

                {:cont, socket}
            end

          {:error, _} ->
            socket =
              socket
              |> assign(:current_user, nil)
              |> assign(:current_tenant_id, nil)
              |> assign(:current_tenant, nil)
              |> assign(:current_member, nil)

            {:cont, socket}
        end

      %{"user_id" => user_id, "tenant_id" => tenant_id} ->
        case BrokenRecord.Accounts.get_user(user_id) do
          {:ok, user} ->
            # Check if user is allowed to access the system
            case BrokenRecord.Accounts.check_user_can_login(user) do
              :ok ->
                case BrokenRecord.Tenants.get_member(tenant_id, user_id) do
                  {:ok, member} ->
                    case BrokenRecord.Tenants.get_tenant(tenant_id) do
                      {:ok, tenant} ->
                        socket =
                          socket
                          |> assign(:current_user, user)
                          |> assign(:current_tenant_id, tenant_id)
                          |> assign(:current_tenant, tenant)
                          |> assign(:current_member, member)

                        {:cont, socket}

                      {:error, :not_found} ->
                        socket =
                          socket
                          |> assign(:current_user, user)
                          |> assign(:current_tenant_id, nil)
                          |> assign(:current_tenant, nil)
                          |> assign(:current_member, nil)
                        {:cont, socket}
                    end

                  {:error, _} ->
                    socket =
                      socket
                      |> assign(:current_user, user)
                      |> assign(:current_tenant_id, nil)
                      |> assign(:current_tenant, nil)
                      |> assign(:current_member, nil)
                    {:cont, socket}
                end

              {:error, _} ->
                # User cannot login - treat as unauthenticated
                socket =
                  socket
                  |> assign(:current_user, nil)
                  |> assign(:current_tenant_id, nil)
                  |> assign(:current_tenant, nil)
                  |> assign(:current_member, nil)
                {:cont, socket}
            end

          {:error, _} ->
            socket =
              socket
              |> assign(:current_user, nil)
              |> assign(:current_tenant_id, nil)
              |> assign(:current_tenant, nil)
              |> assign(:current_member, nil)

            {:cont, socket}
        end

      _ ->
        socket =
          socket
          |> assign(:current_user, nil)
          |> assign(:current_tenant_id, nil)
          |> assign(:current_member, nil)

        {:cont, socket}
    end
  end

  def on_mount(:require_admin, _params, _session, socket) do
    case socket.assigns do
      %{current_member: %{tenant_role: role}} when role in [:owner, :admin] ->
        {:cont, socket}

      _ ->
        {:halt,
         socket
         |> put_flash(:error, "Admin access required")
         |> push_redirect(to: "/dashboard")}
    end
  end

  @doc """
  Requires specific permissions within the current tenant.
  """
  def require_permission(permissions) when is_list(permissions) do
    fn :ensure_authenticated, _params, _session, socket ->
      case socket.assigns do
        %{current_member: %{permissions: user_permissions}} ->
          if Enum.any?(permissions, fn perm -> perm in user_permissions end) do
            {:cont, socket}
          else
            {:halt,
             socket
             |> put_flash(:error, "Insufficient permissions")
             |> push_redirect(to: "/dashboard")}
          end

        _ ->
          {:halt, push_redirect(socket, to: "/auth")}
      end
    end
  end

  @doc """
  Extracts JWT token from session or query parameters.
  """
  def extract_token(%{"token" => token}), do: {:ok, token}
  def extract_token(_), do: {:error, :no_token}

  @doc """
  Sets authentication context in session for JWT token.
  """
  def put_token_session(conn, token) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, %{user: user, tenant: tenant_id, member: _member}} ->
            conn
            |> Plug.Conn.put_session("token", token)
            |> Plug.Conn.put_session("user_id", user.id)
            |> Plug.Conn.put_session("tenant_id", tenant_id)

          {:ok, user} ->
            conn
            |> Plug.Conn.put_session("token", token)
            |> Plug.Conn.put_session("user_id", user.id)

          {:error, _} ->
            conn
        end

      {:error, _} ->
        conn
    end
  end

  @doc """
  Clears authentication session.
  """
  def clear_session(conn) do
    conn
    |> Plug.Conn.delete_session("token")
    |> Plug.Conn.delete_session("user_id")
    |> Plug.Conn.delete_session("tenant_id")
  end
end
