defmodule FSMAppWeb.Telemetry do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Add reporters as children of your supervision tree.
      # {TelemetryMetricsPrometheus, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # This function is used by TelemetryPoller for periodic measurements
  # Uncomment and customize as needed for your application
  # defp periodic_measurements do
  #   [
  #     # A module, function and arguments to be invoked periodically.
  #     # {FSMAppWeb, :count_users, []},
  #     # {FSMAppWeb, :count_orders, []}
  #   ]
  # end
end
