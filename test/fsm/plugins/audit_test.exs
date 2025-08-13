defmodule FSM.Plugins.AuditTest do
  use ExUnit.Case
  alias FSM.Plugins.Audit

  describe "Audit Plugin" do
    test "initializes correctly" do
      fsm = %{data: %{}}
      initialized_fsm = Audit.init(fsm, [])

      # Should return FSM unchanged
      assert initialized_fsm == fsm
    end

    test "handles before_transition hook" do
      fsm = %{id: "test_fsm", data: %{}}
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      result = Audit.before_transition(fsm, transition_data, [])

      # Should return the FSM unchanged
      assert result == fsm
    end

    test "handles after_transition hook" do
      fsm = %{id: "test_fsm", data: %{}}
      transition_data = {:closed, :opening, :open_command, %{user_id: "user123"}}

      result = Audit.after_transition(fsm, transition_data, [])

      # Should return the FSM unchanged
      assert result == fsm
    end

    test "preserves FSM data during hooks" do
      fsm = %{
        id: "test_fsm",
        data: %{
          custom_data: "preserved",
          audit_trail: []
        }
      }
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      result = Audit.before_transition(fsm, transition_data, [])

      # Custom data should be preserved
      assert result.data[:custom_data] == "preserved"
      assert result.data[:audit_trail] == []
    end

    test "handles various transition data formats" do
      fsm = %{id: "test_fsm", data: %{}}

      # Test different transition data formats
      transition_data_1 = {:closed, :open_command, %{user_id: "user123"}}
      transition_data_2 = {:opening, :fully_open, %{}}
      transition_data_3 = {:open, :close_command, %{user_id: "user456"}}

      # All should work without errors
      result1 = Audit.before_transition(fsm, transition_data_1, [])
      result2 = Audit.before_transition(fsm, transition_data_2, [])
      result3 = Audit.before_transition(fsm, transition_data_3, [])

      assert result1 == fsm
      assert result2 == fsm
      assert result3 == fsm
    end

    test "handles empty transition data" do
      fsm = %{id: "test_fsm", data: %{}}
      transition_data = {:closed, :open_command, %{}}

      result = Audit.before_transition(fsm, transition_data, [])
      assert result == fsm
    end

    test "handles nil transition data" do
      fsm = %{id: "test_fsm", data: %{}}
      transition_data = {:closed, :open_command, nil}

      result = Audit.before_transition(fsm, transition_data, [])
      assert result == fsm
    end

    test "works with different plugin options" do
      fsm = %{id: "test_fsm", data: %{}}
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      # Test with different options
      result1 = Audit.before_transition(fsm, transition_data, [])
      result2 = Audit.before_transition(fsm, transition_data, [level: :detailed])
      result3 = Audit.before_transition(fsm, transition_data, [retention: :days_30])

      # All should work and return FSM unchanged
      assert result1 == fsm
      assert result2 == fsm
      assert result3 == fsm
    end

    test "maintains FSM identity" do
      fsm = %{id: "test_fsm", data: %{}}
      transition_data = {:closed, :open_command, %{user_id: "user123"}}

      result = Audit.before_transition(fsm, transition_data, [])

      # FSM should maintain its identity
      assert result.id == fsm.id
      assert result.data == fsm.data
    end
  end
end
