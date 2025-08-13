# FSM System Test Suite

This directory contains comprehensive tests for the FSM (Finite State Machine) system.

## Test Structure

```
test/
├── test_helper.exs              # Test environment setup
├── support/
│   └── test_config.exs         # Test configuration
├── fsm/
│   ├── navigator_test.exs      # Core Navigator tests
│   ├── smart_door_test.exs     # SmartDoor FSM tests
│   ├── components/
│   │   ├── timer_test.exs      # Timer component tests
│   │   └── security_test.exs   # Security component tests
│   ├── plugins/
│   │   ├── logger_test.exs     # Logger plugin tests
│   │   └── audit_test.exs      # Audit plugin tests
│   └── integration_test.exs    # End-to-end integration tests
└── README.md                   # This file
```

## Running Tests

### Run All Tests
```bash
mix test
```

### Run Specific Test Files
```bash
# Run only Navigator tests
mix test test/fsm/navigator_test.exs

# Run only component tests
mix test test/fsm/components/

# Run only plugin tests
mix test test/fsm/plugins/

# Run only integration tests
mix test test/fsm/integration_test.exs
```

### Run Tests with Coverage
```bash
mix test --cover
```

### Run Tests with Specific Pattern
```bash
# Run tests matching "timer"
mix test --only timer

# Run tests matching "security"
mix test --only security
```

## Test Categories

### 1. Unit Tests
- **Navigator Tests**: Test the core FSM functionality
- **Component Tests**: Test individual components (Timer, Security)
- **Plugin Tests**: Test plugins (Logger, Audit)

### 2. Integration Tests
- **SmartDoor Tests**: Test the complete SmartDoor FSM
- **System Integration**: Test the entire system working together

### 3. Test Coverage
- State transitions and validation
- Lifecycle hooks execution
- Component integration
- Plugin functionality
- Error handling and edge cases
- Performance metrics
- Multi-tenant isolation

## Test Data

Tests use consistent test data defined in `test/support/test_config.exs`:
- Default user: "test_user"
- Default tenant: "test_tenant"
- Test sensors: door, motion, and window sensors

## Writing New Tests

### Test Module Structure
```elixir
defmodule FSM.YourModuleTest do
  use ExUnit.Case
  alias FSM.YourModule

  describe "Feature Description" do
    test "specific test case" do
      # Test implementation
      assert expected == actual
    end
  end
end
```

### Test Naming Conventions
- Use descriptive test names that explain the scenario
- Group related tests in `describe` blocks
- Use consistent naming patterns across test files

### Assertions
- Use `assert` for positive assertions
- Use `refute` for negative assertions
- Use `assert_raise` for exception testing
- Use `assert_receive` for message testing

## Test Environment

The test environment is configured to:
- Use minimal logging (warn level)
- Set appropriate timeouts
- Provide consistent test data
- Isolate tests from production environment

## Continuous Integration

Tests are designed to run in CI/CD pipelines:
- No external dependencies
- Deterministic results
- Fast execution
- Comprehensive coverage

## Debugging Tests

### Run Single Test
```bash
mix test test/fsm/navigator_test.exs:25
```

### Run with IEx
```bash
iex -S mix test
```

### Verbose Output
```bash
mix test --trace
```

## Performance Considerations

- Tests are designed to run quickly
- No heavy I/O operations
- Minimal database interactions
- Efficient state management testing

## Contributing

When adding new features:
1. Write tests first (TDD approach)
2. Ensure all tests pass
3. Maintain test coverage above 90%
4. Follow existing test patterns
5. Update this README if needed
