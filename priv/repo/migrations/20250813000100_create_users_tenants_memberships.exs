defmodule FSMApp.Repo.Migrations.CreateUsersTenantsMemberships do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", ""

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end
    create unique_index(:users, [:email])

    create table(:tenants, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :name, :string, null: false
      add :slug, :string, null: false
      timestamps(type: :utc_datetime)
    end
    create unique_index(:tenants, [:slug])

    create table(:memberships, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :role, :string, null: false
      add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end
    create unique_index(:memberships, [:tenant_id, :user_id], name: :memberships_tenant_id_user_id_index)
  end
end
