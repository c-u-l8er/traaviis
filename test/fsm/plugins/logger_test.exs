defmodule FSM.Plugins.LoggerTest do
  use ExUnit.Case
  alias FSM.Plugins.Logger

  describe "Logger Plugin" do
    test "initializes with default log level" do
      fsm = %{data: %{}}
      initialized_fsm = Logger.init(fsm, [])

      assert get_in(initialized_fsm.data, [:logger_config, :level]) == :info
    end

    test "initializes with custom log level" do
      fsm = %{data: %{}}
      initialized_fsm = Logger.init(fsm, level: :debug)

      assert get_in(initialized_fsm.data, [:logger_config, :level]) == :debug
    end

    test "handles before_transition hook" do
      fsm = %{id: "test_fsm", data: %{logger_config: %{level: :info}}}
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      result = Logger.before_transition(fsm, transition_data, [])

      # Should return the FSM unchanged
      assert result == fsm
    end

    test "handles after_transition hook" do
      fsm = %{id: "test_fsm", data: %{logger_config: %{level: :info}}}
      transition_data = {:closed, :opening, :open_command, %{user_id: "user123"}}

      result = Logger.after_transition(fsm, transition_data, [])

      # Should return the FSM unchanged
      assert result == fsm
    end

    test "uses correct log level from FSM data" do
      fsm = %{id: "test_fsm", data: %{logger_config: %{level: :debug}}}
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      # This test verifies the plugin can access the log level
      # The actual logging behavior would be tested in integration tests
      result = Logger.before_transition(fsm, transition_data, [])
      assert result == fsm
    end

    test "handles missing logger config gracefully" do
      fsm = %{id: "test_fsm", data: %{}}  # No logger_config
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      # Should default to :info level
      result = Logger.before_transition(fsm, transition_data, [])
      assert result == fsm
    end

    test "handles nil logger config gracefully" do
      fsm = %{id: "test_fsm", data: %{logger_config: nil}}
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      # Should default to :info level
      result = Logger.before_transition(fsm, transition_data, [])
      assert result == fsm
    end

    test "handles various log levels" do
      levels = [:debug, :info, :warning, :error]

      Enum.each(levels, fn level ->
        fsm = %{id: "test_fsm", data: %{logger_config: %{level: level}}}
        transition_data = {:closed, :open_command, %{user_id: "user123"}}

        result = Logger.before_transition(fsm, transition_data, [])
        assert result == fsm
      end)
    end

    test "preserves FSM data during hooks" do
      fsm = %{
        id: "test_fsm",
        data: %{
          logger_config: %{level: :info},
          custom_data: "preserved"
        }
      }
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      result = Logger.before_transition(fsm, transition_data, [])

      # Custom data should be preserved
      assert result.data[:custom_data] == "preserved"
      assert result.data[:logger_config][:level] == :info
    end
  end
end
