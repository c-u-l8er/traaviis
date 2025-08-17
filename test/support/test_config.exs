# Test configuration for FSM system

# Set test environment
Application.put_env(:fsm_app, :env, :test)

# Configure test logging
Application.put_env(:fsm_app, :log_level, :warn)

# Configure test timeouts
Application.put_env(:fsm_app, :test_timeout, 5000)

# Configure test data directory (enhanced structure)
Application.put_env(:fsm_app, :test_data_dir, "test/tmp/data")

# Configure test data
Application.put_env(:fsm_app, :test_data, %{
  default_user: "test_user",
  default_tenant: "test_tenant",
  test_sensors: ["door_sensor_1", "motion_sensor_1", "window_sensor_1"],
  # Enhanced directory structure test tenants
  test_tenants: ["test_tenant", "tenant1", "tenant2", "t-retain", "t-broadcast"]
})
