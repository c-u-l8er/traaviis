defmodule FSM.Components.Timer do
  use FSM.Navigator

  # Helper functions for lifecycle hooks - defined first
  def start_timer_impl(fsm) do
    # Implementation for starting the actual timer
    fsm
  end

  def cancel_timer_impl(fsm) do
    # Implementation for canceling the timer
    fsm
  end

  def pause_timer_impl(fsm) do
    # Implementation for pausing the timer
    fsm
  end

  def execute_callback(fsm) do
    # Implementation for executing timer callback
    fsm
  end

  # States and transitions
  state :idle do
    navigate_to :running, when: :start
  end

  state :running do
    navigate_to :idle, when: :stop
    navigate_to :paused, when: :pause
    navigate_to :expired, when: :timeout
  end

  state :paused do
    navigate_to :running, when: :resume
    navigate_to :idle, when: :stop
  end

  state :expired do
    navigate_to :idle, when: :reset
  end

  initial_state :idle


  # Functions required by the Navigator for component integration
  @doc """
  Get all states defined by this component.
  """
  def states do
    [:idle, :running, :paused, :expired]
  end

  @doc """
  Get all transitions defined by this component.
  """
  def transitions do
    [
      {:idle, :start, :running, []},
      {:running, :stop, :idle, []},
      {:running, :pause, :paused, []},
      {:running, :timeout, :expired, []},
      {:paused, :resume, :running, []},
      {:paused, :stop, :idle, []},
      {:expired, :reset, :idle, []}
    ]
  end

  # Utility functions that can be called from other FSMs
  @doc """
  Start a timer with the given name and duration.
  """
  def start_timer(timer_name, duration) do
    # Implementation for starting the actual timer
    # This would typically use Process.send_after or :timer.send_after
    timer_ref = Process.send_after(self(), {:timer_expired, timer_name}, duration)
    %{
      timer_name: timer_name,
      duration: duration,
      start_time: System.monotonic_time(:millisecond),
      remaining_time: duration,
      timer_ref: timer_ref,
      callback: nil
    }
  end

  @doc """
  Stop a running timer.
  """
  def stop_timer(timer_ref) when is_reference(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  def stop_timer(_), do: :ok

  @doc """
  Reset a timer to its original duration.
  """
  def reset_timer(_timer_name) do
    # Implementation for resetting the timer
    :ok
  end

  @doc """
  Check if a timer has expired.
  """
  def timer_expired?(timer_data) do
    case timer_data do
      %{start_time: start_time, duration: duration} when is_integer(start_time) and is_integer(duration) ->
        current_time = System.monotonic_time(:millisecond)
        (current_time - start_time) >= duration
      _ ->
        false
    end
  end

  # Lifecycle hooks for timer management - defined after all functions
  on_enter :running do
    __MODULE__.start_timer_impl(fsm)
  end

  on_exit :running do
    __MODULE__.cancel_timer_impl(fsm)
  end

  on_enter :paused do
    __MODULE__.pause_timer_impl(fsm)
  end

  on_enter :expired do
    __MODULE__.execute_callback(fsm)
  end
end
