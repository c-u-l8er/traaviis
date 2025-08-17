defmodule FSMApp.Storage.DirectoryMigrator do
  @moduledoc """
  Migrates data from legacy directory structure to enhanced enterprise structure.

  Handles the migration from current data/ structure to the new enterprise layout:

  OLD STRUCTURE:
  ./data/
  ├── accounts/users.json
  ├── tenancy/tenants.json
  ├── tenancy/memberships.json
  └── {tenant_id}/fsm/{Module}/{fsm_id}.json

  NEW STRUCTURE:
  ./data/
  ├── system/
  │   ├── users/user_{uuid}.json
  │   ├── sessions/active_sessions.json
  │   └── platform_metrics.json
  ├── tenants/
  │   ├── {tenant_uuid}/
  │   │   ├── config.json
  │   │   ├── members/member_{user_uuid}.json
  │   │   ├── workflows/{Module}/{fsm_id}.json
  │   │   └── billing/usage/
  │   └── index.json
  """

  require Logger
  alias FSMApp.Storage.{FSStore, EnhancedStore}
  alias Jason

  @data_root Path.expand("data")
  @backup_dir Path.join(@data_root, "_migration_backup")

  @doc """
  Perform complete migration to enhanced directory structure.
  """
  def migrate_all do
    Logger.info("🚀 Starting migration to enhanced directory structure")

    with :ok <- create_backup(),
         :ok <- initialize_new_structure(),
         :ok <- migrate_users(),
         :ok <- migrate_tenants(),
         :ok <- migrate_memberships(),
         :ok <- migrate_fsm_data(),
         :ok <- create_migration_report() do

      Logger.info("✅ Migration completed successfully")
      :ok
    else
      error ->
        Logger.error("❌ Migration failed: #{inspect(error)}")
        Logger.info("📦 Backup available at: #{@backup_dir}")
        error
    end
  end

  @doc """
  Create backup of current data structure.
  """
  def create_backup do
    Logger.info("📦 Creating backup of current data")

    if File.exists?(@data_root) do
      case File.cp_r(@data_root, @backup_dir) do
        {:ok, _} ->
          Logger.info("✅ Backup created at #{@backup_dir}")
          :ok
        error ->
          Logger.error("❌ Backup failed: #{inspect(error)}")
          error
      end
    else
      Logger.info("ℹ️  No existing data directory to backup")
      :ok
    end
  end

  @doc """
  Initialize the new enhanced directory structure.
  """
  def initialize_new_structure do
    Logger.info("🏗️  Initializing enhanced directory structure")
    EnhancedStore.initialize_directory_structure()
  end

  @doc """
  Migrate user data to enhanced system structure.
  """
  def migrate_users do
    Logger.info("👤 Migrating user data")

    case load_legacy_users() do
      {:ok, users} ->
        results = Enum.map(users, fn user_data ->
          enhanced_user = transform_user_data(user_data)

          case EnhancedStore.store_user(enhanced_user) do
            :ok ->
              Logger.debug("✅ Migrated user: #{enhanced_user.email}")
              :ok
            error ->
              Logger.warning("⚠️  Failed to migrate user #{user_data["email"]}: #{inspect(error)}")
              error
          end
        end)

        successful = Enum.count(results, &(&1 == :ok))
        total = length(users)

        Logger.info("👤 User migration: #{successful}/#{total} successful")

        if successful == total, do: :ok, else: {:error, :partial_user_migration}

      {:error, :not_found} ->
        Logger.info("ℹ️  No legacy users found to migrate")
        :ok

      error -> error
    end
  end

  @doc """
  Migrate tenant data to enhanced structure.
  """
  def migrate_tenants do
    Logger.info("🏢 Migrating tenant data")

    case load_legacy_tenants() do
      {:ok, tenants} ->
        results = Enum.map(tenants, fn tenant_data ->
          case migrate_single_tenant(tenant_data) do
            :ok ->
              Logger.debug("✅ Migrated tenant: #{tenant_data["name"]}")
              :ok
            error ->
              Logger.warning("⚠️  Failed to migrate tenant #{tenant_data["name"]}: #{inspect(error)}")
              error
          end
        end)

        successful = Enum.count(results, &(&1 == :ok))
        total = length(tenants)

        Logger.info("🏢 Tenant migration: #{successful}/#{total} successful")

        if successful == total, do: :ok, else: {:error, :partial_tenant_migration}

      {:error, :not_found} ->
        Logger.info("ℹ️  No legacy tenants found to migrate")
        :ok

      error -> error
    end
  end

  @doc """
  Migrate membership data to enhanced tenant member structure.
  """
  def migrate_memberships do
    Logger.info("👥 Migrating membership data")

    case load_legacy_memberships() do
      {:ok, memberships} ->
        # Group memberships by tenant
        grouped_memberships = Enum.group_by(memberships, &(&1["tenant_id"]))

        results = Enum.flat_map(grouped_memberships, fn {tenant_id, tenant_memberships} ->
          Enum.map(tenant_memberships, fn membership_data ->
            enhanced_member = transform_membership_data(membership_data)

            case EnhancedStore.store_member(tenant_id, enhanced_member) do
              :ok ->
                Logger.debug("✅ Migrated member: #{membership_data["user_id"]} → #{tenant_id}")
                :ok
              error ->
                Logger.warning("⚠️  Failed to migrate membership #{membership_data["user_id"]} → #{tenant_id}: #{inspect(error)}")
                error
            end
          end)
        end)

        successful = Enum.count(results, &(&1 == :ok))
        total = length(memberships)

        Logger.info("👥 Membership migration: #{successful}/#{total} successful")

        if successful == total, do: :ok, else: {:error, :partial_membership_migration}

      {:error, :not_found} ->
        Logger.info("ℹ️  No legacy memberships found to migrate")
        :ok

      error -> error
    end
  end

  @doc """
  Migrate FSM workflow data to enhanced workflows structure.
  """
  def migrate_fsm_data do
    Logger.info("⚙️  Migrating FSM workflow data")

    # Find all tenant directories with FSM data
    tenant_dirs = find_tenant_directories_with_fsm_data()

    results = Enum.flat_map(tenant_dirs, fn tenant_id ->
      migrate_tenant_fsm_data(tenant_id)
    end)

    successful = Enum.count(results, &(&1 == :ok))
    total = length(results)

    Logger.info("⚙️  FSM migration: #{successful}/#{total} workflows successful")

    if successful == total or total == 0, do: :ok, else: {:error, :partial_fsm_migration}
  end

  @doc """
  Create migration report with statistics and any issues.
  """
  def create_migration_report do
    Logger.info("📊 Creating migration report")

    report = %{
      migration_completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      migration_version: "1.0.0",
      directories_created: count_directories_in_path(Path.join(@data_root, "system")) +
                           count_directories_in_path(Path.join(@data_root, "tenants")),
      users_migrated: count_files_in_path(Path.join([@data_root, "system", "users"])),
      tenants_migrated: count_tenant_directories(),
      backup_location: @backup_dir,
      next_steps: [
        "Verify migrated data integrity",
        "Update application configuration to use enhanced storage",
        "Run comprehensive tests",
        "Remove backup after verification (optional)"
      ]
    }

    report_file = Path.join(@data_root, "migration_report.json")
    case Jason.encode(report, pretty: true) do
      {:ok, json} ->
        File.write(report_file, json)
        Logger.info("📊 Migration report saved to: #{report_file}")

        # Log summary
        Logger.info("📈 Migration Summary:")
        Logger.info("   - Users migrated: #{report.users_migrated}")
        Logger.info("   - Tenants migrated: #{report.tenants_migrated}")
        Logger.info("   - Directories created: #{report.directories_created}")

        :ok
      error -> error
    end
  end

  # Private helper functions

  defp load_legacy_users do
    try do
      users = FSStore.load("accounts", "users")
      {:ok, users}
    rescue
      _ -> {:error, :not_found}
    end
  end

  defp load_legacy_tenants do
    try do
      tenants = FSStore.load("tenancy", "tenants")
      {:ok, tenants}
    rescue
      _ -> {:error, :not_found}
    end
  end

  defp load_legacy_memberships do
    try do
      memberships = FSStore.load("tenancy", "memberships")
      {:ok, memberships}
    rescue
      _ -> {:error, :not_found}
    end
  end

  defp transform_user_data(user_data) do
    %FSMApp.Accounts.User{
      id: user_data["id"],
      email: user_data["email"],
      name: extract_name_from_email(user_data["email"]),
      avatar_url: nil,
      hashed_password: user_data["hashed_password"],
      inserted_at: parse_timestamp(user_data["inserted_at"]),
      updated_at: parse_timestamp(user_data["updated_at"]),
      last_login: nil,
      email_verified: user_data["confirmed_at"] != nil,
      status: :active,
      platform_role: determine_platform_role(user_data),
      confirmed_at: parse_timestamp(user_data["confirmed_at"])
    }
  end

  defp transform_membership_data(membership_data) do
    role = membership_data["role"] |> String.to_atom()

    %FSMApp.Tenancy.Member{
      tenant_id: membership_data["tenant_id"],
      user_id: membership_data["user_id"],
      tenant_role: role,
      permissions: FSMApp.Tenancy.Member.default_permissions_for_role(role),
      joined_at: parse_timestamp(membership_data["inserted_at"]),
      invited_by: nil,  # Not available in legacy data
      member_status: :active,
      last_activity: parse_timestamp(membership_data["updated_at"])
    }
  end

  defp migrate_single_tenant(tenant_data) do
    tenant_id = tenant_data["id"]

    # Create tenant config
    tenant_config = %{
      "id" => tenant_id,
      "name" => tenant_data["name"],
      "slug" => tenant_data["slug"],
      "created_at" => tenant_data["inserted_at"],
      "updated_at" => tenant_data["updated_at"],
      "settings" => %{
        "timezone" => "UTC",
        "default_permissions" => FSMApp.Tenancy.Member.default_permissions_for_role(:member)
      }
    }

    EnhancedStore.store_tenant_config(tenant_id, tenant_config)
  end

  defp find_tenant_directories_with_fsm_data do
    if File.exists?(@data_root) do
      @data_root
      |> File.ls!()
      |> Enum.filter(fn dir ->
        dir_path = Path.join(@data_root, dir)
        File.dir?(dir_path) and has_fsm_subdirectory?(dir_path)
      end)
    else
      []
    end
  end

  defp has_fsm_subdirectory?(dir_path) do
    fsm_path = Path.join(dir_path, "fsm")
    File.exists?(fsm_path) and File.dir?(fsm_path)
  end

  defp migrate_tenant_fsm_data(tenant_id) do
    fsm_dir = Path.join([@data_root, tenant_id, "fsm"])
    workflows_dir = Path.join([@data_root, "tenants", tenant_id, "workflows"])

    if File.exists?(fsm_dir) do
      # Create workflows directory
      File.mkdir_p!(workflows_dir)

      # Copy FSM files to workflows directory
      case File.cp_r(fsm_dir, workflows_dir) do
        {:ok, _} ->
          Logger.debug("✅ Migrated FSM data for tenant #{tenant_id}")
          [:ok]
        error ->
          Logger.warning("⚠️  Failed to migrate FSM data for tenant #{tenant_id}: #{inspect(error)}")
          [error]
      end
    else
      []
    end
  end

  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(["-", "_", "."], " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp determine_platform_role(user_data) do
    # For now, make first user platform admin, others regular users
    # In production, this would use more sophisticated logic
    :user
  end

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_timestamp(%DateTime{} = dt), do: dt
  defp parse_timestamp(_), do: DateTime.utc_now()

  defp count_directories_in_path(path) do
    if File.exists?(path) do
      path
      |> File.ls!()
      |> Enum.count(&File.dir?(Path.join(path, &1)))
    else
      0
    end
  end

  defp count_files_in_path(path) do
    if File.exists?(path) do
      path
      |> File.ls!()
      |> Enum.count(&File.regular?(Path.join(path, &1)))
    else
      0
    end
  end

  defp count_tenant_directories do
    tenants_path = Path.join([@data_root, "tenants"])
    count_directories_in_path(tenants_path)
  end
end
