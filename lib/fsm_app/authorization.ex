defmodule FSMApp.Authorization do
  @moduledoc """
  Comprehensive permission checking with context awareness.

  Implements the dual-level authorization system:
  - Platform-level permissions (handled by User.platform_role)
  - Tenant-level permissions (handled by Member.permissions)

  Usage:
    Authorization.can?(user, :workflow_create, %{tenant_id: tenant_id})
    Authorization.can?(user, :platform_admin, :system)
  """

  alias FSMApp.Accounts.User
  alias FSMApp.Tenancy.{Member, Tenancy}
  require Logger

  @doc """
  Main authorization check function.

  Args:
    - user: %User{} struct or user_id string
    - action: atom representing the action (:workflow_create, :tenant_admin, etc.)
    - resource: map with context (%{tenant_id: "..."}) or atom (:system, :platform)
    - context: optional additional context for fine-grained checks

  Returns: boolean
  """
  def can?(user, action, resource, context \\ %{})

  # Platform-level permissions - platform admins can do anything
  def can?(%User{platform_role: :platform_admin}, _action, _resource, _context), do: true

  # Handle user_id string by loading the user
  def can?(user_id, action, resource, context) when is_binary(user_id) do
    case FSMApp.Accounts.get_user!(user_id) do
      %User{} = user -> can?(user, action, resource, context)
      _ -> false
    end
  rescue
    _ -> false
  end

  # System/platform level actions (no tenant context)
  def can?(user, action, :system, context) when is_atom(action) do
    check_platform_permission(user, action, context)
  end

  def can?(user, action, :platform, context) when is_atom(action) do
    check_platform_permission(user, action, context)
  end

  # Tenant-level permissions
  def can?(user, action, %{tenant_id: tenant_id} = resource, context) when is_atom(action) do
    with {:ok, member} <- get_tenant_membership(user.id, tenant_id),
         true <- Member.active?(member),
         true <- has_tenant_permission?(member, action, resource, context) do
      true
    else
      {:error, :not_member} -> false
      {:error, :inactive_member} -> false
      false -> false
      _ -> false
    end
  end

  # Resource-based permissions with tenant context
  def can?(user, action, resource, context) when is_map(resource) do
    tenant_id = Map.get(resource, :tenant_id)

    cond do
      is_nil(tenant_id) -> false
      User.platform_admin?(user) -> true
      true -> can?(user, action, %{tenant_id: tenant_id}, Map.merge(context, resource))
    end
  end

  # Fallback - deny by default
  def can?(_user, _action, _resource, _context), do: false

  @doc """
  Check if user can perform action on multiple resources.
  All resources must be authorized for this to return true.
  """
  def can_all?(user, action, resources, context \\ %{}) when is_list(resources) do
    Enum.all?(resources, &can?(user, action, &1, context))
  end

  @doc """
  Check if user can perform action on any of the given resources.
  """
  def can_any?(user, action, resources, context \\ %{}) when is_list(resources) do
    Enum.any?(resources, &can?(user, action, &1, context))
  end

  @doc """
  Check multiple actions on a single resource.
  """
  def can_actions?(user, actions, resource, context \\ %{}) when is_list(actions) do
    actions
    |> Enum.map(&{&1, can?(user, &1, resource, context)})
    |> Enum.into(%{})
  end

  @doc """
  Get effective permissions for user in a tenant.
  """
  def effective_permissions(user_id, tenant_id) do
    with {:ok, member} <- get_tenant_membership(user_id, tenant_id) do
      {:ok, member.permissions}
    else
      error -> error
    end
  end

  @doc """
  Check if user has administrative access to tenant.
  """
  def tenant_admin?(user_id, tenant_id) do
    case get_tenant_membership(user_id, tenant_id) do
      {:ok, member} -> Member.admin_or_owner?(member) and Member.active?(member)
      _ -> false
    end
  end

  @doc """
  Check if user owns the tenant.
  """
  def tenant_owner?(user_id, tenant_id) do
    case get_tenant_membership(user_id, tenant_id) do
      {:ok, member} -> Member.owner?(member) and Member.active?(member)
      _ -> false
    end
  end

  @doc """
  Authorize and raise if not permitted.
  """
  def authorize!(user, action, resource, context \\ %{}) do
    unless can?(user, action, resource, context) do
      raise "Access denied: #{inspect(user.id)} cannot #{action} on #{inspect(resource)}"
    end
    :ok
  end

  @doc """
  Get user's accessible tenants with their roles.
  """
  def accessible_tenants(user_id) do
    Tenancy.list_user_tenants(user_id)
    |> Enum.map(fn tenant ->
      case get_tenant_membership(user_id, tenant.id) do
        {:ok, member} ->
          %{
            tenant: tenant,
            role: member.tenant_role,
            permissions: member.permissions,
            active: Member.active?(member)
          }
        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  Audit log for authorization decisions.
  """
  def audit_authorization(user, action, resource, result, context \\ %{}) do
    audit_entry = %{
      timestamp: DateTime.utc_now(),
      user_id: user.id,
      action: action,
      resource: resource,
      result: result,
      context: context,
      user_agent: Map.get(context, :user_agent),
      ip_address: Map.get(context, :ip_address)
    }

    # Log the authorization decision
    Logger.info("Authorization: #{user.id} #{if result, do: "ALLOWED", else: "DENIED"} #{action} on #{inspect(resource)}")

    # Store in audit trail (implement based on your audit system)
    store_audit_entry(audit_entry)
  end

  # Private functions

  defp check_platform_permission(%User{platform_role: :platform_admin}, _action, _context), do: true
  defp check_platform_permission(%User{platform_role: :user}, action, _context) do
    # Regular users can only perform basic platform actions
    action in [:profile_view, :profile_edit, :tenant_create, :tenant_join]
  end
  defp check_platform_permission(_, _, _), do: false

  defp has_tenant_permission?(member, action, resource, context) do
    cond do
      Member.owner?(member) ->
        # Owners can do anything in their tenant
        true

      Member.admin_or_owner?(member) ->
        # Admins have most permissions but may be restricted from billing/ownership changes
        check_admin_permission(action, resource, context)

      true ->
        # Check specific permissions
        Member.has_permission?(member, action)
    end
  end

  defp check_admin_permission(action, _resource, _context) do
    # Actions that only owners can perform
    restricted_actions = [:tenant_delete, :tenant_transfer_ownership, :tenant_billing_admin]

    action not in restricted_actions
  end

  defp get_tenant_membership(user_id, tenant_id) do
    case Tenancy.get_user_role(tenant_id, user_id) do
      nil -> {:error, :not_member}
      _role ->
        # For now, create a basic member struct - this will be enhanced when we implement the full Member storage
        # TODO: Replace with actual Member loading from enhanced storage
        basic_member = %Member{
          user_id: user_id,
          tenant_id: tenant_id,
          tenant_role: Tenancy.get_user_role(tenant_id, user_id),
          permissions: Member.default_permissions_for_role(Tenancy.get_user_role(tenant_id, user_id)),
          member_status: :active,
          joined_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }
        {:ok, basic_member}
    end
  end

  defp store_audit_entry(_audit_entry) do
    # TODO: Implement audit trail storage
    # This could store to:
    # - ./data/system/audit/authorization_YYYY-MM-DD.json
    # - ./data/tenants/{tenant_id}/audit/authorization_YYYY-MM-DD.json
    :ok
  end
end
