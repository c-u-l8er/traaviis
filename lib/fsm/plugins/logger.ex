defmodule FSM.Plugins.Logger do
  use FSM.Plugin
  require Logger

  def init(fsm, opts) do
    level = Keyword.get(opts, :level, :info)
    put_in(fsm.data[:logger_config], %{level: level})
  end

  def before_transition(fsm, {old_state, event, event_data}, _opts) do
    level = get_log_level(fsm)

    Logger.log(level, "[FSM] Transitioning from #{old_state} on event #{event}",
      fsm_id: fsm.id,
      event: event,
      old_state: old_state,
      event_data: event_data
    )

    fsm
  end

  def after_transition(fsm, {old_state, new_state, event, event_data}, _opts) do
    level = get_log_level(fsm)

    Logger.log(level, "[FSM] Transitioned from #{old_state} to #{new_state} via #{event}",
      fsm_id: fsm.id,
      event: event,
      old_state: old_state,
      new_state: new_state,
      event_data: event_data
    )

    fsm
  end

  # Helper function to get log level from FSM data
  defp get_log_level(fsm) do
    data = Map.get(fsm, :data, %{})
    logger_config = Map.get(data, :logger_config)
    case logger_config do
      %{} = cfg -> Map.get(cfg, :level, :info)
      _ -> :info
    end
  end
end
