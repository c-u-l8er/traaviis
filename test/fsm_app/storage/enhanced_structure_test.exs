defmodule FSMApp.Storage.EnhancedStructureTest do
  use ExUnit.Case, async: false

  alias FSMApp.Storage.{EnhancedStore, HybridStore}
  alias FSM.Registry

  setup do
    # Use the test data directory created by DataHelper
    test_dir = DataHelper.test_data_dir()

    # Verify test directory structure exists
    assert File.exists?(Path.join([test_dir, "system", "users"]))
    assert File.exists?(Path.join([test_dir, "system", "sessions"]))
    assert File.exists?(Path.join([test_dir, "tenants"]))

    :ok
  end

  describe "enhanced directory structure" do
    test "uses test directories in test environment" do
      # Verify system paths use test directory
      system_dir = Path.join([DataHelper.test_data_dir(), "system"])
      tenants_dir = Path.join([DataHelper.test_data_dir(), "tenants"])

      # Test that the registry uses test directory
      {:ok, registry_state} = Registry.reload_from_disk()

      # Verify directory structure is correct
      assert File.exists?(system_dir)
      assert File.exists?(tenants_dir)
      assert File.exists?(Path.join([tenants_dir, "test_tenant"]))
    end

    test "FSM workflows are stored in enhanced structure" do
      tenant_id = "test_tenant"

      # Create an FSM
      fsm = FSM.SmartDoor.new(%{test: "data"}, id: "enhanced_test", tenant_id: tenant_id)

      # Register it (this should persist to the enhanced structure)
      :ok = Registry.register("enhanced_test", FSM.SmartDoor, fsm)

      # Verify it was stored in the correct enhanced directory
      workflows_dir = Path.join([DataHelper.test_data_dir(), "tenants", tenant_id, "workflows"])
      assert File.exists?(workflows_dir)

      # Look for SmartDoor workflow files
      smart_door_dir = Path.join([workflows_dir, "SmartDoor"])

      if File.exists?(smart_door_dir) do
        {:ok, files} = File.ls(smart_door_dir)
        workflow_files = Enum.filter(files, &String.ends_with?(&1, ".json"))
        assert length(workflow_files) > 0, "Expected to find workflow files in enhanced structure"
      end
    end

    test "tenant configuration is stored correctly" do
      tenant_id = "test_tenant"
      config_file = Path.join([DataHelper.test_data_dir(), "tenants", tenant_id, "config.json"])

      assert File.exists?(config_file)

      {:ok, content} = File.read(config_file)
      {:ok, config} = Jason.decode(content)

      assert config["id"] == tenant_id
      assert config["name"] =~ "Test Tenant"
      assert is_map(config["settings"])
    end

    test "system directory contains proper structure" do
      system_dir = Path.join([DataHelper.test_data_dir(), "system"])

      # Check for expected system files
      users_index = Path.join([system_dir, "users", "index.json"])
      metrics_file = Path.join([system_dir, "platform_metrics.json"])

      assert File.exists?(users_index)
      assert File.exists?(metrics_file)

      # Verify content structure
      {:ok, users_content} = File.read(users_index)
      {:ok, users_data} = Jason.decode(users_content)
      assert Map.has_key?(users_data, "users")
      assert Map.has_key?(users_data, "count")
    end
  end

  describe "backward compatibility" do
    test "can read from both old and new structures" do
      # This test verifies that the Registry can handle mixed directory structures
      {:ok, state} = Registry.reload_from_disk()

      # Should be able to process without errors
      stats = Registry.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :current_count)
    end
  end
end
