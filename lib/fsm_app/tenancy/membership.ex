defmodule FSMApp.Tenancy.Membership do
  @moduledoc """
  User membership in a tenant with a role.
  """

  use FSMApp.Schema

  @roles ~w[owner admin member viewer]a

  schema "memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member

    belongs_to :tenant, FSMApp.Tenancy.Tenant
    belongs_to :user, FSMApp.Accounts.User

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :tenant_id, :user_id])
    |> validate_required([:role, :tenant_id, :user_id])
    |> unique_constraint([:tenant_id, :user_id], name: :memberships_tenant_id_user_id_index)
  end
end
