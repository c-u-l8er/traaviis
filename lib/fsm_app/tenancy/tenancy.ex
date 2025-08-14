defmodule FSMApp.Tenancy do
  @moduledoc """
  Tenancy context: tenants and memberships (filesystem-backed).
  """

  alias FSMApp.Tenancy.{Tenant, Membership}
  alias FSMApp.Storage.FSStore
  alias FSMApp.Storage.FSStore

  @namespace "tenancy"
  @tenants_collection "tenants"
  @memberships_collection "memberships"

  def list_tenants do
    load_tenants()
    |> Enum.map(&to_tenant_struct/1)
    |> Enum.sort_by(& &1.name)
  end

  def get_tenant!(id) do
    case Enum.find(load_tenants(), &(&1["id"] == id)) do
      nil -> raise "Tenant not found"
      map -> to_tenant_struct(map)
    end
  end

  def get_tenant_by_slug!(slug) do
    case Enum.find(load_tenants(), &(&1["slug"] == slug)) do
      nil -> raise "Tenant not found"
      map -> to_tenant_struct(map)
    end
  end

  def create_tenant(attrs) when is_map(attrs) do
    changeset = Tenant.changeset(%Tenant{}, attrs)
    if changeset.valid? do
      slug = Ecto.Changeset.get_field(changeset, :slug)
      case Enum.find(load_tenants(), &(&1["slug"] == slug)) do
        nil ->
          now = DateTime.utc_now() |> DateTime.to_iso8601()
          tenant_map = %{
            "id" => Ecto.UUID.generate(),
            "name" => Ecto.Changeset.get_field(changeset, :name),
            "slug" => slug,
            "inserted_at" => now,
            "updated_at" => now
          }
          case FSStore.persist(@namespace, @tenants_collection, [tenant_map | load_tenants()]) do
            :ok -> {:ok, to_tenant_struct(tenant_map)}
            {:error, reason} -> {:error, Ecto.Changeset.add_error(changeset, :base, inspect(reason))}
          end
        _dup ->
          {:error, Ecto.Changeset.add_error(changeset, :slug, "has already been taken")}
      end
    else
      {:error, changeset}
    end
  end

  def update_tenant(id, attrs) when is_binary(id) and is_map(attrs) do
    case Enum.find(load_tenants(), &(&1["id"] == id)) do
      nil -> {:error, :not_found}
      current ->
        # Build changeset to reuse validations (name + slug required, slug unique)
        changeset = Tenant.changeset(%Tenant{}, %{name: Map.get(attrs, :name, current["name"]), slug: Map.get(attrs, :slug, current["slug"])})
        if changeset.valid? do
          new_slug = Ecto.Changeset.get_field(changeset, :slug)
          if new_slug != current["slug"] and Enum.any?(load_tenants(), &(&1["slug"] == new_slug)) do
            {:error, Ecto.Changeset.add_error(changeset, :slug, "has already been taken")}
          else
            updated = current
            |> Map.put("name", Ecto.Changeset.get_field(changeset, :name))
            |> Map.put("slug", new_slug)
            |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

            tenants = load_tenants()
            |> Enum.map(fn t -> if t["id"] == id, do: updated, else: t end)

            case FSStore.persist(@namespace, @tenants_collection, tenants) do
              :ok -> {:ok, to_tenant_struct(updated)}
              {:error, reason} -> {:error, reason}
            end
          end
        else
          {:error, changeset}
        end
    end
  end

  def delete_tenant(id) when is_binary(id) do
    tenants = load_tenants()
    case Enum.find(tenants, &(&1["id"] == id)) do
      nil -> {:error, :not_found}
      _ ->
        new_tenants = Enum.reject(tenants, &(&1["id"] == id))
        # remove memberships for this tenant
        new_memberships = load_memberships() |> Enum.reject(&(&1["tenant_id"] == id))

        with :ok <- FSStore.persist(@namespace, @tenants_collection, new_tenants),
             :ok <- FSStore.persist(@namespace, @memberships_collection, new_memberships) do
          :ok
        else
          {:error, reason} -> {:error, reason}
          other -> {:error, other}
        end
    end
  end

  def add_member(tenant_id, user_id, role \\ :member) do
    changeset = Membership.changeset(%Membership{}, %{tenant_id: tenant_id, user_id: user_id, role: role})
    if changeset.valid? do
      case Enum.find(load_memberships(), &(&1["tenant_id"] == tenant_id and &1["user_id"] == user_id)) do
        nil ->
          now = DateTime.utc_now() |> DateTime.to_iso8601()
          membership_map = %{
            "id" => Ecto.UUID.generate(),
            "tenant_id" => tenant_id,
            "user_id" => user_id,
            "role" => Ecto.Changeset.get_field(changeset, :role) |> to_string(),
            "inserted_at" => now,
            "updated_at" => now
          }
          case FSStore.persist(@namespace, @memberships_collection, [membership_map | load_memberships()]) do
            :ok -> {:ok, to_membership_struct(membership_map)}
            {:error, reason} -> {:error, Ecto.Changeset.add_error(changeset, :base, inspect(reason))}
          end
        _dup -> {:ok, :already_member}
      end
    else
      {:error, changeset}
    end
  end

  def list_members(tenant_id) do
    users_by_id = build_users_index()
    load_memberships()
    |> Enum.filter(&(&1["tenant_id"] == tenant_id))
    |> Enum.map(fn m ->
      %{
        id: m["id"],
        role: m["role"],
        user: Map.get(users_by_id, m["user_id"], %{id: m["user_id"], email: "unknown"})
      }
    end)
  end

  def list_user_tenants(user_id) do
    tenant_index = load_tenants() |> Enum.into(%{}, fn t -> {t["id"], to_tenant_struct(t)} end)
    load_memberships()
    |> Enum.filter(&(&1["user_id"] == user_id))
    |> Enum.map(&Map.get(tenant_index, &1["tenant_id"]))
    |> Enum.filter(& &1)
  end

  @doc """
  Get the role of a user in a tenant, or nil if not a member.
  """
  def get_user_role(tenant_id, user_id) do
    case Enum.find(load_memberships(), &(&1["tenant_id"] == tenant_id and &1["user_id"] == user_id)) do
      nil -> nil
      m ->
        case m["role"] do
          r when is_binary(r) -> String.to_atom(r)
          r when is_atom(r) -> r
          _ -> nil
        end
    end
  end

  @doc """
  Remove a user's membership from a tenant.
  """
  def remove_member(tenant_id, user_id) do
    memberships = load_memberships()
    case Enum.find(memberships, &(&1["tenant_id"] == tenant_id and &1["user_id"] == user_id)) do
      nil -> {:error, :not_found}
      _ ->
        new_memberships = Enum.reject(memberships, &(&1["tenant_id"] == tenant_id and &1["user_id"] == user_id))
        case FSStore.persist(@namespace, @memberships_collection, new_memberships) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Internal helpers
  defp load_tenants, do: FSStore.load(@namespace, @tenants_collection)
  defp load_memberships, do: FSStore.load(@namespace, @memberships_collection)

  defp to_tenant_struct(map) do
    %Tenant{
      id: map["id"],
      name: map["name"],
      slug: map["slug"],
      inserted_at: normalize_ts(map["inserted_at"]),
      updated_at: normalize_ts(map["updated_at"])
    }
  end

  defp to_membership_struct(map) do
    %Membership{
      id: map["id"],
      role: map["role"],
      tenant_id: map["tenant_id"],
      user_id: map["user_id"],
      inserted_at: normalize_ts(map["inserted_at"]),
      updated_at: normalize_ts(map["updated_at"])
    }
  end

  defp build_users_index do
    FSStore.load("accounts", "users")
    |> Enum.into(%{}, fn u -> {u["id"], %{id: u["id"], email: u["email"]}} end)
  end

  defp normalize_ts(%DateTime{} = dt), do: dt
  defp normalize_ts(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp normalize_ts(_), do: DateTime.utc_now()
end
