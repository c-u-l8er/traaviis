defmodule FSMApp.Jobs.DailyCleanup do
  @moduledoc """
  Daily cleanup job for FSM data and logs.
  """
  use Oban.Worker, queue: :default
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # This is a placeholder job - in a real application you would:
    # - Clean up old FSM logs
    # - Archive completed FSMs
    # - Clean up temporary data
    # - Send daily reports

    Logger.info("Daily cleanup job completed")
    :ok
  end
end
