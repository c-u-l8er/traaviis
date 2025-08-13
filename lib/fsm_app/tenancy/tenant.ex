defmodule FSMApp.Tenancy.Tenant do
  @moduledoc """
  Tenant schema.
  """

  use FSMApp.Schema

  @derive {Jason.Encoder, only: [:id, :name, :slug, :inserted_at, :updated_at]}
  schema "tenants" do
    field :name, :string
    field :slug, :string

    has_many :memberships, FSMApp.Tenancy.Membership

    timestamps()
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
