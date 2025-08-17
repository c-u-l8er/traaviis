defmodule DataHelper do
  @moduledoc """
  Test helper for managing enhanced directory structure in tests.
  """

  @test_data_dir "test/tmp/data"

  def setup_test_directories do
    # Clean up any existing test data
    cleanup_test_data()

    # Create enhanced directory structure for testing
    File.mkdir_p!(Path.join([@test_data_dir, "system", "users"]))
    File.mkdir_p!(Path.join([@test_data_dir, "system", "sessions"]))
    File.mkdir_p!(Path.join([@test_data_dir, "tenants"]))

    # Create test tenant directories
    create_test_tenant_directories([
      "test_tenant",
      "tenant1",
      "tenant2",
      "t-retain",
      "t-broadcast"
    ])

    # Initialize index files
    initialize_index_files()

    # Set test data directory
    Application.put_env(:fsm_app, :test_data_dir, @test_data_dir)

    :ok
  end

  def cleanup_test_data do
    if File.exists?(@test_data_dir) do
      File.rm_rf!(@test_data_dir)
    end
    :ok
  end

  def create_test_tenant(tenant_id) do
    create_test_tenant_directories([tenant_id])
  end

  def test_data_dir, do: @test_data_dir

  def tenant_workflow_dir(tenant_id) do
    Path.join([@test_data_dir, "tenants", tenant_id, "workflows"])
  end

  def system_users_dir do
    Path.join([@test_data_dir, "system", "users"])
  end

  defp create_test_tenant_directories(tenant_ids) do
    Enum.each(tenant_ids, fn tenant_id ->
      tenant_dir = Path.join([@test_data_dir, "tenants", tenant_id])

      # Create all tenant subdirectories
      File.mkdir_p!(Path.join([tenant_dir, "workflows"]))
      File.mkdir_p!(Path.join([tenant_dir, "members"]))
      File.mkdir_p!(Path.join([tenant_dir, "events"]))
      File.mkdir_p!(Path.join([tenant_dir, "effects"]))
      File.mkdir_p!(Path.join([tenant_dir, "billing"]))

      # Create tenant config
      config = %{
        id: tenant_id,
        name: "Test Tenant #{tenant_id}",
        slug: tenant_id,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        settings: %{
          timezone: "UTC",
          default_permissions: ["workflow_create", "workflow_execute"],
          ai_model_access: true
        }
      }

      config_path = Path.join([tenant_dir, "config.json"])
      File.write!(config_path, Jason.encode!(config, pretty: true))
    end)
  end

  defp initialize_index_files do
    # System users index
    users_index = %{users: %{}, count: 0, updated_at: DateTime.utc_now()}
    users_index_path = Path.join([@test_data_dir, "system", "users", "index.json"])
    File.write!(users_index_path, Jason.encode!(users_index, pretty: true))

    # System metrics
    metrics = %{
      platform_stats: %{
        total_users: 0,
        active_tenants: 0,
        total_workflows: 0
      },
      updated_at: DateTime.utc_now()
    }
    metrics_path = Path.join([@test_data_dir, "system", "platform_metrics.json"])
    File.write!(metrics_path, Jason.encode!(metrics, pretty: true))

    # Tenants index
    tenants_index = %{tenants: %{}, count: 0, updated_at: DateTime.utc_now()}
    tenants_index_path = Path.join([@test_data_dir, "tenants", "index.json"])
    File.write!(tenants_index_path, Jason.encode!(tenants_index, pretty: true))
  end
end
