defmodule FSMApp.Tenancy.Member do
  @moduledoc """
  Tenant-specific user membership with roles and permissions.
  Storage: ./data/tenants/{tenant_id}/members/member_{user_id}.json

  Enhanced tenant member model with fine-grained permissions:
  - Tenant-specific roles beyond basic membership
  - Granular permissions for workflow operations
  - Activity tracking and invitation management
  """

  use FSMApp.Schema

  @tenant_roles ~w[owner admin developer viewer]a
  @permissions ~w[
    workflow_create workflow_edit workflow_delete workflow_execute
    workflow_deploy workflow_scale workflow_monitor
    effects_create effects_edit effects_delete effects_execute
    tenant_settings tenant_billing tenant_user_management
    ai_model_access ai_coordination_access
    template_create template_publish template_manage
    analytics_view analytics_export
    audit_logs_view system_metrics_view
  ]a

  @derive {Jason.Encoder, only: [:tenant_id, :user_id, :tenant_role, :permissions, :joined_at, :invited_by, :member_status, :last_activity]}

  schema "members" do
    field :tenant_id, :string
    field :user_id, :string
    field :tenant_role, Ecto.Enum, values: @tenant_roles, default: :viewer
    field :permissions, {:array, Ecto.Enum}, values: @permissions, default: []
    field :joined_at, :utc_datetime
    field :invited_by, :string  # user_id of inviter
    field :member_status, Ecto.Enum, values: [:active, :invited, :suspended], default: :invited
    field :last_activity, :utc_datetime

    # Virtual fields for related data
    field :user, :map, virtual: true
    field :inviter, :map, virtual: true

    timestamps()
  end

  @doc """
  Changeset for creating a new tenant member.
  """
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:tenant_id, :user_id, :tenant_role, :permissions, :invited_by, :member_status])
    |> validate_required([:tenant_id, :user_id, :tenant_role])
    |> validate_inclusion(:tenant_role, @tenant_roles)
    |> validate_permissions()
    |> put_timestamps_on_create()
  end

  @doc """
  Changeset for updating member role and permissions.
  """
  def role_changeset(member, attrs) do
    member
    |> cast(attrs, [:tenant_role, :permissions])
    |> validate_required([:tenant_role])
    |> validate_inclusion(:tenant_role, @tenant_roles)
    |> validate_permissions()
    |> auto_assign_permissions_for_role()
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Changeset for accepting an invitation.
  """
  def accept_invitation_changeset(member) do
    member
    |> change()
    |> put_change(:member_status, :active)
    |> put_change(:joined_at, DateTime.utc_now())
    |> put_change(:last_activity, DateTime.utc_now())
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Changeset for updating last activity.
  """
  def activity_changeset(member) do
    member
    |> change()
    |> put_change(:last_activity, DateTime.utc_now())
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Get default permissions for a given role.
  """
  def default_permissions_for_role(:owner) do
    @permissions  # All permissions
  end

  def default_permissions_for_role(:admin) do
    [
      :workflow_create, :workflow_edit, :workflow_delete, :workflow_execute,
      :workflow_deploy, :workflow_scale, :workflow_monitor,
      :effects_create, :effects_edit, :effects_delete, :effects_execute,
      :tenant_settings, :tenant_user_management,
      :ai_model_access, :ai_coordination_access,
      :template_create, :template_publish, :template_manage,
      :analytics_view, :analytics_export,
      :audit_logs_view, :system_metrics_view
    ]
  end

  def default_permissions_for_role(:developer) do
    [
      :workflow_create, :workflow_edit, :workflow_execute,
      :workflow_deploy, :workflow_monitor,
      :effects_create, :effects_edit, :effects_execute,
      :ai_model_access, :ai_coordination_access,
      :template_create, :template_manage,
      :analytics_view, :system_metrics_view
    ]
  end

  def default_permissions_for_role(:viewer) do
    [
      :workflow_execute, :workflow_monitor,
      :effects_execute,
      :ai_model_access,
      :analytics_view, :system_metrics_view
    ]
  end

  @doc """
  Check if member has a specific permission.
  """
  def has_permission?(%__MODULE__{permissions: permissions}, permission) when is_atom(permission) do
    permission in permissions
  end

  def has_permission?(_, _), do: false

  @doc """
  Check if member has any of the given permissions.
  """
  def has_any_permission?(%__MODULE__{permissions: permissions}, required_permissions) when is_list(required_permissions) do
    Enum.any?(required_permissions, &(&1 in permissions))
  end

  def has_any_permission?(_, _), do: false

  @doc """
  Check if member has all of the given permissions.
  """
  def has_all_permissions?(%__MODULE__{permissions: permissions}, required_permissions) when is_list(required_permissions) do
    Enum.all?(required_permissions, &(&1 in permissions))
  end

  def has_all_permissions?(_, _), do: false

  @doc """
  Check if member is active.
  """
  def active?(%__MODULE__{member_status: :active}), do: true
  def active?(_), do: false

  @doc """
  Check if member is owner.
  """
  def owner?(%__MODULE__{tenant_role: :owner}), do: true
  def owner?(_), do: false

  @doc """
  Check if member is admin or owner.
  """
  def admin_or_owner?(%__MODULE__{tenant_role: role}) when role in [:owner, :admin], do: true
  def admin_or_owner?(_), do: false

  @doc """
  Get all available permissions.
  """
  def available_permissions, do: @permissions

  @doc """
  Get all available roles.
  """
  def available_roles, do: @tenant_roles

  # Private functions

  defp validate_permissions(changeset) do
    case get_change(changeset, :permissions) do
      nil -> changeset
      permissions when is_list(permissions) ->
        invalid_permissions = permissions -- @permissions
        if length(invalid_permissions) > 0 do
          add_error(changeset, :permissions, "invalid permissions: #{inspect(invalid_permissions)}")
        else
          changeset
        end
      _ ->
        add_error(changeset, :permissions, "must be a list")
    end
  end

  defp auto_assign_permissions_for_role(changeset) do
    case get_change(changeset, :tenant_role) do
      nil -> changeset
      role ->
        permissions = get_change(changeset, :permissions) || default_permissions_for_role(role)
        put_change(changeset, :permissions, permissions)
    end
  end

  defp put_timestamps_on_create(changeset) do
    now = DateTime.utc_now()
    changeset
    |> put_change(:inserted_at, now)
    |> put_change(:updated_at, now)
  end
end
