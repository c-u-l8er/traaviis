defmodule FSM.IntegrationTest do
  use ExUnit.Case
  alias FSM.SmartDoor
  alias FSM.Components.Timer
  alias FSM.Components.Security

  describe "FSM System Integration" do
    test "complete door operation cycle" do
      # Create a new SmartDoor FSM
      fsm = SmartDoor.new(%{}, id: "integration_test", tenant_id: "test_tenant")
      assert fsm.current_state == :closed

      # Open the door
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      assert opening_fsm.current_state == :opening

      # Complete opening
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})
      assert open_fsm.current_state == :open

      # Close the door
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :close_command, %{user_id: "user123"})
      assert closing_fsm.current_state == :closing

      # Complete closing
      {:ok, closed_fsm} = SmartDoor.navigate(closing_fsm, :fully_closed, %{})
      assert closed_fsm.current_state == :closed

      # Verify the complete cycle
      assert closed_fsm.performance[:transition_count] == 4
    end

    test "component integration with lifecycle hooks" do
      # Create FSM and open door to trigger timer
      fsm = SmartDoor.new(%{}, id: "timer_test", tenant_id: "test_tenant")

      # Open door (should start auto-close timer)
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Check that timer was started when door is fully open
      assert Map.has_key?(open_fsm.data, :timers)
      assert Map.has_key?(open_fsm.data[:timers], :auto_close)
    end

    test "security integration with emergency scenarios" do
      # Create FSM and test emergency lock
      fsm = SmartDoor.new(%{}, id: "security_test", tenant_id: "test_tenant")

      # Trigger emergency lock
      {:ok, emergency_fsm} = SmartDoor.navigate(fsm, :emergency_lock, %{reason: :security_breach})
      assert emergency_fsm.current_state == :emergency_lock

      # Clear emergency
      {:ok, closed_fsm} = SmartDoor.navigate(emergency_fsm, :emergency_clear, %{authorized_by: "security_officer"})
      assert closed_fsm.current_state == :closed
    end

    test "obstruction handling during operations" do
      # Create FSM and test obstruction scenarios
      fsm = SmartDoor.new(%{}, id: "obstruction_test", tenant_id: "test_tenant")

      # Start opening
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})

      # Detect obstruction during opening
      {:ok, closed_fsm} = SmartDoor.navigate(opening_fsm, :obstruction, %{sensor: "door_sensor_1"})
      assert closed_fsm.current_state == :closed

      # Try opening again
      {:ok, opening_fsm2} = SmartDoor.navigate(closed_fsm, :open_command, %{user_id: "user123"})
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm2, :fully_open, %{})

      # Start closing
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :close_command, %{user_id: "user123"})

      # Detect obstruction during closing
      {:ok, opening_fsm3} = SmartDoor.navigate(closing_fsm, :obstruction, %{sensor: "door_sensor_1"})
      assert opening_fsm3.current_state == :opening
    end

    test "auto-close functionality" do
      # Create FSM and test auto-close
      fsm = SmartDoor.new(%{}, id: "auto_close_test", tenant_id: "test_tenant")

      # Open door
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Simulate auto-close timer
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :auto_close, %{timer: "auto_close_timer"})
      assert closing_fsm.current_state == :closing

      # Complete closing
      {:ok, closed_fsm} = SmartDoor.navigate(closing_fsm, :fully_closed, %{})
      assert closed_fsm.current_state == :closed
    end

    test "external event handling" do
      # Create FSM and test external security events
      fsm = SmartDoor.new(%{}, id: "external_test", tenant_id: "test_tenant")

      # Simulate external security system alarm
      updated_fsm = SmartDoor.handle_external_event(fsm, :SecuritySystem, :state_changed, %{to: :alarm})
      assert updated_fsm.current_state == :emergency_lock

      # Clear emergency
      {:ok, closed_fsm} = SmartDoor.navigate(updated_fsm, :emergency_clear, %{authorized_by: "security_officer"})
      assert closed_fsm.current_state == :closed
    end

    test "data persistence across transitions" do
      # Create FSM with initial data
      fsm = SmartDoor.new(%{user_id: "user123", session_id: "session456"}, id: "data_test", tenant_id: "test_tenant")

      # Verify initial data
      assert fsm.data[:user_id] == "user123"
      assert fsm.data[:session_id] == "session456"

      # Open door with additional data
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{timestamp: "2024-01-01", location: "main_entrance"})

      # Verify data is merged
      assert opening_fsm.data[:user_id] == "user123"
      assert opening_fsm.data[:session_id] == "session456"
      assert opening_fsm.data[:timestamp] == "2024-01-01"
      assert opening_fsm.data[:location] == "main_entrance"

      # Complete opening
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Verify data persists
      assert open_fsm.data[:user_id] == "user123"
      assert open_fsm.data[:session_id] == "session456"
      assert open_fsm.data[:timestamp] == "2024-01-01"
      assert open_fsm.data[:location] == "main_entrance"
    end

    test "performance metrics tracking" do
      # Create FSM and perform multiple transitions
      fsm = SmartDoor.new(%{}, id: "performance_test", tenant_id: "test_tenant")

      # Perform several transitions
      {:ok, fsm1} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      {:ok, fsm2} = SmartDoor.navigate(fsm1, :fully_open, %{})
      {:ok, fsm3} = SmartDoor.navigate(fsm2, :close_command, %{user_id: "user123"})
      {:ok, fsm4} = SmartDoor.navigate(fsm3, :fully_closed, %{})

      # Verify performance metrics
      assert fsm4.performance[:transition_count] == 4
      assert fsm4.performance[:last_transition_at] != nil
      assert fsm4.performance[:avg_transition_time] > 0
    end

    test "tenant isolation" do
      # Create FSMs for different tenants
      fsm1 = SmartDoor.new(%{}, id: "tenant1_fsm", tenant_id: "tenant1")
      fsm2 = SmartDoor.new(%{}, id: "tenant2_fsm", tenant_id: "tenant2")

      # Verify they have different IDs and tenant IDs
      assert fsm1.id == "tenant1_fsm"
      assert fsm1.tenant_id == "tenant1"
      assert fsm2.id == "tenant2_fsm"
      assert fsm2.tenant_id == "tenant2"

      # Verify they can operate independently
      {:ok, opening_fsm1} = SmartDoor.navigate(fsm1, :open_command, %{user_id: "user1"})
      {:ok, opening_fsm2} = SmartDoor.navigate(fsm2, :open_command, %{user_id: "user2"})

      assert opening_fsm1.current_state == :opening
      assert opening_fsm2.current_state == :opening
      assert opening_fsm1.data[:user_id] == "user1"
      assert opening_fsm2.data[:user_id] == "user2"
    end
  end
end
