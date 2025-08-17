defmodule FSMAppWeb.Auth.ErrorHandler do
  @moduledoc """
  Guardian error handler for authentication failures.

  Provides consistent error responses for authentication and authorization failures
  across HTTP endpoints and WebSocket channels.
  """

  import Plug.Conn
  import Phoenix.Controller
  require Logger

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    Logger.warning("Authentication error: #{type} - #{reason}")

    case type do
      :invalid_token ->
        handle_invalid_token(conn, reason)

      :token_expired ->
        handle_expired_token(conn, reason)

      :unauthenticated ->
        handle_unauthenticated(conn, reason)

      :unauthorized ->
        handle_unauthorized(conn, reason)

      :forbidden ->
        handle_forbidden(conn, reason)

      _ ->
        handle_generic_error(conn, type, reason)
    end
  end

  @doc """
  Handle authentication errors for API requests.
  """
  def handle_api_auth_error(conn, error_type, reason \\ nil) do
    {status, error_code, message} = map_error_to_response(error_type, reason)

    error_response = %{
      error: %{
        code: error_code,
        message: message,
        type: to_string(error_type),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    conn
    |> put_status(status)
    |> put_resp_content_type("application/json")
    |> json(error_response)
  end

  @doc """
  Handle authentication errors for web requests.
  """
  def handle_web_auth_error(conn, error_type, reason \\ nil) do
    {status, _error_code, message} = map_error_to_response(error_type, reason)

    case error_type do
      :unauthenticated ->
        # Avoid redirect loops - don't redirect to login if already on login page
        current_path = conn.request_path
        if current_path in ["/sign-in", "/auth/login", "/register"] do
          # Already on auth page - just set status and halt
          conn
          |> put_status(401)
          |> put_flash(:error, message)
          |> halt()
        else
          # Redirect to login page
          conn
          |> put_flash(:info, "Please sign in to continue")
          |> redirect(to: "/auth/login")
        end

      :forbidden ->
        # Show access denied page
        conn
        |> put_status(status)
        |> put_flash(:error, message)
        |> redirect(to: "/auth/access-denied")

      _ ->
        # Generic error handling
        conn
        |> put_status(status)
        |> put_flash(:error, message)
        |> redirect(to: "/")
    end
  end

  @doc """
  Handle WebSocket authentication errors.
  """
  def handle_socket_auth_error(error_type, reason \\ nil) do
    {_status, error_code, message} = map_error_to_response(error_type, reason)

    %{
      error: %{
        code: error_code,
        message: message,
        type: to_string(error_type),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  # Private error handlers

  defp handle_invalid_token(conn, reason) do
    if api_request?(conn) do
      handle_api_auth_error(conn, :invalid_token, reason)
    else
      handle_web_auth_error(conn, :invalid_token, reason)
    end
  end

  defp handle_expired_token(conn, reason) do
    if api_request?(conn) do
      handle_api_auth_error(conn, :token_expired, reason)
    else
      handle_web_auth_error(conn, :token_expired, reason)
    end
  end

  defp handle_unauthenticated(conn, reason) do
    if api_request?(conn) do
      handle_api_auth_error(conn, :unauthenticated, reason)
    else
      handle_web_auth_error(conn, :unauthenticated, reason)
    end
  end

  defp handle_unauthorized(conn, reason) do
    if api_request?(conn) do
      handle_api_auth_error(conn, :unauthorized, reason)
    else
      handle_web_auth_error(conn, :unauthorized, reason)
    end
  end

  defp handle_forbidden(conn, reason) do
    if api_request?(conn) do
      handle_api_auth_error(conn, :forbidden, reason)
    else
      handle_web_auth_error(conn, :forbidden, reason)
    end
  end

  defp handle_generic_error(conn, type, reason) do
    Logger.error("Unhandled authentication error: #{type} - #{reason}")

    if api_request?(conn) do
      handle_api_auth_error(conn, :authentication_error, reason)
    else
      handle_web_auth_error(conn, :authentication_error, reason)
    end
  end

  # Helper functions

  defp api_request?(conn) do
    # Check if request expects JSON response
    case get_req_header(conn, "accept") do
      [accept_header] -> String.contains?(accept_header, "application/json")
      [] -> false
    end or
    # Check if request is to API path
    String.starts_with?(conn.request_path, "/api/")
  end

  defp map_error_to_response(error_type, reason) do
    case {error_type, reason} do
      {:invalid_token, _} ->
        {401, "INVALID_TOKEN", "The provided authentication token is invalid"}

      {:token_expired, _} ->
        {401, "TOKEN_EXPIRED", "The authentication token has expired"}

      {:unauthenticated, :not_authenticated} ->
        {401, "NOT_AUTHENTICATED", "Authentication is required to access this resource"}

      {:unauthenticated, :session_expired} ->
        {401, "SESSION_EXPIRED", "Your session has expired. Please log in again"}

      {:unauthenticated, :user_inactive} ->
        {401, "USER_INACTIVE", "Your account is inactive. Please contact support"}

      {:unauthorized, _} ->
        {401, "UNAUTHORIZED", "You are not authorized to access this resource"}

      {:forbidden, :insufficient_permissions} ->
        {403, "INSUFFICIENT_PERMISSIONS", "You do not have permission to perform this action"}

      {:forbidden, :no_tenant_context} ->
        {403, "NO_TENANT_CONTEXT", "Tenant context is required for this operation"}

      {:forbidden, :platform_admin_required} ->
        {403, "PLATFORM_ADMIN_REQUIRED", "Platform administrator privileges are required"}

      {:forbidden, _} ->
        {403, "FORBIDDEN", "Access to this resource is forbidden"}

      {:authentication_error, _} ->
        {500, "AUTHENTICATION_ERROR", "An authentication error occurred"}

      _ ->
        {500, "UNKNOWN_ERROR", "An unknown authentication error occurred"}
    end
  end
end
