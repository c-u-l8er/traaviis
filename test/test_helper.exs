ExUnit.start()

# Set up test environment
Application.put_env(:fsm_app, :env, :test)

# Load test helpers
Code.require_file("support/data_helper.ex", __DIR__)

# Setup enhanced directory structure for tests
DataHelper.setup_test_directories()

# Cleanup after all tests
ExUnit.after_suite(fn _result ->
  DataHelper.cleanup_test_data()
end)
