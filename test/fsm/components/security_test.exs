defmodule FSM.Components.SecurityTest do
  use ExUnit.Case
  alias FSM.Components.Security

  describe "Security Component" do
    test "has correct states" do
      states = Security.states()
      assert :unlocked in states
      assert :locked in states
      assert :alarm in states
      assert length(states) == 3
    end

    test "has correct transitions" do
      transitions = Security.transitions()

      # Check unlocked transitions
      assert {:unlocked, :lock, :locked, []} in transitions
      assert {:unlocked, :intrusion_detected, :alarm, []} in transitions

      # Check locked transitions
      assert {:locked, :correct_key, :unlocked, []} in transitions
      assert {:locked, :forced_entry, :alarm, []} in transitions

      # Check alarm transitions
      assert {:alarm, :alarm_reset, :locked, []} in transitions

      assert length(transitions) == 5
    end

    test "creates security data structure" do
      security_data = %{
        security_level: :high,
        last_activity: DateTime.utc_now(),
        failed_attempts: 0,
        lockout_until: nil,
        alarm_sensors: [:motion, :door, :window]
      }

      assert is_map(security_data)
      assert security_data.security_level == :high
      assert security_data.failed_attempts == 0
      assert length(security_data.alarm_sensors) == 3
    end

    test "gets security level correctly" do
      security_data = %{security_level: :critical}
      assert Security.get_security_level(security_data) == :critical

      # Test with invalid data
      assert Security.get_security_level(nil) == :normal
      assert Security.get_security_level(%{}) == :normal
    end

    test "checks access permissions correctly" do
      high_security = %{security_level: :high}
      normal_security = %{security_level: :normal}
      low_security = %{security_level: :low}

      # High security should allow access to normal level
      assert Security.access_allowed?(high_security, :normal) == true

      # Normal security should allow access to normal level
      assert Security.access_allowed?(normal_security, :normal) == true

      # Low security should not allow access to high level
      assert Security.access_allowed?(low_security, :high) == false

      # Normal security should not allow access to high level
      assert Security.access_allowed?(normal_security, :high) == false
    end

    test "handles utility functions" do
      fsm = %{data: %{}}
      assert %{data: %{}} = Security.log_security_event(fsm, :test_event)
      assert %{data: %{}} = Security.activate_security_monitoring(fsm)
      assert %{data: %{}} = Security.trigger_alarm_system(fsm)
      assert %{data: %{}} = Security.notify_security_personnel(fsm)
      assert %{data: %{}} = Security.deactivate_alarm_system(fsm)
    end

    test "handles validation functions" do
      fsm = %{data: %{security_level: :high}}

      {:ok, _} = Security.check_security_credentials(fsm, :test_event, %{})
      {:ok, _} = Security.check_lockout_status(fsm, :test_event, %{})
    end
  end

  describe "Security Component FSM functionality" do
    test "creates FSM instance" do
      fsm = Security.new()
      assert fsm.current_state == :unlocked
    end

    test "transitions from unlocked to locked" do
      fsm = Security.new()
      {:ok, new_fsm} = Security.navigate(fsm, :lock)
      assert new_fsm.current_state == :locked
    end

    test "transitions from unlocked to alarm on intrusion" do
      fsm = Security.new()
      {:ok, new_fsm} = Security.navigate(fsm, :intrusion_detected)
      assert new_fsm.current_state == :alarm
    end

    test "transitions from locked to unlocked with correct key" do
      fsm = Security.new()
      {:ok, locked_fsm} = Security.navigate(fsm, :lock)
      {:ok, unlocked_fsm} = Security.navigate(locked_fsm, :correct_key)
      assert unlocked_fsm.current_state == :unlocked
    end

    test "transitions from locked to alarm on forced entry" do
      fsm = Security.new()
      {:ok, locked_fsm} = Security.navigate(fsm, :lock)
      {:ok, alarm_fsm} = Security.navigate(locked_fsm, :forced_entry)
      assert alarm_fsm.current_state == :alarm
    end

    test "transitions from alarm to locked on reset" do
      fsm = Security.new()
      {:ok, locked_fsm} = Security.navigate(fsm, :lock)
      {:ok, alarm_fsm} = Security.navigate(locked_fsm, :forced_entry)
      {:ok, reset_fsm} = Security.navigate(alarm_fsm, :alarm_reset)
      assert reset_fsm.current_state == :locked
    end

    test "handles invalid transitions gracefully" do
      fsm = Security.new()

      # Try to unlock from unlocked (invalid)
      {:error, :invalid_transition} = Security.navigate(fsm, :correct_key)

      # Try to lock from unlocked (valid)
      {:ok, locked_fsm} = Security.navigate(fsm, :lock)

      # Try to detect intrusion from locked (invalid)
      {:error, :invalid_transition} = Security.navigate(locked_fsm, :intrusion_detected)
    end

    test "executes lifecycle hooks correctly" do
      fsm = Security.new()

      # Lock the door (should trigger on_enter :locked)
      {:ok, locked_fsm} = Security.navigate(fsm, :lock)

      # Trigger alarm (should trigger on_enter :alarm)
      {:ok, alarm_fsm} = Security.navigate(locked_fsm, :forced_entry)

      # Reset alarm (should trigger on_exit :alarm)
      {:ok, _reset_fsm} = Security.navigate(alarm_fsm, :alarm_reset)
    end
  end
end
