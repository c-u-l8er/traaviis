defmodule FSMApp.Storage.EnhancedStore do
  @moduledoc """
  Enhanced filesystem storage implementing the dual-level directory structure.

  Directory Structure:
  ./data/
  ├── system/                         # Global platform data
  │   ├── users/
  │   │   ├── user_{uuid}.json        # Global user accounts
  │   │   └── index.json              # User lookup index
  │   ├── sessions/
  │   │   └── active_sessions.json    # User session data
  │   └── platform_metrics.json      # System-wide metrics
  ├── tenants/                        # Tenant-isolated data
  │   ├── {tenant_uuid}/
  │   │   ├── config.json             # Tenant configuration
  │   │   ├── members/
  │   │   │   ├── member_{user_uuid}.json  # Member profiles
  │   │   │   ├── roster.json         # Member roster summary
  │   │   │   └── invitations.json    # Pending invitations
  │   │   ├── workflows/              # FSM workflows (renamed from fsm/)
  │   │   │   ├── {Module}/{fsm_id}.json   # FSM snapshots
  │   │   │   └── templates/          # Tenant-specific templates
  │   │   ├── events/                 # Event streams
  │   │   │   └── {Module}/{fsm_id}/  # Event streams (JSONL)
  │   │   ├── effects/                # Effects execution data
  │   │   │   ├── executions/         # Effect execution logs
  │   │   │   └── metrics/            # Performance metrics
  │   │   └── billing/
  │   │       ├── usage/
  │   │       │   └── YYYY-MM.json    # Monthly usage data
  │   │       └── invoices/
  │   │           └── inv_{uuid}.json # Generated invoices
  │   └── index.json                  # Tenant lookup index
  """

  require Logger
  alias Jason

  @data_root Path.expand("data")
  @system_root Path.join(@data_root, "system")
  @tenants_root Path.join(@data_root, "tenants")

  # System-level storage operations

  @doc """
  Store a global platform user.
  """
  def store_user(user) do
    user_id = user.id || raise ArgumentError, "User must have an id"
    file_path = user_file_path(user_id)

    # Add stored_at timestamp to the struct instead of converting to map first
    # This preserves the @derive Jason.Encoder directive
    user_with_stored_at = Map.put(user, :stored_at, DateTime.utc_now() |> DateTime.to_iso8601())

    with :ok <- ensure_directory_exists(Path.dirname(file_path)),
         :ok <- write_json_file(file_path, user_with_stored_at),
         :ok <- update_user_index(user_id, user.email) do
      Logger.info("Stored user #{user_id} in enhanced directory structure")
      :ok
    else
      error ->
        Logger.error("Failed to store user #{user_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Load a global platform user.
  """
  def load_user(user_id) do
    file_path = user_file_path(user_id)

    case read_json_file(file_path) do
      {:ok, data} ->
        Logger.debug("Loaded user #{user_id} from enhanced storage")
        {:ok, data}
      error ->
        Logger.debug("User #{user_id} not found in enhanced storage: #{inspect(error)}")
        error
    end
  end

  @doc """
  List all platform users with optional filtering.
  """
  def list_users(opts \\ []) do
    users_dir = Path.join(@system_root, "users")

    case File.ls(users_dir) do
      {:ok, files} ->
        users = files
        |> Enum.filter(&String.ends_with?(&1, ".json") and String.starts_with?(&1, "user_"))
        |> Enum.map(fn filename ->
          file_path = Path.join(users_dir, filename)
          case read_json_file(file_path) do
            {:ok, user_data} -> user_data
            _ -> nil
          end
        end)
        |> Enum.filter(& &1)
        |> apply_user_filters(opts)

        {:ok, users}
      error -> error
    end
  end

  # Tenant-level storage operations

  @doc """
  Store a tenant member.
  """
  def store_member(tenant_id, member) do
    user_id = member.user_id || raise ArgumentError, "Member must have a user_id"
    file_path = member_file_path(tenant_id, user_id)

    member_data = Map.from_struct(member)
    |> Map.put(:stored_at, DateTime.utc_now() |> DateTime.to_iso8601())

    with :ok <- ensure_directory_exists(Path.dirname(file_path)),
         :ok <- write_json_file(file_path, member_data),
         :ok <- update_member_roster(tenant_id, user_id, member.tenant_role) do
      Logger.info("Stored member #{user_id} for tenant #{tenant_id}")
      :ok
    else
      error ->
        Logger.error("Failed to store member #{user_id} for tenant #{tenant_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Load a tenant member.
  """
  def load_member(tenant_id, user_id) do
    file_path = member_file_path(tenant_id, user_id)

    case read_json_file(file_path) do
      {:ok, data} ->
        Logger.debug("Loaded member #{user_id} from tenant #{tenant_id}")
        {:ok, data}
      error ->
        Logger.debug("Member #{user_id} not found in tenant #{tenant_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  List all members of a tenant.
  """
  def list_tenant_members(tenant_id) do
    members_dir = Path.join([@tenants_root, tenant_id, "members"])

    case File.ls(members_dir) do
      {:ok, files} ->
        members = files
        |> Enum.filter(&String.ends_with?(&1, ".json") and String.starts_with?(&1, "member_"))
        |> Enum.map(fn filename ->
          file_path = Path.join(members_dir, filename)
          case read_json_file(file_path) do
            {:ok, member_data} -> member_data
            _ -> nil
          end
        end)
        |> Enum.filter(& &1)

        {:ok, members}
      error -> error
    end
  end

  @doc """
  Store tenant configuration.
  """
  def store_tenant_config(tenant_id, config) do
    file_path = tenant_config_file_path(tenant_id)

    config_data = Map.merge(config, %{
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "tenant_id" => tenant_id
    })

    with :ok <- ensure_directory_exists(Path.dirname(file_path)),
         :ok <- write_json_file(file_path, config_data) do
      Logger.info("Stored config for tenant #{tenant_id}")
      :ok
    else
      error ->
        Logger.error("Failed to store config for tenant #{tenant_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Load tenant configuration.
  """
  def load_tenant_config(tenant_id) do
    file_path = tenant_config_file_path(tenant_id)
    read_json_file(file_path)
  end

  @doc """
  Initialize the enhanced directory structure.
  """
  def initialize_directory_structure do
    directories = [
      Path.join(@system_root, "users"),
      Path.join(@system_root, "sessions"),
      @tenants_root
    ]

    results = Enum.map(directories, &ensure_directory_exists/1)

    if Enum.all?(results, &(&1 == :ok)) do
      # Initialize index files
      with :ok <- initialize_user_index(),
           :ok <- initialize_tenant_index() do
        Logger.info("Enhanced directory structure initialized successfully")
        :ok
      end
    else
      Logger.error("Failed to initialize some directories: #{inspect(results)}")
      {:error, :directory_creation_failed}
    end
  end

  @doc """
  Migrate data from old structure to new enhanced structure.
  """
  def migrate_from_legacy do
    Logger.info("Starting migration from legacy to enhanced directory structure")

    with {:ok, _} <- migrate_users(),
         {:ok, _} <- migrate_tenants(),
         {:ok, _} <- migrate_fsm_data() do
      Logger.info("Migration completed successfully")
      :ok
    else
      error ->
        Logger.error("Migration failed: #{inspect(error)}")
        error
    end
  end

  # Private helper functions

  defp user_file_path(user_id) do
    Path.join([@system_root, "users", "user_#{user_id}.json"])
  end

  defp member_file_path(tenant_id, user_id) do
    Path.join([@tenants_root, tenant_id, "members", "member_#{user_id}.json"])
  end

  defp tenant_config_file_path(tenant_id) do
    Path.join([@tenants_root, tenant_id, "config.json"])
  end

  defp user_index_file_path do
    Path.join([@system_root, "users", "index.json"])
  end

  defp tenant_index_file_path do
    Path.join(@tenants_root, "index.json")
  end

  defp ensure_directory_exists(dir_path) do
    case File.mkdir_p(dir_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp write_json_file(file_path, data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write(file_path, json)
      error -> error
    end
  end

  defp read_json_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> Jason.decode(content)
      error -> error
    end
  end

  defp update_user_index(user_id, email) do
    index_file = user_index_file_path()

    current_index = case read_json_file(index_file) do
      {:ok, index} -> index
      _ -> %{}
    end

    updated_index = Map.put(current_index, user_id, %{
      "email" => email,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    write_json_file(index_file, updated_index)
  end

  defp update_member_roster(tenant_id, user_id, role) do
    roster_file = Path.join([@tenants_root, tenant_id, "members", "roster.json"])

    current_roster = case read_json_file(roster_file) do
      {:ok, roster} -> roster
      _ -> %{"members" => %{}, "count" => 0}
    end

    updated_members = Map.put(current_roster["members"] || %{}, user_id, %{
      "role" => to_string(role),
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    updated_roster = %{
      "members" => updated_members,
      "count" => map_size(updated_members),
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    with :ok <- ensure_directory_exists(Path.dirname(roster_file)) do
      write_json_file(roster_file, updated_roster)
    end
  end

  defp initialize_user_index do
    index_file = user_index_file_path()
    initial_index = %{
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "version" => "1.0.0"
    }
    write_json_file(index_file, initial_index)
  end

  defp initialize_tenant_index do
    index_file = tenant_index_file_path()
    initial_index = %{
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "version" => "1.0.0"
    }
    write_json_file(index_file, initial_index)
  end

  defp apply_user_filters(users, opts) do
    users
    |> filter_by_status(Keyword.get(opts, :status))
    |> filter_by_role(Keyword.get(opts, :platform_role))
    |> sort_users(Keyword.get(opts, :sort_by, :created_at))
  end

  defp filter_by_status(users, nil), do: users
  defp filter_by_status(users, status) do
    Enum.filter(users, &(Map.get(&1, "status") == to_string(status)))
  end

  defp filter_by_role(users, nil), do: users
  defp filter_by_role(users, role) do
    Enum.filter(users, &(Map.get(&1, "platform_role") == to_string(role)))
  end

  defp sort_users(users, :created_at) do
    Enum.sort_by(users, &Map.get(&1, "created_at", ""), &>=/2)
  end
  defp sort_users(users, :email) do
    Enum.sort_by(users, &Map.get(&1, "email", ""))
  end
  defp sort_users(users, _), do: users

  defp migrate_users do
    # TODO: Implement migration from old accounts/users structure
    {:ok, []}
  end

  defp migrate_tenants do
    # TODO: Implement migration from old tenancy structure
    {:ok, []}
  end

  defp migrate_fsm_data do
    # TODO: Implement migration from old FSM data structure
    {:ok, []}
  end
end
