defmodule FSMApp.Tenancy do
  @moduledoc """
  Tenancy context: tenants and memberships.
  """

  import Ecto.Query
  alias FSMApp.Repo
  alias FSMApp.Tenancy.{Tenant, Membership}

  def list_tenants, do: Repo.all(from t in Tenant, order_by: t.name)
  def get_tenant!(id), do: Repo.get!(Tenant, id)
  def get_tenant_by_slug!(slug), do: Repo.get_by!(Tenant, slug: slug)

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  def add_member(tenant_id, user_id, role \\ :member) do
    %Membership{}
    |> Membership.changeset(%{tenant_id: tenant_id, user_id: user_id, role: role})
    |> Repo.insert(on_conflict: :nothing)
  end

  def list_members(tenant_id) do
    Repo.all(from m in Membership, where: m.tenant_id == ^tenant_id, preload: :user)
  end

  def list_user_tenants(user_id) do
    Repo.all(
      from m in Membership,
        where: m.user_id == ^user_id,
        join: t in assoc(m, :tenant),
        preload: [tenant: t]
    )
    |> Enum.map(& &1.tenant)
  end
end
