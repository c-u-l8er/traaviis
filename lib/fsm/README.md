# FSM (Finite State Machine) System

A production-ready finite state machine system built in Elixir with modularity, componentization, and pluggable behavior.

## Features

- **Modular State Management**: Define states and transitions with a clean DSL
- **Component System**: Reusable FSM components for common functionality
- **Plugin Architecture**: Cross-cutting concerns like logging and auditing
- **Multi-tenant Support**: Isolated FSM instances per tenant
- **Inter-FSM Communication**: Events between different state machines
- **Lifecycle Hooks**: Execute code on state entry/exit
- **Validation Rules**: Custom validation for state transitions
- **Performance Optimized**: Efficient state transitions and event handling

## Quick Start

### Creating a Simple FSM

```elixir
defmodule MyFSM do
  use FSM.Navigator

  state :idle do
    navigate_to :active, when: :start
  end

  state :active do
    navigate_to :idle, when: :stop
  end

  initial_state :idle
end
```

### Using Components

Components provide reusable FSM functionality:

```elixir
defmodule MyFSM do
  use FSM.Navigator
  
  # Include timer functionality
  use_component FSM.Components.Timer
  
  # Include security features
  use_component FSM.Components.Security
  
  # ... your states
end
```

Components automatically merge their states and transitions with your main FSM.

### Adding Plugins

```elixir
defmodule MyFSM do
  use FSM.Navigator
  
  # Add logging with custom level
  use_plugin FSM.Plugins.Logger, level: :debug
  
  # Add audit trail
  use_plugin FSM.Plugins.Audit
  
  # ... your states
end
```

## SmartDoor Example

The `SmartDoor` FSM demonstrates a complete door control system:

```elixir
defmodule FSM.SmartDoor do
  use FSM.Navigator

  use_component FSM.Components.Timer
  use_component FSM.Components.Security
  use_plugin FSM.Plugins.Logger, level: :debug
  use_plugin FSM.Plugins.Audit

  state :closed do
    navigate_to :opening, when: :open_command
    navigate_to :emergency_lock, when: :emergency_lock
  end

  state :opening do
    navigate_to :open, when: :fully_open
    navigate_to :closed, when: :obstruction
    navigate_to :emergency_lock, when: :emergency_lock
  end

  # ... more states
end
```

## State Management

### States

Define states with the `state/2` macro:

```elixir
state :state_name do
  # Define transitions here
end
```

### Transitions

Define transitions with `navigate_to/2`:

```elixir
navigate_to :target_state, when: :event_name
```

### Initial State

Set the starting state:

```elixir
initial_state :state_name
```

## Lifecycle Hooks

Execute code when entering or exiting states:

```elixir
on_enter :state_name do
  # Code to run when entering the state
end

on_exit :state_name do
  # Code to run when exiting the state
end
```

## Validation

Add custom validation rules:

```elixir
validate :my_validation_function
```

Validation functions should return `{:ok, fsm}` or `{:error, reason}`.

## Component System

### Timer Component

Provides timer functionality for FSM states:

```elixir
use_component FSM.Components.Timer
```

### Security Component

Handles security-related state management:

```elixir
use_component FSM.Components.Security
```

## Plugin System

### Logger Plugin

Configurable logging for state transitions:

```elixir
use_plugin FSM.Plugins.Logger, level: :debug
```

### Audit Plugin

Tracks all state changes and events:

```elixir
use_plugin FSM.Plugins.Audit
```

## FSM Manager API

### Creating FSMs

```elixir
{:ok, fsm_id} = FSM.Manager.create_fsm(MyFSM, %{}, "tenant_id")
```

### Sending Events

```elixir
{:ok, result} = FSM.Manager.send_event(fsm_id, :event_name, %{data: "value"})
```

### Getting State

```elixir
{:ok, state} = FSM.Manager.get_fsm_state(fsm_id)
```

### Updating Data

```elixir
{:ok, result} = FSM.Manager.update_fsm_data(fsm_id, %{new_data: "value"})
```

## Testing

Run the test suite:

```bash
mix test lib/fsm/smart_door_test.exs
```

## Architecture

The FSM system consists of several key modules:

- **FSM.Navigator**: Core DSL and state management
- **FSM.Manager**: FSM lifecycle and operations
- **FSM.Components**: Reusable FSM functionality
- **FSM.Plugins**: Cross-cutting behavior
- **FSM.Registry**: FSM registration and discovery

## Best Practices

1. **Keep states focused**: Each state should represent a clear, distinct condition
2. **Use components**: Leverage the component system for reusable functionality
3. **Add plugins**: Include logging and auditing for production systems
4. **Validate transitions**: Add validation rules for complex business logic
5. **Handle errors gracefully**: Use proper error handling in lifecycle hooks
6. **Test thoroughly**: Write comprehensive tests for all state transitions

## Performance Considerations

- FSMs are lightweight and efficient
- State transitions are O(1) operations
- Components and plugins are loaded once at compile time
- Event handling is optimized for high-throughput scenarios

## Multi-tenancy

Each FSM instance is isolated by tenant ID, ensuring data separation and security between different tenants.
