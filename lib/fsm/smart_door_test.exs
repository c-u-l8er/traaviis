defmodule FSM.SmartDoorTest do
  use ExUnit.Case
  alias FSM.SmartDoor
  alias FSM.Manager

  setup do
    # Create a new SmartDoor FSM for testing
    {:ok, fsm_id} = Manager.create_fsm(SmartDoor, %{}, "test_tenant")
    %{fsm_id: fsm_id}
  end

  describe "SmartDoor FSM" do
    test "initializes in closed state", %{fsm_id: fsm_id} do
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :closed
    end

    test "transitions from closed to opening on open_command", %{fsm_id: fsm_id} do
      {:ok, _} = Manager.send_event(fsm_id, :open_command, %{user_id: "user123"})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :opening
    end

    test "transitions from opening to open on fully_open", %{fsm_id: fsm_id} do
      # First open the door
      {:ok, _} = Manager.send_event(fsm_id, :open_command, %{user_id: "user123"})
      # Then complete opening
      {:ok, _} = Manager.send_event(fsm_id, :fully_open, %{})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :open
    end

    test "transitions from open to closing on close_command", %{fsm_id: fsm_id} do
      # Open the door first
      {:ok, _} = Manager.send_event(fsm_id, :open_command, %{user_id: "user123"})
      {:ok, _} = Manager.send_event(fsm_id, :fully_open, %{})
      # Then close it
      {:ok, _} = Manager.send_event(fsm_id, :close_command, %{user_id: "user123"})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :closing
    end

    test "transitions to emergency_lock from any state", %{fsm_id: fsm_id} do
      # Test from closed state
      {:ok, _} = Manager.send_event(fsm_id, :emergency_lock, %{reason: :security_breach})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :emergency_lock
    end

    test "handles obstruction during opening", %{fsm_id: fsm_id} do
      # Start opening
      {:ok, _} = Manager.send_event(fsm_id, :open_command, %{user_id: "user123"})
      # Detect obstruction
      {:ok, _} = Manager.send_event(fsm_id, :obstruction, %{sensor: "door_sensor_1"})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :closed
    end

    test "handles obstruction during closing", %{fsm_id: fsm_id} do
      # Open the door first
      {:ok, _} = Manager.send_event(fsm_id, :open_command, %{user_id: "user123"})
      {:ok, _} = Manager.send_event(fsm_id, :fully_open, %{})
      # Start closing
      {:ok, _} = Manager.send_event(fsm_id, :close_command, %{user_id: "user123"})
      # Detect obstruction
      {:ok, _} = Manager.send_event(fsm_id, :obstruction, %{sensor: "door_sensor_1"})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :opening
    end

    test "auto-close functionality", %{fsm_id: fsm_id} do
      # Open the door
      {:ok, _} = Manager.send_event(fsm_id, :open_command, %{user_id: "user123"})
      {:ok, _} = Manager.send_event(fsm_id, :fully_open, %{})
      # Simulate auto-close timer
      {:ok, _} = Manager.send_event(fsm_id, :auto_close, %{timer: "auto_close_timer"})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :closing
    end

    test "emergency lock can be cleared", %{fsm_id: fsm_id} do
      # Trigger emergency lock
      {:ok, _} = Manager.send_event(fsm_id, :emergency_lock, %{reason: :security_breach})
      # Clear emergency
      {:ok, _} = Manager.send_event(fsm_id, :emergency_clear, %{authorized_by: "security_officer"})
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert state.current_state == :closed
    end
  end

  describe "Component Integration" do
    test "Timer component integration", %{fsm_id: fsm_id} do
      # The timer component should be available
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert Map.has_key?(state.components, FSM.Components.Timer)
    end

    test "Security component integration", %{fsm_id: fsm_id} do
      # The security component should be available
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert Map.has_key?(state.components, FSM.Components.Security)
    end
  end

  describe "Plugin Integration" do
    test "Logger plugin is active", %{fsm_id: fsm_id} do
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert Map.has_key?(state.plugins, FSM.Plugins.Logger)
    end

    test "Audit plugin is active", %{fsm_id: fsm_id} do
      {:ok, state} = Manager.get_fsm_state(fsm_id)
      assert Map.has_key?(state.plugins, FSM.Plugins.Audit)
    end
  end
end
