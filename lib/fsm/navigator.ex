defmodule FSM.Navigator do
  @moduledoc """
  A production-ready finite state machine with navigational syntax using Elixir macros.

  Features:
  - Modularity and componentization
  - Pluggable behavior system
  - Inter-FSM communication
  - Event persistence and audit trails
  - Performance optimizations
  - Multi-tenant support
  """

  defmacro __using__(_opts) do
    quote do
      import FSM.Navigator, only: [state: 2, navigate_to: 2, initial_state: 1, validate: 1, use_component: 1, use_component: 2, use_plugin: 1, use_plugin: 2, subscribe_to: 3, on_enter: 2, on_exit: 2]
      import ExUnit.Callbacks, only: []
      Module.register_attribute(__MODULE__, :states, accumulate: true)
      Module.register_attribute(__MODULE__, :transitions, accumulate: true)
      Module.register_attribute(__MODULE__, :initial_state, [])
      Module.register_attribute(__MODULE__, :plugins, accumulate: true)
      Module.register_attribute(__MODULE__, :components, accumulate: true)
      Module.register_attribute(__MODULE__, :subscriptions, accumulate: true)
      Module.register_attribute(__MODULE__, :validations, accumulate: true)
      Module.register_attribute(__MODULE__, :hooks, accumulate: true)

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
      @transitions {@current_state, unquote(condition), unquote(target_state), []}
    end
  end

  defmacro initial_state(state) do
    quote do
      @initial_state unquote(state)
    end
  end

  # Validation rules for state transitions
  defmacro validate(validation_fn) do
    quote do
      @validations unquote(validation_fn)
    end
  end

  # Lifecycle hooks
  defmacro on_enter(state, do: block) do
    quote do
      @hooks {:enter, unquote(state), unquote(Macro.escape(block))}
    end
  end

  defmacro on_exit(state, do: block) do
    quote do
      @hooks {:exit, unquote(state), unquote(Macro.escape(block))}
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
    _subscriptions = Module.get_attribute(env.module, :subscriptions) |> Enum.reverse()
    validations = Module.get_attribute(env.module, :validations) |> Enum.reverse()
    hooks = Module.get_attribute(env.module, :hooks) |> Enum.reverse()

    # Merge component states and transitions
    {component_states, component_transitions} = merge_components(components)
    all_states = Enum.uniq(states ++ component_states)
    all_transitions = transitions ++ component_transitions

    quote do
      defstruct [
        current_state: unquote(initial_state),
        data: %{},
        id: nil,
        tenant_id: nil,
        subscribers: [],
        plugins: unquote(Macro.escape(plugins)),
        metadata: %{
          created_at: nil,
          updated_at: nil,
          version: 1,
          tags: []
        },
        performance: %{
          transition_count: 0,
          last_transition_at: nil,
          avg_transition_time: 0
        }
      ]

      def new(initial_data \\ %{}, opts \\ []) do
        id = Keyword.get(opts, :id, make_ref())
        tenant_id = Keyword.get(opts, :tenant_id)

        fsm = %__MODULE__{
          current_state: unquote(initial_state),
          data: initial_data,
          id: id,
          tenant_id: tenant_id,
          metadata: %{
            created_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            version: 1,
            tags: Keyword.get(opts, :tags, [])
          }
        }

        # Register with FSM registry for inter-FSM communication
        FSM.Registry.register(id, __MODULE__, fsm)

        # Initialize plugins
        fsm = initialize_plugins(fsm)

        # Execute on_enter hook for initial state
        fsm = execute_hook(fsm, :enter, unquote(initial_state))

        fsm
      end

      def navigate(fsm, event, event_data \\ %{}, opts \\ []) do
        start_time = System.monotonic_time(:microsecond)
        old_state = fsm.current_state

        with {:ok, validated_fsm} <- validate_transition(fsm, event, event_data) do
          has_transition? = Enum.any?(unquote(Macro.escape(all_transitions)), fn {from, ev, _to, _opts} ->
            from == old_state and ev == event
          end)

          if not has_transition? do
            {:error, :invalid_transition}
          else
            # Apply pre-transition plugins
            validated_fsm = apply_plugins(validated_fsm, :before_transition, {old_state, event, event_data})

            # Execute on_exit hook for current state
            validated_fsm = execute_hook(validated_fsm, :exit, old_state)

            # Perform the actual transition
            new_fsm = do_navigate(validated_fsm, event, event_data)

            # Execute on_enter hook for new state
            new_fsm = execute_hook(new_fsm, :enter, new_fsm.current_state)

            # Apply post-transition plugins if state changed
            new_fsm = if new_fsm.current_state != old_state do
              new_fsm = apply_plugins(new_fsm, :after_transition, {old_state, new_fsm.current_state, event, event_data})

              # Update performance metrics
              new_fsm = update_performance_metrics(new_fsm, start_time)

              # Publish state change event to subscribers
              publish_event(new_fsm, :state_changed, %{
                from: old_state,
                to: new_fsm.current_state,
                event: event,
                data: event_data,
                timestamp: DateTime.utc_now()
              })

              # Persist state change
              persist_state_change(new_fsm, old_state, event, event_data)

              new_fsm
            else
              new_fsm
            end

            {:ok, new_fsm}
          end
        else
          {:error, _reason} -> {:error, :validation_error}
        end
      end

      # Generated navigation functions
      unquote(generate_navigate_clauses(all_transitions))

      def do_navigate(fsm, _event, _event_data), do: fsm

      # Component interface
      def states, do: unquote(all_states)
      def transitions, do: unquote(Macro.escape(all_transitions))
      def current_state(%__MODULE__{current_state: state}), do: state

      def can_navigate?(fsm, event) do
        case do_navigate(fsm, event, %{}) do
          ^fsm -> false
          _new_fsm -> true
        end
      end

      def possible_destinations(%__MODULE__{current_state: current}) do
        unquote(Macro.escape(all_transitions))
        |> Enum.filter(fn {from, _event, _to, _opts} -> from == current end)
        |> Enum.map(fn {_from, event, to, opts} -> {event, to, opts} end)
      end

      # Validation
      defp validate_transition(fsm, event, event_data) do
        Enum.reduce_while(unquote(Macro.escape(validations)), {:ok, fsm}, fn validation_fn, {:ok, acc_fsm} ->
          case apply(__MODULE__, validation_fn, [acc_fsm, event, event_data]) do
            {:ok, validated_fsm} -> {:cont, {:ok, validated_fsm}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end

      # Hook execution
      defp execute_hook(fsm, hook_type, state) do
        hook = Enum.find(unquote(Macro.escape(hooks)), fn {type, hook_state, _block} ->
          type == hook_type and hook_state == state
        end)

        case hook do
          {^hook_type, ^state, block} ->
            try do
              {result, _} = Code.eval_quoted(block, [fsm: fsm], __ENV__)
              result
            rescue
              e ->
                require Logger
                Logger.error("Hook execution failed: #{inspect(e)}")
                fsm
            end
          _ -> fsm
        end
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
            apply(plugin_module, hook, [acc_fsm, data, opts]) || acc_fsm
          else
            acc_fsm
          end
        end)
      end

      # Performance metrics
      defp update_performance_metrics(fsm, start_time) do
        end_time = System.monotonic_time(:microsecond)
        transition_time = end_time - start_time

        current_avg = fsm.performance.avg_transition_time
        new_count = fsm.performance.transition_count + 1
        new_avg = (current_avg * (new_count - 1) + transition_time) / new_count

        %{fsm |
          performance: %{
            fsm.performance |
            transition_count: new_count,
            last_transition_at: DateTime.utc_now(),
            avg_transition_time: new_avg
          }
        }
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

      # Persistence
      defp persist_state_change(fsm, old_state, event, event_data) do
        # This would typically save to a database or event store
        # For now, we'll just log it
        require Logger
        Logger.info("FSM #{fsm.id} transitioned from #{old_state} to #{fsm.current_state} via #{event}")

        # In production, you might want to:
        # 1. Save to an event store
        # 2. Update the FSM record in the database
        # 3. Send to a message queue for processing
        # 4. Update analytics/metrics

        fsm
      end

      # Default handler for external events
      def handle_external_event(fsm, _source_module, _event_type, _event_data) do
        fsm  # Override in implementing modules
      end

      # Error handling
      defp return_error(_fsm, error_type, _reason) do
        require Logger
        Logger.error("FSM navigation error: #{error_type}")
        {:error, error_type}
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

        Enum.each(transitions, fn {from, event, to, opts} ->
          IO.puts("  #{from} --#{event}--> #{to} #{if opts != [], do: "(#{inspect(opts)})"}")
        end)
      end
    end
  end

  defp generate_navigate_clauses(transitions) do
    transitions
    |> Enum.group_by(fn {from, event, _to, _opts} -> {from, event} end)
    |> Enum.map(fn {{from, event}, transitions_for_event} ->
      {_from, _event, to, _opts} = hd(transitions_for_event)

      quote do
        def do_navigate(%__MODULE__{current_state: unquote(from)} = fsm, unquote(event), event_data) do
          new_data = Map.merge(fsm.data, event_data)
          %{fsm |
            current_state: unquote(to),
            data: new_data,
            metadata: %{fsm.metadata | updated_at: DateTime.utc_now()}
          }
        end
      end
    end)
  end

  defp merge_components([]), do: {[], []}
  defp merge_components(components) do
    Enum.reduce(components, {[], []}, fn {component_module, _opts}, {states_acc, transitions_acc} ->
      # Check if component has states/transitions functions, if not, skip it
      component_states = if function_exported?(component_module, :states, 0) do
        component_module.states()
      else
        []
      end

      component_transitions = if function_exported?(component_module, :transitions, 0) do
        component_module.transitions()
      else
        []
      end

      {states_acc ++ component_states, transitions_acc ++ component_transitions}
    end)
  end
end
