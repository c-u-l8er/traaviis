defmodule FSM.Components.Security do
  use FSM.Navigator
  require Logger

  # Helper functions for lifecycle hooks - defined first
  def log_security_event(fsm, event) do
    # Implementation for logging security events
    Logger.info("Security event: #{event}")
    fsm
  end

  def activate_security_monitoring(fsm) do
    # Implementation for activating security monitoring
    fsm
  end

  def trigger_alarm_system(fsm) do
    # Implementation for triggering alarm system
    fsm
  end

  def notify_security_personnel(fsm) do
    # Implementation for notifying security personnel
    fsm
  end

  def deactivate_alarm_system(fsm) do
    # Implementation for deactivating alarm system
    fsm
  end

  def check_security_credentials(fsm, _event, _data) do
    # Implementation for checking security credentials
    {:ok, fsm}
  end

  def check_lockout_status(fsm, _event, _data) do
    # Implementation for checking lockout status
    {:ok, fsm}
  end

  # States and transitions
  state :unlocked do
    navigate_to :locked, when: :lock
    navigate_to :alarm, when: :intrusion_detected
  end

  state :locked do
    navigate_to :unlocked, when: :correct_key
    navigate_to :alarm, when: :forced_entry
  end

  state :alarm do
    navigate_to :locked, when: :alarm_reset
  end

  initial_state :unlocked

  # Security validation rules
  validate :check_security_credentials
  validate :check_lockout_status



  # Functions required by the Navigator for component integration
  @doc """
  Get all states defined by this component.
  """
  def states do
    [:unlocked, :locked, :alarm]
  end

  @doc """
  Get all transitions defined by this component.
  """
  def transitions do
    [
      {:unlocked, :lock, :locked, []},
      {:unlocked, :intrusion_detected, :alarm, []},
      {:locked, :correct_key, :unlocked, []},
      {:locked, :forced_entry, :alarm, []},
      {:alarm, :alarm_reset, :locked, []}
    ]
  end

  # Utility functions that can be called from other FSMs
  @doc """
  Get current security level.
  """
  def get_security_level(security_data)
  def get_security_level(%{security_level: level}), do: level
  def get_security_level(_), do: :normal

  @doc """
  Check if access is allowed.
  """
  def access_allowed?(security_data, required_level) do
    current_level = get_security_level(security_data)
    security_level_value(current_level) >= security_level_value(required_level)
  end

  # Helper function to convert security levels to numeric values
  defp security_level_value(:low), do: 1
  defp security_level_value(:normal), do: 2
  defp security_level_value(:high), do: 3
  defp security_level_value(:critical), do: 4
  defp security_level_value(_), do: 0

  # Lifecycle hooks for security management - defined after all functions
  on_enter :locked do
    __MODULE__.log_security_event(fsm, :door_locked)
    __MODULE__.activate_security_monitoring(fsm)
  end

  on_enter :alarm do
    __MODULE__.trigger_alarm_system(fsm)
    __MODULE__.notify_security_personnel(fsm)
  end

  on_exit :alarm do
    __MODULE__.deactivate_alarm_system(fsm)
  end
end
