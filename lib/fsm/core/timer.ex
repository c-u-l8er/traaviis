defmodule FSM.Timer do
  @moduledoc """
  A simple timer FSM that wraps the `FSM.Components.Timer` component so it can be
  created directly via the factory/UI.

  Events:
  - :start -> :running
  - :stop -> :idle
  - :pause -> :paused
  - :resume -> :running
  - :timeout -> :expired
  - :reset -> :idle
  """

  use FSM.Navigator

  # Reuse the generic timer states/transitions
  use_component FSM.Components.Timer

  # Ensure a well-defined initial state for the wrapper FSM
  initial_state :idle

  # Convenience helpers for external users
  def start_named_timer(fsm, timer_name, duration_ms, payload \\ %{}) do
    timer_data = FSM.Components.Timer.start_timer(timer_name, duration_ms, payload)
    new_data = Map.update(fsm.data, :timers, %{timer_name => timer_data}, fn timers ->
      Map.put(timers, timer_name, timer_data)
    end)
    %{fsm | data: new_data}
  end

  def stop_named_timer(fsm, timer_name) do
    case fsm.data |> Map.get(:timers, %{}) |> Map.get(timer_name) do
      %{timer_ref: timer_ref} when is_reference(timer_ref) ->
        _ = FSM.Components.Timer.stop_timer(timer_ref)
        update_in(fsm.data[:timers], &Map.delete(&1 || %{}, timer_name))
        |> then(fn new_timers -> %{fsm | data: Map.put(fsm.data, :timers, new_timers)} end)
      _ -> fsm
    end
  end
end
