defmodule FSM.Navigator do
  @moduledoc """
  A finite state machine with navigational syntax using Elixir macros.
  Supports modularity, componentization, pluggability, and inter-FSM communication.
  """

  defmacro __using__(_opts) do
    quote do
      import FSM.Navigator
      Module.register_attribute(__MODULE__, :states, accumulate: true)
      Module.register_attribute(__MODULE__, :transitions, accumulate: true)
      Module.register_attribute(__MODULE__, :initial_state, [])
      Module.register_attribute(__MODULE__, :plugins, accumulate: true)
      Module.register_attribute(__MODULE__, :components, accumulate: true)
      Module.register_attribute(__MODULE__, :subscriptions, accumulate: true)

      @before_compile FSM.Navigator
    end
  end

  # Core DSL macros
  defmacro state(name, do: block) do
    quote do
      @current_state unquote(name)
      @states unquote(name)
      unquote(block)
    end
  end

  defmacro navigate_to(target_state, when: condition) do
    quote do
      @transitions {@current_state, unquote(condition), unquote(target_state)}
    end
  end

  defmacro initial_state(state) do
    quote do
      @initial_state unquote(state)
    end
  end

  # Modularity: Import states and transitions from other FSMs
  defmacro use_component(component_module, opts \\ []) do
    quote do
      @components {unquote(component_module), unquote(opts)}
    end
  end

  # Pluggability: Add behavior plugins
  defmacro use_plugin(plugin_module, opts \\ []) do
    quote do
      @plugins {unquote(plugin_module), unquote(opts)}
    end
  end

  # Inter-FSM communication: Subscribe to events from other FSMs
  defmacro subscribe_to(fsm_module, event, action) do
    quote do
      @subscriptions {unquote(fsm_module), unquote(event), unquote(action)}
    end
  end

  defmacro __before_compile__(env) do
    states = Module.get_attribute(env.module, :states) |> Enum.reverse()
    transitions = Module.get_attribute(env.module, :transitions) |> Enum.reverse()
    initial_state = Module.get_attribute(env.module, :initial_state)
    plugins = Module.get_attribute(env.module, :plugins) |> Enum.reverse()
    components = Module.get_attribute(env.module, :components) |> Enum.reverse()
    subscriptions = Module.get_attribute(env.module, :subscriptions) |> Enum.reverse()

    # Merge component states and transitions
    {component_states, component_transitions} = merge_components(components)
    all_states = Enum.uniq(states ++ component_states)
    all_transitions = transitions ++ component_transitions

    quote do
      defstruct [
        current_state: unquote(initial_state),
        data: %{},
        id: nil,
        subscribers: [],
        plugins: unquote(Macro.escape(plugins))
      ]

      def new(initial_data \\ %{}, opts \\ []) do
        id = Keyword.get(opts, :id, make_ref())
        fsm = %__MODULE__{
          current_state: unquote(initial_state),
          data: initial_data,
          id: id
        }

        # Register with FSM registry for inter-FSM communication
        FSM.Registry.register(id, __MODULE__, fsm)

        # Initialize plugins
        fsm = initialize_plugins(fsm)

        fsm
      end

      def navigate(fsm, event, event_data \\ %{}) do
        old_state = fsm.current_state

        # Apply pre-transition plugins
        fsm = apply_plugins(fsm, :before_transition, {old_state, event, event_data})

        # Perform the actual transition
        new_fsm = do_navigate(fsm, event, event_data)

        # Apply post-transition plugins if state changed
        new_fsm = if new_fsm.current_state != old_state do
          new_fsm = apply_plugins(new_fsm, :after_transition, {old_state, new_fsm.current_state, event, event_data})

          # Publish state change event to subscribers
          publish_event(new_fsm, :state_changed, %{
            from: old_state,
            to: new_fsm.current_state,
            event: event,
            data: event_data
          })

          new_fsm
        else
          new_fsm
        end

        new_fsm
      end

      # Generated navigation functions
      unquote(generate_navigate_clauses(all_transitions))

      def do_navigate(fsm, _event, _event_data), do: fsm

      # Component interface
      def states, do: unquote(all_states)
      def transitions, do: unquote(Macro.escape(all_transitions))
      def current_state(%__MODULE__{current_state: state}), do: state

      def can_navigate?(fsm, event) do
        case do_navigate(fsm, event) do
          ^fsm -> false
          _new_fsm -> true
        end
      end

      def possible_destinations(%__MODULE__{current_state: current}) do
        unquote(Macro.escape(all_transitions))
        |> Enum.filter(fn {from, _event, _to} -> from == current end)
        |> Enum.map(fn {_from, event, to} -> {event, to} end)
      end

      # Plugin management
      defp initialize_plugins(fsm) do
        Enum.reduce(fsm.plugins, fsm, fn {plugin_module, opts}, acc_fsm ->
          plugin_module.init(acc_fsm, opts)
        end)
      end

      defp apply_plugins(fsm, hook, data) do
        Enum.reduce(fsm.plugins, fsm, fn {plugin_module, opts}, acc_fsm ->
          if function_exported?(plugin_module, hook, 3) do
            plugin_module.apply(hook, [acc_fsm, data, opts]) || acc_fsm
          else
            acc_fsm
          end
        end)
      end

      # Inter-FSM communication
      def subscribe(fsm, subscriber_id) do
        %{fsm | subscribers: [subscriber_id | fsm.subscribers]}
      end

      defp publish_event(fsm, event_type, event_data) do
        Enum.each(fsm.subscribers, fn subscriber_id ->
          case FSM.Registry.get(subscriber_id) do
            {:ok, {subscriber_module, subscriber_fsm}} ->
              spawn(fn ->
                subscriber_module.handle_external_event(subscriber_fsm, __MODULE__, event_type, event_data)
              end)
            _ -> :ok
          end
        end)

        fsm
      end

      # Default handler for external events
      def handle_external_event(fsm, _source_module, _event_type, _event_data) do
        fsm  # Override in implementing modules
      end

      def visualize do
        states = unquote(all_states)
        transitions = unquote(Macro.escape(all_transitions))

        IO.puts("=== #{__MODULE__} FSM ===")
        IO.puts("States: #{inspect(states)}")
        IO.puts("Initial State: #{unquote(initial_state)}")
        IO.puts("Components: #{inspect(unquote(Macro.escape(components)))}")
        IO.puts("Plugins: #{inspect(unquote(Macro.escape(plugins)))}")
        IO.puts("Transitions:")

        Enum.each(transitions, fn {from, event, to} ->
          IO.puts("  #{from} --#{event}--> #{to}")
        end)
      end
    end
  end

  defp generate_navigate_clauses(transitions) do
    transitions
    |> Enum.group_by(fn {from, event, _to} -> {from, event} end)
    |> Enum.map(fn {{from, event}, transitions_for_event} ->
      {_from, _event, to} = hd(transitions_for_event)

      quote do
        def do_navigate(%__MODULE__{current_state: unquote(from)} = fsm, unquote(event), event_data) do
          new_data = Map.merge(fsm.data, event_data)
          %{fsm | current_state: unquote(to), data: new_data}
        end
      end
    end)
  end

  defp merge_components(components) do
    Enum.reduce(components, {[], []}, fn {component_module, _opts}, {states_acc, transitions_acc} ->
      component_states = component_module.states()
      component_transitions = component_module.transitions()

      {states_acc ++ component_states, transitions_acc ++ component_transitions}
    end)
  end
