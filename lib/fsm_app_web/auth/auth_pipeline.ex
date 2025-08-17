defmodule FSMAppWeb.Auth.Pipeline do
  @moduledoc """
  Enterprise authentication pipeline with JWT + tenant context.

  Implements the enhanced authentication system from the roadmap:
  - JWT-based authentication with Guardian
  - Tenant context resolution and validation
  - Session management with ETS backing
  - Role-based access control integration
  - WebSocket authentication support

  Pipeline stages:
  1. Extract and verify JWT token
  2. Load user from enhanced storage
  3. Resolve tenant context from URL/params
  4. Validate tenant membership and permissions
  5. Set authentication assigns for controllers/channels
  """

  use Guardian.Plug.Pipeline,
    otp_app: :fsm_app,
    module: FSMAppWeb.Auth.Guardian,
    error_handler: FSMAppWeb.Auth.ErrorHandler

  alias FSMApp.{Accounts, Authorization, Tenancy}
  alias FSMApp.Tenancy.Member
  alias FSMApp.Storage.HybridStore
  require Logger

  # Core authentication plugs - simplified approach
  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.VerifySession
  plug Guardian.Plug.LoadResource
  plug :load_current_user
  plug :resolve_tenant_context
  plug :validate_tenant_access
  plug :ensure_authenticated_user

  @doc """
  Authenticate user and establish session.
  """
  def authenticate_user(conn, email, password) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        # Create JWT token
        {:ok, token, _claims} = FSMAppWeb.Auth.Guardian.encode_and_sign(user)

        # Create session in hybrid storage
        session_data = %{
          user_id: user.id,
          email: user.email,
          platform_role: user.platform_role,
          authenticated_at: DateTime.utc_now(),
          ip_address: get_client_ip(conn),
          user_agent: get_user_agent(conn)
        }

        session_id = generate_session_id()
        HybridStore.put_session(session_id, session_data, ttl: 86400) # 24 hours

        # Set authentication assigns
        conn = conn
        |> Plug.Conn.assign(:current_user, user)
        |> Plug.Conn.assign(:session_id, session_id)
        |> Plug.Conn.assign(:authenticated_at, session_data.authenticated_at)

        Logger.info("User #{user.id} (#{email}) authenticated successfully")

        {:ok, conn, token}

      {:error, :invalid_credentials} ->
        Logger.warning("Authentication failed for #{email}")
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Logout user and invalidate session.
  """
  def logout_user(conn) do
    # Invalidate JWT token
    case Guardian.Plug.current_token(conn) do
      nil -> :ok
      token -> FSMAppWeb.Auth.Guardian.revoke(token)
    end

    # Remove session
    case conn.assigns[:session_id] do
      nil -> :ok
      session_id -> HybridStore.delete({:session, session_id})
    end

    # Clear assigns
    conn = conn
    |> Plug.Conn.assign(:current_user, nil)
    |> Plug.Conn.assign(:current_tenant, nil)
    |> Plug.Conn.assign(:tenant_member, nil)
    |> Plug.Conn.assign(:session_id, nil)

    Logger.info("User logged out successfully")

    {:ok, conn}
  end

  @doc """
  Ensure user is authenticated (plug).
  """
  def ensure_authenticated(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> FSMAppWeb.Auth.ErrorHandler.auth_error({:unauthenticated, :not_authenticated}, %{})
        |> halt()

      user ->
        # Validate session is still active
        case validate_active_session(conn) do
          :ok -> conn
          {:error, reason} ->
            Logger.warning("Session validation failed for user #{user.id}: #{reason}")
            conn
            |> FSMAppWeb.Auth.ErrorHandler.auth_error({:unauthenticated, reason}, %{})
            |> halt()
        end
    end
  end

  @doc """
  Ensure user has access to tenant (plug).
  """
  def ensure_tenant_access(conn, _opts) do
    user = conn.assigns[:current_user]
    tenant_id = conn.assigns[:tenant_id]

    cond do
      is_nil(user) ->
        conn
        |> FSMAppWeb.Auth.ErrorHandler.auth_error({:unauthenticated, :not_authenticated}, %{})
        |> halt()

      is_nil(tenant_id) ->
        conn
        |> FSMAppWeb.Auth.ErrorHandler.auth_error({:forbidden, :no_tenant_context}, %{})
        |> halt()

      Authorization.can?(user, :tenant_access, %{tenant_id: tenant_id}) ->
        conn

      true ->
        Logger.warning("User #{user.id} denied access to tenant #{tenant_id}")
        conn
        |> FSMAppWeb.Auth.ErrorHandler.auth_error({:forbidden, :insufficient_permissions}, %{})
        |> halt()
    end
  end

  @doc """
  Require specific permission (plug factory).
  """
  def require_permission(permission) when is_atom(permission) do
    fn conn, _opts ->
      user = conn.assigns[:current_user]
      tenant_id = conn.assigns[:tenant_id]

      if Authorization.can?(user, permission, %{tenant_id: tenant_id}) do
        conn
      else
        Logger.warning("User #{user.id} lacks permission #{permission} for tenant #{tenant_id}")
        conn
        |> FSMAppWeb.Auth.ErrorHandler.auth_error({:forbidden, :insufficient_permissions}, %{})
        |> halt()
      end
    end
  end

  @doc """
  Require platform admin privileges (plug).
  """
  def require_platform_admin(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && FSMApp.Accounts.User.platform_admin?(user) do
      conn
    else
      Logger.warning("User #{user && user.id} denied platform admin access")
      conn
      |> FSMAppWeb.Auth.ErrorHandler.auth_error({:forbidden, :platform_admin_required}, %{})
      |> halt()
    end
  end

  @doc """
  WebSocket authentication for channels.
  """
  def authenticate_socket(socket, params) do
    with {:ok, token} <- extract_token_from_params(params),
         {:ok, claims} <- FSMAppWeb.Auth.Guardian.decode_and_verify(token),
         {:ok, user} <- load_user_from_claims(claims),
         :ok <- validate_user_session(user, params) do

      socket = socket
      |> assign(:current_user, user)
      |> assign(:authenticated_at, DateTime.utc_now())

      Logger.debug("WebSocket authenticated for user #{user.id}")
      {:ok, socket}
    else
      error ->
        Logger.warning("WebSocket authentication failed: #{inspect(error)}")
        {:error, :authentication_failed}
    end
  end

  @doc """
  WebSocket tenant authorization for channels.
  """
  def authorize_socket_tenant(socket, tenant_id) do
    user = socket.assigns[:current_user]

    case Authorization.can?(user, :tenant_access, %{tenant_id: tenant_id}) do
      true ->
        # Load tenant member info
        case HybridStore.get_member(tenant_id, user.id) do
          {:ok, member} ->
            socket = socket
            |> assign(:tenant_id, tenant_id)
            |> assign(:tenant_member, member)
            |> assign(:tenant_permissions, member.permissions)

            Logger.debug("WebSocket authorized for tenant #{tenant_id}")
            {:ok, socket}

          {:error, _} ->
            # Create basic member info for compatibility
            basic_member = %{
              user_id: user.id,
              tenant_id: tenant_id,
              tenant_role: Tenancy.get_user_role(tenant_id, user.id),
              permissions: [],
              member_status: :active
            }

            socket = socket
            |> assign(:tenant_id, tenant_id)
            |> assign(:tenant_member, basic_member)
            |> assign(:tenant_permissions, [])

            {:ok, socket}
        end

      false ->
        Logger.warning("User #{user.id} denied WebSocket access to tenant #{tenant_id}")
        {:error, :insufficient_permissions}
    end
  end

  # Private plug functions

  defp load_current_user(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        # Fallback to session-based authentication if no Guardian resource
        case Plug.Conn.get_session(conn, :user_id) do
          nil ->
            conn
          user_id ->
            case Accounts.get_user(user_id) do
              {:ok, user} ->
                conn |> assign(:current_user, user)
              {:error, _reason} ->
                conn
            end
        end

      user ->
        conn
        |> assign(:current_user, user)
    end
  end

  defp resolve_tenant_context(conn, _opts) do
    tenant_id = get_tenant_id_from_request(conn)

    if tenant_id do
      conn |> assign(:tenant_id, tenant_id)
    else
      conn
    end
  end

  defp validate_tenant_access(conn, _opts) do
    user = conn.assigns[:current_user]
    tenant_id = conn.assigns[:tenant_id]

    # Skip if no tenant context or platform admin
    cond do
      is_nil(tenant_id) -> conn
      is_nil(user) -> conn
      FSMApp.Accounts.User.platform_admin?(user) ->
        assign(conn, :tenant_permissions, Member.available_permissions())

      true ->
        case HybridStore.get_member(tenant_id, user.id) do
          {:ok, member} ->
            conn
            |> assign(:tenant_member, member)
            |> assign(:tenant_permissions, member.permissions)

          {:error, _} ->
            # Fallback to legacy membership check
            case Tenancy.get_user_role(tenant_id, user.id) do
              nil ->
                conn
                |> assign(:tenant_member, nil)
                |> assign(:tenant_permissions, [])

              role ->
                basic_member = %{
                  user_id: user.id,
                  tenant_id: tenant_id,
                  tenant_role: role,
                  permissions: Member.default_permissions_for_role(role),
                  member_status: :active
                }

                conn
                |> assign(:tenant_member, basic_member)
                |> assign(:tenant_permissions, basic_member.permissions)
            end
        end
    end
  end

  # Helper functions

  defp get_tenant_id_from_request(conn) do
    # Try multiple sources for tenant ID
    cond do
      # 1. URL path parameter
      tenant_id = conn.path_params["tenant_id"] -> tenant_id

      # 2. Query parameter
      tenant_id = conn.params["tenant_id"] -> tenant_id

      # 3. Subdomain (e.g., tenant1.traaviis.com)
      tenant_id = extract_tenant_from_host(conn) -> tenant_id

      # 4. Custom header
      tenant_id = get_req_header(conn, "x-tenant-id") |> List.first() -> tenant_id

      # 5. Default tenant for development
      true -> nil
    end
  end

  defp extract_tenant_from_host(conn) do
    case get_req_header(conn, "host") do
      [host] ->
        case String.split(host, ".") do
          [tenant_slug | _rest] when tenant_slug not in ["www", "api", "app"] ->
            # Convert slug to tenant ID if needed
            resolve_tenant_id_from_slug(tenant_slug)
          _ -> nil
        end
      _ -> nil
    end
  end

  defp resolve_tenant_id_from_slug(slug) do
    # TODO: Implement slug-to-ID resolution
    slug
  end

  defp validate_active_session(conn) do
    case conn.assigns[:session_id] do
      nil -> {:error, :no_session}
      session_id ->
        case HybridStore.get_session(session_id) do
          {:ok, _session_data} -> :ok
          {:error, :not_found} -> {:error, :session_expired}
          error -> error
        end
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip] -> String.split(ip, ",") |> List.first() |> String.trim()
      [] ->
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> "unknown"
        end
    end
  end

  defp get_user_agent(conn) do
    get_req_header(conn, "user-agent") |> List.first() || "unknown"
  end

  defp extract_token_from_params(params) do
    case Map.get(params, "token") do
      nil -> {:error, :no_token}
      token when is_binary(token) -> {:ok, token}
      _ -> {:error, :invalid_token}
    end
  end

  defp load_user_from_claims(claims) do
    case Map.get(claims, "sub") do
      nil -> {:error, :no_user_id}
      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} -> {:ok, user}
          error -> error
        end
    end
  end

  defp validate_user_session(user, _params) do
    # TODO: Add additional session validation
    if FSMApp.Accounts.User.active?(user) do
      :ok
    else
      {:error, :user_inactive}
    end
  end

  # New simplified authentication plug
  defp ensure_authenticated_user(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        # Not authenticated - let error handler decide what to do
        conn
        |> FSMAppWeb.Auth.ErrorHandler.auth_error({:unauthenticated, :not_authenticated}, %{})
        |> halt()

      user ->
        # Check user status like BrokenRecord does
        case check_user_can_login(user) do
          :ok ->
            conn

          {:error, reason} ->
            Logger.warning("User #{user.id} authentication blocked: #{reason}")
            conn
            |> FSMAppWeb.Auth.ErrorHandler.auth_error({:unauthenticated, reason}, %{})
            |> halt()
        end
    end
  end

  # User status checking (adapted from BrokenRecord pattern)
  defp check_user_can_login(user) do
    cond do
      # Check if user is active
      not FSMApp.Accounts.User.active?(user) ->
        {:error, :user_inactive}

      # Add more status checks as needed
      # user.status == :suspended -> {:error, :user_suspended}
      # not user.email_verified -> {:error, :user_not_verified}

      true -> :ok
    end
  end
end
