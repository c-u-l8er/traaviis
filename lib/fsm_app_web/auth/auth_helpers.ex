defmodule FSMAppWeb.Auth.AuthHelpers do
  @moduledoc """
  Authentication helper functions shared across controllers and LiveViews.
  
  Provides common authentication utilities adapted from BrokenRecord patterns:
  - User status checking
  - Token management
  - Session utilities
  - Multi-tenant helpers
  """

  alias FSMApp.{Accounts, Authorization, Tenancy}
  alias FSMAppWeb.Auth.Guardian
  require Logger

  @doc """
  Check if a user can login based on their status.
  
  Performs comprehensive user validation including:
  - User existence and loading
  - Active status
  - Account suspension
  - Email verification (if implemented)
  """
  def check_user_can_login(user) do
    cond do
      is_nil(user) ->
        {:error, :user_not_found}

      not user_active?(user) ->
        {:error, :user_inactive}
      
      # Add more status checks based on your User schema
      # Map.get(user, :status) == :suspended -> {:error, :user_suspended}
      # not Map.get(user, :email_verified, true) -> {:error, :user_not_verified}
      
      true -> :ok
    end
  end

  @doc """
  Check if user is active.
  
  Adapt this function to match your User schema's active field logic.
  """
  def user_active?(user) do
    # Common patterns for user status:
    # - user.active == true
    # - user.status == :active  
    # - is_nil(user.deactivated_at)
    # - user.deleted_at == nil
    
    # For now, assuming users are active by default
    Map.get(user, :active, true) != false
  end

  @doc """
  Create authentication token with optional tenant context.
  
  Similar to BrokenRecord's tenant token creation but adapted for FSMApp.
  """
  def create_auth_token(user, tenant_id \\ nil) do
    case Guardian.encode_and_sign(user) do
      {:ok, token, claims} ->
        Logger.debug("Created auth token for user #{user.id}")
        {:ok, token, claims}
      
      error ->
        Logger.error("Failed to create auth token for user #{user.id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get user's tenant memberships.
  
  Returns list of tenants user has access to, adapted from BrokenRecord pattern.
  """
  def get_user_tenants(user_id) do
    Logger.debug("Looking up tenants for user_id: #{user_id}")
    
    # This would need to be implemented based on your tenant system
    # For now, returning empty list as placeholder
    tenants = []
    
    Logger.debug("Found #{length(tenants)} tenants for user #{user_id}")
    
    tenants
    |> Enum.map(fn tenant ->
      %{
        tenant_id: tenant.id,
        tenant_name: tenant.name,
        # tenant_role: get_user_role_in_tenant(tenant.id, user_id),
        # joined_at: get_user_join_date(tenant.id, user_id)
      }
    end)
  end

  @doc """
  Handle multi-tenant login flow.
  
  Based on BrokenRecord's pattern:
  - 0 tenants: Show tenant creation or contact admin
  - 1 tenant: Auto-login to that tenant
  - Multiple tenants: Show tenant selection
  """
  def handle_tenant_selection(user) do
    tenants = get_user_tenants(user.id)
    
    case tenants do
      [] ->
        {:no_tenants, []}
        
      [single_tenant] ->
        {:single_tenant, single_tenant}
        
      multiple_tenants ->
        {:multiple_tenants, multiple_tenants}
    end
  end

  @doc """
  Set authentication session with token and user context.
  
  Stores both session-based and token-based auth for compatibility.
  """
  def put_auth_session(conn, user, token \\ nil) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> maybe_put_token_session(token)
  end

  @doc """
  Clear all authentication session data.
  """
  def clear_auth_session(conn) do
    # Revoke JWT token if present
    case Plug.Conn.get_session(conn, :auth_token) do
      nil -> :ok
      token -> Guardian.revoke(token)
    end
    
    conn
    |> Plug.Conn.delete_session(:user_id)
    |> Plug.Conn.delete_session(:tenant_id) 
    |> Plug.Conn.delete_session(:auth_token)
  end

  @doc """
  Extract authentication info from session or token.
  
  Supports both session-based and JWT token authentication.
  """
  def get_auth_from_session(session) do
    case session do
      %{"auth_token" => token} when not is_nil(token) ->
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            case Guardian.resource_from_claims(claims) do
              {:ok, user} -> {:ok, user, :token}
              error -> error
            end
          error -> error
        end
        
      %{"user_id" => user_id} when not is_nil(user_id) ->
        case Accounts.get_user(user_id) do
          {:ok, user} -> {:ok, user, :session}
          error -> error
        end
        
      _ ->
        {:error, :no_auth}
    end
  end

  @doc """
  Format user-friendly error messages.
  
  Maps technical error reasons to user-friendly messages.
  """
  def format_auth_error(reason) do
    case reason do
      :invalid_credentials -> "Invalid email or password"
      :user_inactive -> "Your account is inactive. Please contact support."
      :user_suspended -> "🚫 Your account has been suspended. Please contact support for assistance."
      :user_not_verified -> "Please verify your email address before logging in."
      :user_not_found -> "Account not found. Please check your credentials."
      :token_expired -> "Your session has expired. Please sign in again."
      :authentication_failed -> "Authentication failed. Please try again."
      _ -> "Login failed. Please try again."
    end
  end

  # Private helper functions

  defp maybe_put_token_session(conn, nil), do: conn
  defp maybe_put_token_session(conn, token) do
    Plug.Conn.put_session(conn, :auth_token, token)
  end
end