end

# FSM Registry for inter-FSM communication
defmodule FSM.Registry do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register(id, module, fsm) do
    GenServer.call(__MODULE__, {:register, id, module, fsm})
  end

  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  def update(id, fsm) do
    GenServer.call(__MODULE__, {:update, id, fsm})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call({:register, id, module, fsm}, _from, state) do
    {:reply, :ok, Map.put(state, id, {module, fsm})}
  end

  def handle_call({:get, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, {:error, :not_found}, state}
      result -> {:reply, {:ok, result}, state}
    end
  end

  def handle_call({:update, id, fsm}, _from, state) do
    case Map.get(state, id) do
      {module, _old_fsm} -> {:reply, :ok, Map.put(state, id, {module, fsm})}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end
end

# Plugin Behavior
defmodule FSM.Plugin do
  @callback init(fsm :: struct(), opts :: keyword()) :: struct()
  @callback before_transition(fsm :: struct(), transition_data :: tuple(), opts :: keyword()) :: struct()
  @callback after_transition(fsm :: struct(), transition_data :: tuple(), opts :: keyword()) :: struct()

  defmacro __using__(_) do
    quote do
      @behaviour FSM.Plugin

      def init(fsm, _opts), do: fsm
      def before_transition(fsm, _data, _opts), do: fsm
      def after_transition(fsm, _data, _opts), do: fsm

      defoverridable [init: 2, before_transition: 3, after_transition: 3]
    end
  end
end

# Example: Logging Plugin
defmodule FSM.Plugins.Logger do
  use FSM.Plugin

  def init(fsm, opts) do
    level = Keyword.get(opts, :level, :info)
    put_in(fsm.data[:logger_config], %{level: level})
  end

  def before_transition(fsm, {old_state, event, _event_data}, _opts) do
    IO.puts("[FSM] Transitioning from #{old_state} on event #{event}")
    fsm
  end

  def after_transition(fsm, {old_state, new_state, event, _event_data}, _opts) do
    IO.puts("[FSM] Transitioned from #{old_state} to #{new_state} via #{event}")
    fsm
  end
end

# Example: Audit Plugin
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

# Component: Basic Timer States
defmodule FSM.Components.Timer do
  use FSM.Navigator

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
end

# Component: Security States
defmodule FSM.Components.Security do
  use FSM.Navigator

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
end

# Example: Modular Smart Door (combines Timer + Security + Door logic)
defmodule SmartDoor do
  use FSM.Navigator

  # Use components for modularity
  use_component FSM.Components.Timer
  use_component FSM.Components.Security

  # Use plugins for cross-cutting concerns
  use_plugin FSM.Plugins.Logger, level: :debug
  use_plugin FSM.Plugins.Audit

  # Door-specific states
  state :closed do
    navigate_to :opening, when: :open_command
  end

  state :opening do
    navigate_to :open, when: :fully_open
    navigate_to :closed, when: :obstruction
  end

  state :open do
    navigate_to :closing, when: :close_command
    navigate_to :closing, when: :auto_close
  end

  state :closing do
    navigate_to :closed, when: :fully_closed
    navigate_to :opening, when: :obstruction
  end

  initial_state :closed

  # Handle events from other FSMs
  def handle_external_event(fsm, SecuritySystem, :state_changed, %{to: :alarm}) do
    # When security system goes to alarm, lock the door
    navigate(fsm, :emergency_lock, %{reason: :security_alarm})
  end

  def handle_external_event(fsm, _source, _event, _data), do: fsm
end

# Example: Security System that communicates with Smart Door
defmodule SecuritySystem do
  use FSM.Navigator

  use_component FSM.Components.Security
  use_plugin FSM.Plugins.Logger

  state :monitoring do
    navigate_to :alarm, when: :motion_detected
    navigate_to :disarmed, when: :disarm
  end

  state :disarmed do
    navigate_to :monitoring, when: :arm
  end

  initial_state :monitoring
end

# Example usage and orchestration
defmodule FSMOrchestrator do
  def start_demo do
    # Start the registry
    {:ok, _pid} = FSM.Registry.start_link([])

    # Create interconnected FSMs
    door_id = :smart_door_1
    security_id = :security_system_1

    door = SmartDoor.new(%{location: "front_door"}, id: door_id)
    security = SecuritySystem.new(%{zone: "perimeter"}, id: security_id)

    # Set up inter-FSM communication
    door = SmartDoor.subscribe(door, security_id)
    security = SecuritySystem.subscribe(security, door_id)

    IO.puts("\n=== FSM Communication Demo ===")

    # Show initial states
    IO.puts("Door state: #{SmartDoor.current_state(door)}")
    IO.puts("Security state: #{SecuritySystem.current_state(security)}")

    # Trigger security alarm - should affect door
    IO.puts("\nTriggering motion detection...")
    security = SecuritySystem.navigate(security, :motion_detected)
    IO.puts("Security state after motion: #{SecuritySystem.current_state(security)}")

    # Show audit logs from plugins
    door_audit = get_in(door.data, [:audit_log]) || []
    security_audit = get_in(security.data, [:audit_log]) || []

    IO.puts("\nDoor audit log: #{inspect(door_audit)}")
    IO.puts("Security audit log: #{inspect(security_audit)}")

    # Visualize both FSMs
    SmartDoor.visualize()
    SecuritySystem.visualize()
  end

  def component_demo do
    IO.puts("\n=== Component Reusability Demo ===")

    # Show how timer component is reused
    timer = FSM.Components.Timer.new()
    IO.puts("Timer states: #{inspect(FSM.Components.Timer.states())}")

    # Show how security component is reused
    security = FSM.Components.Security.new()
    IO.puts("Security states: #{inspect(FSM.Components.Security.states())}")

    # Show how SmartDoor inherits from both
    door = SmartDoor.new()
    IO.puts("SmartDoor combined states: #{inspect(SmartDoor.states())}")
  end
end
