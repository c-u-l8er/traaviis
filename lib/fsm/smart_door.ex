defmodule FSM.SmartDoor do
  use FSM.Navigator
  require Logger

  # Use components for modularity
  use_component FSM.Components.Timer
  use_component FSM.Components.Security

  # Use plugins for cross-cutting concerns
  use_plugin FSM.Plugins.Logger, level: :debug
  use_plugin FSM.Plugins.Audit

  # Helper functions for component integration - defined first
  def start_auto_close_timer(fsm) do
    # Use the Timer component to start auto-close timer with targeting info
    timer_data = FSM.Components.Timer.start_timer(:auto_close, 30000, %{fsm_id: fsm.id, tenant_id: fsm.tenant_id}) # 30 seconds
    # Store timer data in FSM data
    new_data = Map.update(fsm.data, :timers, %{auto_close: timer_data}, fn timers ->
      Map.put(timers, :auto_close, timer_data)
    end)
    %{fsm | data: new_data}
  end

  def reset_auto_close_timer(fsm) do
    # Reset the auto-close timer
    case fsm.data |> Map.get(:timers, %{}) |> Map.get(:auto_close) do
      %{timer_ref: timer_ref} when is_reference(timer_ref) ->
        FSM.Components.Timer.stop_timer(timer_ref)
        # Remove timer from FSM data
        new_data = update_in(fsm.data, [:timers], &Map.delete(&1 || %{}, :auto_close))
        %{fsm | data: new_data}
      _ ->
        fsm
    end
  end

  def start_safety_timer(fsm) do
    # Start safety timer for closing operation
    # After a short delay, auto-complete closing by emitting :fully_closed
    timer_data = FSM.Components.Timer.start_timer(:fully_closed, 5000, %{fsm_id: fsm.id, tenant_id: fsm.tenant_id}) # 5 seconds
    new_data = Map.update(fsm.data, :timers, %{safety_check: timer_data}, fn timers ->
      Map.put(timers, :safety_check, timer_data)
    end)
    %{fsm | data: new_data}
  end

  def trigger_security_alarm(fsm) do
    # Use the Security component to trigger alarm
    FSM.Components.Security.trigger_alarm_system(fsm)
    FSM.Components.Security.notify_security_personnel(fsm)
    fsm
  end

  # Door-specific states
  state :closed do
    navigate_to :opening, when: :open_command
    navigate_to :emergency_lock, when: :emergency_lock
  end

  state :opening do
    navigate_to :open, when: :fully_open
    navigate_to :closed, when: :obstruction
    navigate_to :emergency_lock, when: :emergency_lock
  end

  state :open do
    navigate_to :closing, when: :close_command
    navigate_to :closing, when: :auto_close
    navigate_to :emergency_lock, when: :emergency_lock
  end

  state :closing do
    navigate_to :closed, when: :fully_closed
    navigate_to :opening, when: :obstruction
    navigate_to :emergency_lock, when: :emergency_lock
  end

  # Emergency state for security situations
  state :emergency_lock do
    navigate_to :closed, when: :emergency_clear
  end

  initial_state :closed

  # Lifecycle hooks for better state management - defined after functions
  on_enter :opening do
    fsm
  end

  on_enter :open do
    # Start or restart auto-close timer when door is fully open
    __MODULE__.start_auto_close_timer(fsm)
  end

  on_enter :closing do
    # Cancel auto-close timer when starting to close, then start safety timer
    fsm
    |> __MODULE__.reset_auto_close_timer()
    |> __MODULE__.start_safety_timer()
  end

  on_enter :emergency_lock do
    # Trigger security alarm
    __MODULE__.trigger_security_alarm(fsm)
  end

  # Handle events from other FSMs
  def handle_external_event(fsm, :SecuritySystem, :state_changed, %{to: :alarm}) do
    # When security system goes to alarm, lock the door
    case navigate(fsm, :emergency_lock, %{reason: :security_alarm}) do
      {:ok, new_fsm} -> new_fsm
      {:error, _} -> fsm
    end
  end

  def handle_external_event(fsm, _source, _event, _data), do: fsm
end
