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
    # After a short delay, auto-complete closing by emitting :fully_closed (only used for auto-close)
    # Route this timer to the Manager process so it survives UI process restarts
    payload = %{fsm_id: fsm.id, tenant_id: fsm.tenant_id}
    timer_ref = Process.send_after(FSM.Manager, {:timer_expired, :fully_closed, payload}, 5000)
    timer_data = %{
      timer_name: :fully_closed,
      duration: 5000,
      start_time: System.monotonic_time(:millisecond),
      remaining_time: 5000,
      timer_ref: timer_ref,
      callback: nil,
      payload: payload
    }
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
  validate :mark_auto_close

  # Lifecycle hooks for better state management - defined after functions
  on_enter :opening do
    fsm
  end

  on_enter :open do
    # Start or restart auto-close timer when door is fully open
    __MODULE__.start_auto_close_timer(fsm)
  end

  on_enter :closing do
    # Cancel auto-close timer when starting to close
    fsm = __MODULE__.reset_auto_close_timer(fsm)

    # Only start the safety timer (which triggers :fully_closed) when we entered
    # :closing via an auto-close event. Detect via marker set in event_data.
    auto_close_triggered? = fsm.data |> Map.get(:auto_close, false)

    fsm = if auto_close_triggered? do
      __MODULE__.start_safety_timer(fsm)
    else
      fsm
    end

    # Clear the marker to avoid leaking into future transitions
    %{fsm | data: Map.delete(fsm.data, :auto_close)}
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

  # Validation: mark auto_close-triggered transitions so on_enter :closing can auto-complete
  def mark_auto_close(fsm, event, _event_data) do
    case {fsm.current_state, event} do
      {:open, :auto_close} ->
        {:ok, %{fsm | data: Map.put(fsm.data, :auto_close, true)}}
      _ ->
        {:ok, fsm}
    end
  end
end
