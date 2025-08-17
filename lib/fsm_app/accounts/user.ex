defmodule FSMApp.Accounts.User do
  @moduledoc """
  Global platform user - persistent across all tenants.
  Storage: ./data/system/users/user_{uuid}.json

  Enhanced dual-level user architecture for enterprise multi-tenancy:
  - Global users exist at platform level
  - Tenant members exist at tenant level with specific roles
  """

  use FSMApp.Schema

  @derive {Jason.Encoder, only: [:id, :email, :name, :avatar_url, :inserted_at, :updated_at, :last_login, :email_verified, :status, :platform_role, :stored_at, :hashed_password]}
  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :name, :string
    field :avatar_url, :string
    field :last_login, :utc_datetime
    field :email_verified, :boolean, default: false
    field :status, Ecto.Enum, values: [:active, :suspended, :pending_verification], default: :active
    field :platform_role, Ecto.Enum, values: [:platform_admin, :user], default: :user

    # Legacy field for compatibility
    field :confirmed_at, :utc_datetime

    # Storage-related field (virtual, used only for JSON storage)
    field :stored_at, :string, virtual: true

    has_many :memberships, FSMApp.Tenancy.Membership

    timestamps()
  end

  @doc """
  Changeset for user registration with enhanced validation.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :name, :avatar_url])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:email)
    |> validate_length(:password, min: 8, message: "must be at least 8 characters")
    |> validate_length(:name, min: 2, max: 100)
    |> validate_simple_password_strength()
    |> put_default_name_if_empty()
    |> put_password_hash()
    |> put_timestamps()
  end

  @doc """
  Changeset for updating user profile.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :avatar_url, :email])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:name, min: 2, max: 100)
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Changeset for platform admin operations.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:status, :platform_role, :email_verified])
    |> validate_required([:status, :platform_role])
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Update last login timestamp.
  """
  def login_changeset(user) do
    user
    |> change()
    |> put_change(:last_login, DateTime.utc_now())
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Check if user has platform admin privileges.
  """
  def platform_admin?(%__MODULE__{platform_role: :platform_admin}), do: true
  def platform_admin?(_), do: false

  @doc """
  Check if user account is active.
  """
  def active?(%__MODULE__{status: :active}), do: true
  def active?(_), do: false

  # Private functions

  defp validate_simple_password_strength(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password ->
        errors = []

        # Basic strength checks - just ensure it's not too simple
        errors = if String.length(password) >= 8, do: errors, else: ["must be at least 8 characters" | errors]

        # Optional: warn if too simple but don't prevent registration
        if String.match?(password, ~r/^[a-z]+$|^[A-Z]+$|^[0-9]+$/) do
          # Password is all lowercase, all uppercase, or all numbers
          errors = ["consider using a mix of letters and numbers for better security" | errors]
        end

        Enum.reduce(errors, changeset, fn error, acc ->
          add_error(acc, :password, error)
        end)
    end
  end

  defp put_default_name_if_empty(changeset) do
    case get_change(changeset, :name) do
      nil ->
        # Generate default name from email
        case get_change(changeset, :email) do
          nil -> changeset
          email ->
            default_name = email |> String.split("@") |> List.first() |> String.capitalize()
            put_change(changeset, :name, default_name)
        end
      "" ->
        # Same for empty string
        case get_change(changeset, :email) do
          nil -> changeset
          email ->
            default_name = email |> String.split("@") |> List.first() |> String.capitalize()
            put_change(changeset, :name, default_name)
        end
      _name -> changeset
    end
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, hashed_password: Bcrypt.hash_pwd_salt(password))
  end

  defp put_password_hash(changeset), do: changeset

  defp put_timestamps(changeset) do
    now = DateTime.utc_now()
    changeset
    |> put_change(:inserted_at, now)
    |> put_change(:updated_at, now)
    |> put_change(:confirmed_at, now)  # For legacy compatibility
  end
end
