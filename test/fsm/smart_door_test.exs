defmodule FSM.SmartDoorTest do
  use ExUnit.Case
  alias FSM.SmartDoor

  describe "SmartDoor FSM" do
    test "initializes in closed state" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")
      assert fsm.current_state == :closed
    end

    test "transitions from closed to opening on open_command" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")
      {:ok, new_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      assert new_fsm.current_state == :opening
    end

    test "transitions from opening to open on fully_open" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # First open the door
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      # Then complete opening
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})
      assert open_fsm.current_state == :open
    end

    test "transitions from open to closing on close_command" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open the door first
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Then close it
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :close_command, %{user_id: "user123"})
      assert closing_fsm.current_state == :closing
    end

    test "transitions to emergency_lock from any state" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Test from closed state
      {:ok, emergency_fsm} = SmartDoor.navigate(fsm, :emergency_lock, %{reason: :security_breach})
      assert emergency_fsm.current_state == :emergency_lock
    end

    test "handles obstruction during opening" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Start opening
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})

      # Detect obstruction
      {:ok, closed_fsm} = SmartDoor.navigate(opening_fsm, :obstruction, %{sensor: "door_sensor_1"})
      assert closed_fsm.current_state == :closed
    end

    test "handles obstruction during closing" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open the door first
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Start closing
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :close_command, %{user_id: "user123"})

      # Detect obstruction
      {:ok, opening_fsm} = SmartDoor.navigate(closing_fsm, :obstruction, %{sensor: "door_sensor_1"})
      assert opening_fsm.current_state == :opening
    end

    test "auto-close functionality" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open the door
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Simulate auto-close timer
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :auto_close, %{timer: "auto_close_timer"})
      assert closing_fsm.current_state == :closing
    end

    test "emergency lock can be cleared" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Trigger emergency lock
      {:ok, emergency_fsm} = SmartDoor.navigate(fsm, :emergency_lock, %{reason: :security_breach})

      # Clear emergency
      {:ok, closed_fsm} = SmartDoor.navigate(emergency_fsm, :emergency_clear, %{authorized_by: "security_officer"})
      assert closed_fsm.current_state == :closed
    end

    test "handles invalid transitions gracefully" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Try to close from closed state (invalid)
      {:error, :invalid_transition} = SmartDoor.navigate(fsm, :close_command)

      # Try to fully open from closed state (invalid)
      {:error, :invalid_transition} = SmartDoor.navigate(fsm, :fully_open)

      # Try to fully close from closed state (invalid)
      {:error, :invalid_transition} = SmartDoor.navigate(fsm, :fully_closed)
    end

    test "executes lifecycle hooks correctly" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open the door (should trigger on_enter :opening)
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})

      # Complete opening (should trigger on_enter :open)
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Start closing (should trigger on_enter :closing)
      {:ok, closing_fsm} = SmartDoor.navigate(open_fsm, :close_command, %{user_id: "user123"})

      # Complete closing (should trigger on_enter :closed)
      {:ok, closed_fsm} = SmartDoor.navigate(closing_fsm, :fully_closed, %{})
      assert closed_fsm.current_state == :closed
    end
  end

  describe "SmartDoor Component Integration" do
    test "Timer component integration" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open the door to trigger timer
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})

      # Check if timer data is stored
      assert Map.has_key?(opening_fsm.data, :timers)
      assert Map.has_key?(opening_fsm.data[:timers], :auto_close)
    end

    test "Security component integration" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Trigger emergency lock to test security integration
      {:ok, emergency_fsm} = SmartDoor.navigate(fsm, :emergency_lock, %{reason: :security_breach})
      assert emergency_fsm.current_state == :emergency_lock
    end
  end

  describe "SmartDoor External Events" do
    test "handles external security system events" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Simulate security system alarm
      updated_fsm = SmartDoor.handle_external_event(fsm, :SecuritySystem, :state_changed, %{to: :alarm})
      assert updated_fsm.current_state == :emergency_lock
    end

    test "ignores unrelated external events" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")
      initial_state = fsm.current_state

      # Send unrelated event
      updated_fsm = SmartDoor.handle_external_event(fsm, :OtherSystem, :event, %{data: "test"})
      assert updated_fsm.current_state == initial_state
    end
  end

  describe "SmartDoor Data Management" do
    test "stores and retrieves timer data" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open door to start timer
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123"})

      # Check timer data
      assert Map.has_key?(opening_fsm.data, :timers)
      assert Map.has_key?(opening_fsm.data[:timers], :auto_close)

      # Complete opening to reset timer
      {:ok, open_fsm} = SmartDoor.navigate(opening_fsm, :fully_open, %{})

      # Timer should be removed
      refute Map.has_key?(open_fsm.data[:timers], :auto_close)
    end

    test "handles user data in events" do
      fsm = SmartDoor.new(%{}, id: "test", tenant_id: "test_tenant")

      # Open door with user data
      {:ok, opening_fsm} = SmartDoor.navigate(fsm, :open_command, %{user_id: "user123", timestamp: "2024-01-01"})

      # Check if user data is preserved
      assert opening_fsm.data[:user_id] == "user123"
      assert opening_fsm.data[:timestamp] == "2024-01-01"
    end
  end
end
