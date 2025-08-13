# FSM Production Application

A production-ready Finite State Machine (FSM) application built with Elixir/Phoenix, featuring a WebSocket API, multi-tenant control panel, and Model Context Protocol (MCP) integration using [Hermes MCP](https://github.com/cloudwalk/hermes-mcp).

## 🚀 Features

### Core FSM Framework
- **Enhanced FSM Navigator**: Production-ready FSM DSL with macros
- **Modular Components**: Reusable FSM components and plugins
- **Inter-FSM Communication**: Event-driven communication between FSMs
- **Performance Monitoring**: Built-in metrics and performance tracking
- **Multi-tenant Support**: Tenant isolation and management

### WebSocket API
- **Real-time Communication**: Live FSM state updates via WebSockets
- **Event Broadcasting**: Real-time event distribution across tenants
- **Channel Management**: Efficient WebSocket connection handling
- **Authentication**: Secure tenant-based access control

### Multi-tenant Control Panel
- **LiveView Interface**: Modern, responsive web interface
- **FSM Management**: Create, monitor, and manage FSM instances
- **Real-time Updates**: Live state changes and metrics
- **Template System**: Predefined FSM templates for quick setup

### MCP Integration
- **AI Agent Support**: Integration with Claude, GPT, and other LLMs
- **Standardized Interface**: Model Context Protocol compliance
- **Rich Tool Set**: Comprehensive FSM management tools
- **Extensible Architecture**: Plugin-based tool system

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web Client   │    │   Phoenix      │    │   FSM Core     │
│   (LiveView)   │◄──►│   WebSocket    │◄──►│   Framework    │
│                 │    │   Channels     │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   MCP Server   │    │   FSM Manager   │
                       │   (Hermes)     │    │   & Registry    │
                       └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   AI Agents    │
                       │   (Claude,     │
                       │    GPT, etc.)  │
                       └─────────────────┘
```

## 🛠️ Technology Stack

- **Backend**: Elixir 1.14+, Phoenix 1.7+
- **Database**: PostgreSQL with Ecto
- **Real-time**: Phoenix Channels & LiveView
- **MCP**: Hermes MCP library
- **Frontend**: Tailwind CSS, Alpine.js
- **Monitoring**: Prometheus metrics
- **Background Jobs**: Oban
- **Authentication**: Guardian JWT

## 📦 Installation

### Prerequisites
- Elixir 1.14+
- Erlang/OTP 24+
- PostgreSQL 12+
- Node.js 16+ (for assets)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd fsm-app
   ```

2. **Install dependencies**
   ```bash
   mix deps.get
   ```

3. **Setup database**
   ```bash
   mix ecto.setup
   ```

4. **Install and build assets**
   ```bash
   mix assets.setup
   mix assets.build
   ```

5. **Start the application**
   ```bash
   mix phx.server
   ```

6. **Access the application**
   - Web Interface: http://localhost:4000
   - MCP Endpoint: http://localhost:4000/mcp

## 🔧 Configuration

### Environment Variables
```bash
# Database
export DATABASE_URL="postgresql://user:password@localhost/fsm_app"

# MCP Configuration
export MCP_SERVER_ENABLED=true
export MCP_SERVER_PORT=4001

# Security
export SECRET_KEY_BASE="your-secret-key"
export GUARDIAN_SECRET_KEY="your-guardian-secret"
```

### Configuration Files
- `config/config.exs` - General configuration
- `config/dev.exs` - Development settings
- `config/prod.exs` - Production settings
- `config/test.exs` - Test configuration

## 📚 Usage

### Creating FSMs

#### Via Web Interface
1. Navigate to the control panel
2. Click "Create FSM"
3. Select a module (SmartDoor, SecuritySystem, Timer)
4. Configure parameters
5. Click "Create FSM"

#### Via MCP
```json
{
  "tool": "create_fsm",
  "arguments": {
    "module": "SmartDoor",
    "config": {
      "location": "front_entrance",
      "security_level": "high"
    },
    "tenant_id": "building_management"
  }
}
```

#### Via WebSocket
```javascript
const channel = socket.channel(`fsm:${tenantId}`);
channel.join();

channel.push("create_fsm", {
  module: "SmartDoor",
  config: { location: "front_entrance" }
});
```

### Sending Events

#### Via Web Interface
1. Select an FSM from the list
2. Click "Send Event"
3. Enter event name and data
4. Click "Send Event"

#### Via MCP
```json
{
  "tool": "send_event",
  "arguments": {
    "fsm_id": "door_001",
    "event": "open_command",
    "event_data": {"user_id": "john_doe"}
  }
}
```

#### Via WebSocket
```javascript
channel.push("send_event", {
  fsm_id: "door_001",
  event: "open_command",
  event_data: { user_id: "john_doe" }
});
```

### Monitoring FSMs

#### Real-time Updates
The WebSocket API provides real-time updates for:
- FSM state changes
- Event processing
- Performance metrics
- System statistics

#### MCP Tools
Available monitoring tools:
- `get_fsm_state` - Current FSM state
- `get_fsm_metrics` - Performance metrics
- `get_server_stats` - System statistics
- `list_tenant_fsms` - Tenant FSM overview

## 🏢 Multi-tenancy

### Tenant Isolation
- Each tenant has isolated FSM instances
- WebSocket channels are tenant-specific
- MCP operations respect tenant boundaries
- Data is completely separated between tenants

### Tenant Management
- Tenant creation and configuration
- User access control per tenant
- Resource limits and quotas
- Usage analytics and reporting

## 🔌 MCP Integration

### Available Tools

#### FSM Management
- `create_fsm` - Create new FSM instances
- `destroy_fsm` - Remove FSM instances
- `get_fsm_state` - Query FSM state
- `list_tenant_fsms` - List tenant FSMs

#### Event Handling
- `send_event` - Send events to FSMs
- `batch_send_events` - Batch event processing
- `validate_transition` - Validate state transitions

#### Monitoring
- `get_fsm_metrics` - Performance metrics
- `get_server_stats` - System statistics
- `get_available_modules` - Available FSM types

### MCP Client Setup
```elixir
# Connect to FSM MCP Server
{:ok, client} = Hermes.Client.start_link(
  name: "FSM Client",
  transport: {:streamable_http, base_url: "http://localhost:4000/mcp"}
)

# Use FSM tools
{:ok, result} = client.call_tool("create_fsm", %{
  module: "SmartDoor",
  config: %{location: "main_entrance"},
  tenant_id: "tenant_001"
})
```

## 🧪 Testing

### Running Tests
```bash
# All tests
mix test

# Specific test file
mix test test/fsm/navigator_test.exs

# With coverage
mix test --cover

# Integration tests
mix test test/integration/
```

### Test Structure
- `test/unit/` - Unit tests for individual modules
- `test/integration/` - Integration tests
- `test/support/` - Test helpers and fixtures
- `test/mcp/` - MCP-specific tests

## 📊 Monitoring & Observability

### Metrics
- Prometheus metrics for all operations
- Custom FSM performance metrics
- WebSocket connection statistics
- MCP operation metrics

### Health Checks
- FSM Registry health
- Database connectivity
- WebSocket channel status
- MCP server health

### Logging
- Structured logging with metadata
- FSM state change logging
- Event processing logs
- Error tracking and reporting

## 🚀 Deployment

### Production Setup
1. **Environment Configuration**
   ```bash
   export MIX_ENV=prod
   export SECRET_KEY_BASE="your-production-secret"
   export DATABASE_URL="your-production-db-url"
   ```

2. **Database Migration**
   ```bash
   mix ecto.migrate
   ```

3. **Asset Compilation**
   ```bash
   mix assets.deploy
   ```

4. **Release Build**
   ```bash
   mix release
   ```

### Docker Deployment
```dockerfile
FROM elixir:1.14-alpine

WORKDIR /app
COPY . .

RUN mix deps.get --only prod
RUN mix compile
RUN mix assets.deploy
RUN mix release

CMD ["mix", "phx.server"]
```

### Kubernetes
- Helm charts for deployment
- Horizontal Pod Autoscaler
- Ingress configuration
- Service mesh integration

## 🔒 Security

### Authentication
- JWT-based authentication
- Multi-factor authentication support
- Session management
- Password policies

### Authorization
- Role-based access control (RBAC)
- Tenant isolation
- API rate limiting
- Resource quotas

### Data Protection
- Data encryption at rest
- TLS for all communications
- Input validation and sanitization
- Audit logging

## 🤝 Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### Code Style
- Follow Elixir style guidelines
- Use Credo for code quality
- Run Dialyzer for type checking
- Maintain test coverage > 90%

### Testing Guidelines
- Write unit tests for new features
- Add integration tests for workflows
- Update documentation
- Ensure backward compatibility

## 📖 Documentation

### API Documentation
- [WebSocket API Reference](docs/websocket_api.md)
- [MCP Tools Reference](docs/mcp_tools.md)
- [FSM DSL Reference](docs/fsm_dsl.md)

### Architecture Documentation
- [System Architecture](docs/architecture.md)
- [MCP Integration](docs/mcp_integration.md)
- [Multi-tenancy Design](docs/multi_tenancy.md)

### User Guides
- [Getting Started](docs/getting_started.md)
- [Control Panel Guide](docs/control_panel.md)
- [MCP Client Setup](docs/mcp_client.md)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Hermes MCP](https://github.com/cloudwalk/hermes-mcp) for MCP implementation
- [Phoenix Framework](https://phoenixframework.org/) for the web framework
- [Elixir](https://elixir-lang.org/) for the programming language
- [Tailwind CSS](https://tailwindcss.com/) for the UI framework

## 📞 Support

### Getting Help
- [GitHub Issues](https://github.com/your-org/fsm-app/issues)
- [Documentation](https://docs.fsm-app.com)
- [Community Forum](https://community.fsm-app.com)

### Commercial Support
- Enterprise support available
- Custom development services
- Training and consulting
- SLA guarantees

---

**Built with ❤️ using Elixir, Phoenix, and Hermes MCP**
