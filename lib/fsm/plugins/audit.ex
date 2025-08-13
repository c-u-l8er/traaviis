defmodule FSM.Plugins.Audit do
  use FSM.Plugin

  def init(fsm, _opts) do
    put_in(fsm.data[:audit_log], [])
  end

  def after_transition(fsm, {old_state, new_state, event, event_data}, _opts) do
    audit_entry = %{
      timestamp: :os.system_time(:millisecond),
      from: old_state,
      to: new_state,
      event: event,
      data: event_data
    }

    update_in(fsm.data[:audit_log], fn log -> [audit_entry | log] end)
  end
end
