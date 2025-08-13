defmodule FSM.SecuritySystem do
  @moduledoc """
  Security system FSM that composes the `FSM.Components.Security` component and
  adds a minimal top-level flow around arming/disarming and alarm handling.

  Example events:
  - :arm -> transitions to :locked (armed)
  - :disarm -> transitions to :unlocked
  - :intrusion_detected -> transitions to :alarm
  - :alarm_reset -> transitions to :locked
  """

  use FSM.Navigator
  require Logger

  # Reuse the shared security states/transitions
  use_component FSM.Components.Security

  # Provide an explicit initial state for this wrapper FSM
  initial_state :unlocked

  # Optional lifecycle: add simple logging
  on_enter :alarm do
    Logger.warning("SecuritySystem alarm state entered")
    fsm
  end

  # Helper to arm the system (maps to component's :lock transition)
  def arm(fsm, meta \\ %{}) do
    case navigate(fsm, :lock, meta) do
      {:ok, new_fsm} -> new_fsm
      _ -> fsm
    end
  end

  # Helper to disarm the system (maps to component's :correct_key transition)
  def disarm(fsm, meta \\ %{}) do
    case navigate(fsm, :correct_key, meta) do
      {:ok, new_fsm} -> new_fsm
      _ -> fsm
    end
  end
end
