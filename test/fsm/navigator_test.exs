defmodule FSM.NavigatorTest do
  use ExUnit.Case

  # Test FSM module
  defmodule TestFSM do
    use FSM.Navigator
    require FSM.Navigator

    state :idle do
      navigate_to :active, when: :start
    end

    state :active do
      navigate_to :idle, when: :stop
      navigate_to :paused, when: :pause
    end

    state :paused do
      navigate_to :active, when: :resume
      navigate_to :idle, when: :stop
    end

    initial_state :idle

    on_enter :active do
      %{fsm | data: Map.put(fsm.data, :entered_at, DateTime.utc_now())}
    end

    FSM.Navigator.on_exit :active do
      %{fsm | data: Map.put(fsm.data, :exited_at, DateTime.utc_now())}
    end

    validate :check_permission

    def check_permission(fsm, _event, _data) do
      if fsm.data[:permission] == :granted do
        {:ok, fsm}
      else
        {:error, :permission_denied}
      end
    end
  end

  describe "FSM.Navigator basic functionality" do
    test "creates FSM with correct initial state" do
      fsm = TestFSM.new(%{permission: :granted})
      assert fsm.current_state == :idle
      assert fsm.data[:permission] == :granted
    end

    test "transitions between states correctly" do
      fsm = TestFSM.new(%{permission: :granted})

      # Start the FSM
      {:ok, new_fsm} = TestFSM.navigate(fsm, :start, %{user: "test"})
      assert new_fsm.current_state == :active

      # Pause the FSM
      {:ok, paused_fsm} = TestFSM.navigate(new_fsm, :pause)
      assert paused_fsm.current_state == :paused

      # Resume the FSM
      {:ok, resumed_fsm} = TestFSM.navigate(paused_fsm, :resume)
      assert resumed_fsm.current_state == :active

      # Stop the FSM
      {:ok, stopped_fsm} = TestFSM.navigate(resumed_fsm, :stop)
      assert stopped_fsm.current_state == :idle
    end

    test "executes lifecycle hooks correctly" do
      fsm = TestFSM.new(%{permission: :granted})

      # Start the FSM (should trigger on_enter :active)
      {:ok, new_fsm} = TestFSM.navigate(fsm, :start)
      assert Map.has_key?(new_fsm.data, :entered_at)

      # Stop the FSM (should trigger on_exit :active)
      {:ok, stopped_fsm} = TestFSM.navigate(new_fsm, :stop)
      assert Map.has_key?(stopped_fsm.data, :exited_at)
    end

    test "validates transitions correctly" do
      # FSM without permission should fail validation
      fsm = TestFSM.new(%{permission: :denied})
      {:error, :validation_error} = TestFSM.navigate(fsm, :start)

      # FSM with permission should succeed
      fsm_with_permission = TestFSM.new(%{permission: :granted})
      {:ok, _} = TestFSM.navigate(fsm_with_permission, :start)
    end

    test "handles invalid transitions gracefully" do
      fsm = TestFSM.new(%{permission: :granted})

      # Try to transition from idle to paused (invalid)
      {:error, :invalid_transition} = TestFSM.navigate(fsm, :pause)
    end

    test "updates FSM data during transitions" do
      fsm = TestFSM.new(%{permission: :granted, counter: 0})

      # Start with additional data
      {:ok, new_fsm} = TestFSM.navigate(fsm, :start, %{counter: 1})
      assert new_fsm.data[:counter] == 1
    end
  end

  describe "FSM.Navigator advanced features" do
    test "maintains FSM metadata" do
      fsm = TestFSM.new(%{permission: :granted}, id: "test123", tenant_id: "tenant1")

      assert fsm.id == "test123"
      assert fsm.tenant_id == "tenant1"
      assert fsm.metadata[:created_at] != nil
      assert fsm.metadata[:version] == 1
    end

    test "tracks performance metrics" do
      fsm = TestFSM.new(%{permission: :granted})

      # Perform a transition
      {:ok, new_fsm} = TestFSM.navigate(fsm, :start)

      assert new_fsm.performance[:transition_count] == 1
      assert new_fsm.performance[:last_transition_at] != nil
    end

    test "handles external events" do
      fsm = TestFSM.new(%{permission: :granted})

      # Test default external event handler
      updated_fsm = TestFSM.handle_external_event(fsm, :source, :event, %{data: "test"})
      assert updated_fsm == fsm
    end
  end
end
