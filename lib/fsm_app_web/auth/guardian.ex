defmodule FSMAppWeb.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT token management.

  Handles JWT token creation, verification, and user resource loading
  for the enhanced authentication system.
  """

  use Guardian, otp_app: :fsm_app

  alias FSMApp.Accounts

  @impl Guardian
  def subject_for_token(%{id: id}, _claims) do
    # Use user ID as the subject
    {:ok, to_string(id)}
  end

  @impl Guardian
  def subject_for_token(_, _) do
    {:error, :invalid_resource}
  end

  @impl Guardian
  def resource_from_claims(%{"sub" => user_id}) do
    # Load user from enhanced storage
    case Accounts.get_user(user_id) do
      {:ok, user} -> {:ok, user}
      {:error, :not_found} -> {:error, :user_not_found}
      error -> error
    end
  end

  @impl Guardian
  def resource_from_claims(_claims) do
    {:error, :invalid_claims}
  end

  @impl Guardian
  def build_claims(claims, %{id: user_id, email: email, platform_role: role}, _opts) do
    # Add custom claims
    custom_claims = %{
      "user_id" => user_id,
      "email" => email,
      "platform_role" => to_string(role),
      "issued_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, Map.merge(claims, custom_claims)}
  end

  @impl Guardian
  def build_claims(claims, _resource, _opts) do
    {:ok, claims}
  end

  @doc """
  Create a token for a user with custom TTL.
  """
  def create_token(user, ttl \\ {24, :hours}) do
    encode_and_sign(user, %{}, ttl: ttl)
  end

  @doc """
  Create a refresh token.
  """
  def create_refresh_token(user) do
    encode_and_sign(user, %{"typ" => "refresh"}, ttl: {30, :days})
  end

  @doc """
  Refresh an access token using a refresh token.
  """
  def refresh_token(refresh_token) do
    case decode_and_verify(refresh_token) do
      {:ok, %{"typ" => "refresh", "sub" => user_id}} ->
        case Accounts.get_user(user_id) do
          {:ok, user} ->
            # Create new access token
            create_token(user)
          error -> error
        end

      {:ok, _} -> {:error, :invalid_refresh_token}
      error -> error
    end
  end

  @doc """
  Verify token and get user.
  """
  def verify_and_get_user(token) do
    case decode_and_verify(token) do
      {:ok, claims} -> resource_from_claims(claims)
      error -> error
    end
  end

  @doc """
  Check if token is expired.
  """
  def token_expired?(token) do
    case decode_and_verify(token) do
      {:ok, %{"exp" => exp}} ->
        current_time = System.system_time(:second)
        exp < current_time

      {:error, :token_expired} -> true
      _ -> true
    end
  end

  @doc """
  Extract custom claims from token.
  """
  def get_user_claims(token) do
    case decode_and_verify(token) do
      {:ok, %{"user_id" => user_id, "email" => email, "platform_role" => role}} ->
        {:ok, %{user_id: user_id, email: email, platform_role: String.to_atom(role)}}

      {:ok, _} -> {:error, :invalid_claims}
      error -> error
    end
  end
end
