defmodule FSMApp.Accounts do
  @moduledoc """
  Enhanced accounts context with dual-level user architecture.

  Manages global platform users with enhanced functionality:
  - Global user accounts persistent across all tenants
  - Platform-level roles and permissions
  - Enhanced authentication and profile management
  - Integration with enhanced storage system
  """

  alias FSMApp.Accounts.User
  alias FSMApp.Storage.{FSStore, EnhancedStore}
  require Logger

  # Legacy namespace for compatibility
  @namespace "accounts"
  @users_collection "users"

  @doc """
  Get user by ID with fallback to legacy storage.
  """
  def get_user!(id) do
    case get_user(id) do
      {:ok, user} -> user
      {:error, :not_found} -> raise "User not found"
      {:error, reason} -> raise "Error loading user: #{inspect(reason)}"
    end
  end

  @doc """
  Get user by ID (returns {:ok, user} or {:error, reason}).
  """
  def get_user(id) when is_binary(id) do
    # Try enhanced storage first
    case EnhancedStore.load_user(id) do
      {:ok, user_data} ->
        {:ok, to_user_struct(user_data)}
      {:error, :enoent} ->
        # Fallback to legacy storage
        case Enum.find(load_users_legacy(), &(&1["id"] == id)) do
          nil -> {:error, :not_found}
          map -> {:ok, to_user_struct(map)}
        end
      error ->
        Logger.error("Error loading user #{id}: #{inspect(error)}")
        error
    end
  end

  def get_user(_), do: {:error, :invalid_id}

  @doc """
  Get user by email with enhanced lookup.
  """
  def get_user_by_email(email) when is_binary(email) do
    # Try enhanced storage with index lookup
    case find_user_by_email_enhanced(email) do
      {:ok, user} -> user
      {:error, _} ->
        # Fallback to legacy storage
        case Enum.find(load_users_legacy(), &(&1["email"] == email)) do
          nil -> nil
          map -> to_user_struct(map)
        end
    end
  end

  def get_user_by_email(_), do: nil

  @doc """
  Register a new user with enhanced validation and storage.
  """
  def register_user(attrs) when is_map(attrs) do
    changeset = User.registration_changeset(%User{}, attrs)

    if changeset.valid? do
      email = Ecto.Changeset.get_field(changeset, :email)

      # Check for existing user across both storage systems
      if get_user_by_email(email) do
        {:error, Ecto.Changeset.add_error(changeset, :email, "has already been taken")}
      else
        # Create enhanced user record
        user = %User{
          id: Ecto.UUID.generate(),
          email: email,
          name: Ecto.Changeset.get_field(changeset, :name),
          avatar_url: Ecto.Changeset.get_field(changeset, :avatar_url),
          hashed_password: Ecto.Changeset.get_field(changeset, :hashed_password),
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          last_login: nil,
          email_verified: false,
          status: :active,
          platform_role: :user,
          confirmed_at: DateTime.utc_now()  # For legacy compatibility
        }

        case EnhancedStore.store_user(user) do
          :ok ->
            Logger.info("Successfully registered user #{user.id} (#{email})")
            {:ok, user}
          error ->
            Logger.error("Failed to store user: #{inspect(error)}")
            {:error, Ecto.Changeset.add_error(changeset, :base, "Failed to create user account")}
        end
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Authenticate user with enhanced login tracking.
  """
  def authenticate_user(email, password) do
    with %User{} = user <- get_user_by_email(email),
         true <- User.active?(user),
         hashed_password when not is_nil(hashed_password) <- user.hashed_password,
         true <- Bcrypt.verify_pass(password, hashed_password) do

      # Update last login
      updated_user = %{user |
        last_login: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      # Store updated user (best effort - don't fail auth if this fails)
      EnhancedStore.store_user(updated_user)

      Logger.info("User #{user.id} (#{email}) authenticated successfully")
      {:ok, updated_user}
    else
      nil ->
        Logger.warning("Authentication failed: user not found (#{email})")
        {:error, :invalid_credentials}
      false ->
        Logger.warning("Authentication failed: invalid password or inactive account (#{email})")
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Update user profile.
  """
  def update_user_profile(user, attrs) do
    changeset = User.profile_changeset(user, attrs)

    if changeset.valid? do
      updated_user = apply_changeset_to_user(user, changeset)

      case EnhancedStore.store_user(updated_user) do
        :ok -> {:ok, updated_user}
        error -> {:error, Ecto.Changeset.add_error(changeset, :base, "Failed to update profile")}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Admin operations for managing users.
  """
  def admin_update_user(user, attrs) do
    changeset = User.admin_changeset(user, attrs)

    if changeset.valid? do
      updated_user = apply_changeset_to_user(user, changeset)

      case EnhancedStore.store_user(updated_user) do
        :ok -> {:ok, updated_user}
        error -> {:error, Ecto.Changeset.add_error(changeset, :base, "Failed to update user")}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  List users with filtering and pagination.
  """
  def list_users(opts \\ []) do
    case EnhancedStore.list_users(opts) do
      {:ok, users_data} ->
        users = Enum.map(users_data, &to_user_struct/1)
        {:ok, users}
      error -> error
    end
  end

  @doc """
  Get platform admin users.
  """
  def list_platform_admins do
    case list_users(platform_role: :platform_admin) do
      {:ok, users} -> users
      _ -> []
    end
  end

  @doc """
  Verify user email.
  """
  def verify_user_email(user) do
    updated_user = %{user |
      email_verified: true,
      status: :active,
      updated_at: DateTime.utc_now()
    }

    case EnhancedStore.store_user(updated_user) do
      :ok -> {:ok, updated_user}
      error -> {:error, :verification_failed}
    end
  end

  @doc """
  Initialize enhanced storage and migrate legacy data.
  """
  def initialize_enhanced_storage do
    with :ok <- EnhancedStore.initialize_directory_structure(),
         :ok <- migrate_legacy_users() do
      Logger.info("Enhanced user storage initialized successfully")
      :ok
    else
      error ->
        Logger.error("Failed to initialize enhanced storage: #{inspect(error)}")
        error
    end
  end

  # Private helper functions

  defp find_user_by_email_enhanced(email) do
    # TODO: Implement efficient email lookup via user index
    # For now, fallback to listing and filtering
    case EnhancedStore.list_users() do
      {:ok, users} ->
        case Enum.find(users, &(Map.get(&1, "email") == email)) do
          nil -> {:error, :not_found}
          user_data -> {:ok, to_user_struct(user_data)}
        end
      error -> error
    end
  end

  defp migrate_legacy_users do
    Logger.info("Starting migration of legacy users to enhanced storage")

    legacy_users = load_users_legacy()
    migrated_count = 0

    results = Enum.map(legacy_users, fn user_data ->
      # Convert legacy user data to new format
      enhanced_user = %User{
        id: user_data["id"],
        email: user_data["email"],
        name: user_data["email"] |> String.split("@") |> hd(),  # Use email prefix as default name
        avatar_url: nil,
        hashed_password: user_data["hashed_password"],
        inserted_at: normalize_ts(user_data["inserted_at"]),
        updated_at: normalize_ts(user_data["updated_at"]),
        last_login: nil,
        email_verified: user_data["confirmed_at"] != nil,
        status: :active,
        platform_role: :user,
        confirmed_at: normalize_ts(user_data["confirmed_at"])
      }

      case EnhancedStore.store_user(enhanced_user) do
        :ok ->
          Logger.debug("Migrated user #{enhanced_user.id}")
          :ok
        error ->
          Logger.warning("Failed to migrate user #{enhanced_user.id}: #{inspect(error)}")
          error
      end
    end)

    successful_migrations = Enum.count(results, &(&1 == :ok))
    Logger.info("Migration completed: #{successful_migrations}/#{length(legacy_users)} users migrated")

    :ok
  end

  defp apply_changeset_to_user(user, changeset) do
    Enum.reduce(changeset.changes, user, fn {field, value}, acc ->
      Map.put(acc, field, value)
    end)
  end

  # Legacy support functions
  defp load_users_legacy, do: FSStore.load(@namespace, @users_collection)

  defp to_user_struct(map) when is_map(map) do
    %User{
      id: map["id"],
      email: map["email"] || map[:email],
      name: map["name"] || map[:name],
      avatar_url: map["avatar_url"] || map[:avatar_url],
      hashed_password: map["hashed_password"] || map[:hashed_password],
      inserted_at: normalize_ts(map["inserted_at"] || map[:inserted_at]),
      updated_at: normalize_ts(map["updated_at"] || map[:updated_at]),
      last_login: normalize_ts(map["last_login"] || map[:last_login]),
      email_verified: map["email_verified"] || map[:email_verified] || false,
      status: normalize_status(map["status"] || map[:status]),
      platform_role: normalize_platform_role(map["platform_role"] || map[:platform_role]),
      confirmed_at: normalize_ts(map["confirmed_at"] || map[:confirmed_at])
    }
  end

  defp normalize_ts(nil), do: nil
  defp normalize_ts(%DateTime{} = dt), do: dt
  defp normalize_ts(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
  defp normalize_ts(_), do: nil

  defp normalize_status(nil), do: :active
  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status(status) when is_binary(status) do
    case String.to_existing_atom(status) do
      atom when atom in [:active, :suspended, :pending_verification] -> atom
      _ -> :active
    end
  rescue
    _ -> :active
  end

  defp normalize_platform_role(nil), do: :user
  defp normalize_platform_role(role) when is_atom(role), do: role
  defp normalize_platform_role(role) when is_binary(role) do
    case String.to_existing_atom(role) do
      atom when atom in [:platform_admin, :user] -> atom
      _ -> :user
    end
  rescue
    _ -> :user
  end
end
