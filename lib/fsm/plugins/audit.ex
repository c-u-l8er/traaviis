defmodule FSM.Plugins.Audit do
  use FSM.Plugin

  def init(fsm, _opts) do
    fsm
  end

  def after_transition(fsm, {old_state, new_state, event, event_data}, _opts) do
    _ = {old_state, new_state, event, event_data}
    fsm
  end
end
