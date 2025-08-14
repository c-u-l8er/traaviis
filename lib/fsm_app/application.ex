defmodule FSMApp.Application do
  @moduledoc """
  The FSMApp Application Supervisor.

  This module supervises all the core services including:
  - FSM Registry and Manager
  - WebSocket Channel Manager
  - MCP Server/Client
  - Database connections
  - Background job processing
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      FSMAppWeb.Telemetry,

      # Database repository removed (filesystem-backed persistence in use)

      # Start the PubSub system
      {Phoenix.PubSub, name: FSMApp.PubSub},

      # Start the Endpoint (http/https)
      FSMAppWeb.Endpoint,

      # Task supervisor for async/supervised jobs (effects, broadcasts, callbacks)
      {Task.Supervisor, name: FSM.TaskSupervisor},

      # Start the FSM Registry
      FSM.Registry,

      # Start the FSM Manager
      FSM.Manager,

      # Start the MCP Server
      # FSMApp.MCP.Server,

      # Start the MCP Client Manager
      # FSMApp.MCP.ClientManager,

      # Start the WebSocket Channel Manager
      FSMAppWeb.ChannelManager,

      # Start the Tenant Manager
      FSMApp.TenantManager,

      # Start the Background Job Processor
      # {Oban, Application.get_env(:fsm_app, Oban, [])}
    ]

    opts = [strategy: :one_for_one, name: FSMApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FSMAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
