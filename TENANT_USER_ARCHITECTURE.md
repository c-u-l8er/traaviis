# BrokenRecord PaaS - Tenant, User & Member Architecture Documentation

## Executive Summary

BrokenRecord is a multi-tenant Platform-as-a-Service (PaaS) built with Elixir that provides containerized application deployment on Fly.io's global edge network. This document comprehensively details how tenants, users, members, and the finite state machine (FSM) architecture work together in both the filesystem and UI to provide secure, scalable multi-tenant isolation.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Storage Architecture](#data-storage-architecture)
3. [User & Member Model](#user--member-model)
4. [Tenant Structure & Management](#tenant-structure--management)
5. [Finite State Machine Implementation](#finite-state-machine-implementation)
6. [Multi-Tenancy Implementation](#multi-tenancy-implementation)
7. [UI & Authentication Flow](#ui--authentication-flow)
8. [Filesystem Organization](#filesystem-organization)
9. [ETS Memory Management](#ets-memory-management)
10. [Application Types & Native Catalog](#application-types--native-catalog)
11. [Security & Isolation](#security--isolation)
12. [Performance & Scalability](#performance--scalability)

---

## Architecture Overview

### Core System Design

BrokenRecord implements a **dual-level user model** with complete tenant isolation:

1. **Global Users**: Platform-wide accounts stored in `./data/system/users/`
2. **Tenant Members**: User memberships within specific tenants with role-based permissions
3. **Tenant Organizations**: Isolated environments with their own resources, billing, and data

```
┌─────────────────────────────────────────────────────────────────┐
│                   BrokenRecord PaaS Platform                   │
├─────────────────────────────────────────────────────────────────┤
│ Global Users Layer (./data/system/users/)                      │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
│ │ user_abc123 │ │ user_def456 │ │ user_ghi789 │                │
│ └─────────────┘ └─────────────┘ └─────────────┘                │
├─────────────────────────────────────────────────────────────────┤
│ Tenant Isolation Layer (./data/tenants/)                       │
│                                                                 │
│ ┌─────────────────────┐ ┌─────────────────────┐                 │
│ │   Tenant A          │ │   Tenant B          │                 │
│ │   ├─config.json     │ │   ├─config.json     │                 │
│ │   ├─members/        │ │   ├─members/        │                 │
│ │   ├─applications/   │ │   ├─applications/   │                 │
│ │   ├─deployments/    │ │   ├─deployments/    │                 │
│ │   ├─billing/        │ │   ├─billing/        │                 │
│ │   └─monitoring/     │ │   └─monitoring/     │                 │
│ └─────────────────────┘ └─────────────────────┘                 │
├─────────────────────────────────────────────────────────────────┤
│ ETS In-Memory Layer (Performance + Scalability)                │
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐    │
│ │ :tenants_0      │ │ :tenants_1      │ │ ...             │    │
│ │ :tenants_9      │ │ :users_registry │ │ :deployments_   │    │
│ │ (Sharded)       │ │                 │ │ registry        │    │
│ └─────────────────┘ └─────────────────┘ └─────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

- **Complete Tenant Isolation**: Each tenant has completely isolated data, billing, infrastructure, and application deployments
- **Global User Identity**: Users have a single platform account but can be members of multiple tenants with different roles
- **No Database Dependency**: Uses ETS + JSON persistence for human-readable, transparent data storage
- **FSM-Driven Deployments**: All deployment operations use finite state machines for reliability and observability
- **Memory-Optimized**: Aggressive ETS management with automatic JSON persistence for Fly.io constraints

---

## Data Storage Architecture

### Storage Strategy Overview

BrokenRecord uses a **hybrid ETS + JSON persistence approach** with no traditional database:

```elixir
# Storage Flow
User Action → ETS (In-Memory) → JSON Persistence → ETS Cleanup → Archive
     ↓              ↓                ↓                 ↓           ↓
Real-time    Ultra-fast       Human-readable    Memory      Long-term
Response     Operations       Debugging         Management   Storage
```

### ETS Table Design

```elixir
# Core ETS Tables
:users_registry                 # Global platform users
:tenant_members_registry        # User memberships per tenant  
:member_invitations_registry    # Pending invitations
:applications_registry          # Application definitions
:deployments_registry          # Deployment states (FSM driven)
:resource_usage                # Usage tracking for billing

# Sharded Tenant Tables (for scalability)
:tenants_0, :tenants_1, ..., :tenants_9   # 10 shards using phash2
```

### Memory Management Strategy

```elixir
# Memory Thresholds (Fly.io optimized)
@memory_threshold 268_435_456  # 256MB - aggressive for containers
@entry_ttl 3600               # 1 hour TTL for inactive entries
@shard_count 10               # Horizontal scalability

# Cleanup Strategy
- Every 10 seconds: Memory pressure checks
- Every 5 minutes: Cleanup old entries  
- On pressure: Emergency cleanup + JSON persistence
- Archive: Compress old data to .json.gz files
```

---

## User & Member Model

### Global Users (Platform Accounts)

**Location**: `./data/system/users/user_{uuid}.json`

```elixir
%BrokenRecord.Accounts.User{
  id: "user_abc123",
  email: "john.doe@example.com", 
  password_hash: "hashed_password",
  name: "John Doe",
  avatar_url: "https://avatar.service.com/user_abc123.jpg",
  created_at: ~U[2024-01-15 10:30:00Z],
  updated_at: ~U[2024-01-20 14:22:00Z],
  last_login: ~U[2024-01-20 14:22:00Z],
  email_verified: true,
  status: :active,  # :active, :suspended, :pending_verification
  platform_role: :user  # :platform_admin, :user
}
```

### Tenant Members (Tenant-Specific Roles)

**Location**: `./data/tenants/{tenant_id}/members/member_{user_id}.json`

```elixir
%BrokenRecord.Tenants.Member{
  tenant_id: "tenant_123",
  user_id: "user_abc123", 
  tenant_role: :admin,  # :owner, :admin, :developer, :viewer
  permissions: [:deploy, :scale, :billing, :user_management],
  joined_at: ~U[2024-01-15 10:35:00Z],
  invited_by: "user_def456",
  member_status: :active,  # :active, :invited, :suspended
  last_activity: ~U[2024-01-20 14:22:00Z]
}
```

### Role-Based Access Control

```elixir
# Platform Roles (Global)
:platform_admin  # Full system administration access
:user            # Standard platform user

# Tenant Roles (Per-tenant)
:owner           # Full tenant control, billing, deletion
:admin           # User management, deployments, configuration  
:developer       # Deploy applications, view metrics
:viewer          # Read-only access to dashboards

# Granular Permissions
[:deploy, :scale, :billing, :user_management, :infrastructure_management,
 :monitoring, :logs, :settings, :delete_applications]
```

### User-Tenant Relationship Patterns

```elixir
# One User, Multiple Tenants with Different Roles
user_abc123:
  ├─ tenant_company_a (role: :admin)
  ├─ tenant_startup_b (role: :developer) 
  └─ tenant_personal_c (role: :owner)

# ETS Lookup Pattern
{tenant_id, user_id} => member_data
{"tenant_123", "user_abc123"} => %Member{tenant_role: :admin, ...}
```

---

## Tenant Structure & Management

### Tenant Configuration

**Location**: `./data/tenants/{tenant_id}/config.json`

```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "name": "Acme Corporation", 
  "domain": "acme.com",
  "slug": "acme",
  "owner_id": "user_abc123",
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:00Z", 
  "status": "active",
  "member_count": 3,
  "config": {
    "resource_limits": {
      "cpu_cores": 8,
      "memory_gb": 32, 
      "storage_gb": 500,
      "applications_limit": 10
    },
    "billing_plan": "pro",
    "features": [
      "load_balancer",
      "auto_scaling", 
      "custom_domains"
    ]
  }
}
```

### Tenant Directory Structure

```
./data/tenants/{tenant_uuid}/
├── config.json                    # Tenant configuration
├── members/
│   ├── member_{user_uuid}.json     # Member profiles with tenant-specific data
│   ├── roster.json                 # Member roster summary
│   └── invitations.json            # Pending member invitations
├── applications/
│   ├── app_{uuid}.json             # Application definitions
│   └── deployments/
│       ├── dep_{uuid}.json         # Active deployment states
│       └── archived/               # Archived deployment history
│           └── dep_{uuid}.json.gz
├── infrastructure/
│   ├── servers/
│   │   └── server_{id}.json        # Fly.io machine details
│   ├── networks/
│   │   └── net_{id}.json           # Network configurations
│   └── load_balancers/
│       └── lb_{id}.json            # Load balancer configs
├── billing/
│   ├── usage/
│   │   ├── YYYY-MM.json            # Monthly usage data
│   │   └── archived/               # Compressed old usage
│   │       └── YYYY-MM.json.gz
│   └── invoices/
│       └── inv_{uuid}.json         # Generated invoices
└── monitoring/
    ├── metrics/
    │   ├── YYYY-MM-DD.json         # Daily metrics
    │   └── archived/               # Compressed old metrics
    │       └── YYYY-MM-DD.json.gz
    └── alerts.json                 # Active alerts
```

### Tenant Isolation Mechanisms

1. **Filesystem Isolation**: Complete directory separation per tenant
2. **ETS Sharding**: Tenants distributed across 10 shards for performance
3. **Infrastructure Isolation**: Separate Fly.io apps and networks per tenant
4. **Billing Isolation**: Separate usage tracking and invoicing
5. **Access Control**: JWT tokens scoped to specific tenant contexts

---

## Finite State Machine Implementation

### FSM Architecture Overview

BrokenRecord uses **GenStateMachine** for reliable, observable deployment management:

```elixir
# Deployment State Flow
:pending → :creating_app → :deploying → :running → :stopped
    ↓           ↓            ↓          ↓        ↓
Validate → Fly.io App → Deploy → Health → Cleanup
Resources   Creation    Machine  Checks   Resources
```

### Deployment State Machine

```elixir
defmodule BrokenRecord.Deployment.FlyStateMachine do
  use GenStateMachine
  
  # State Transitions
  def handle_event(:cast, :start_deployment, :pending, data) do
    case ensure_fly_app(data.deployment) do
      {:ok, app_info} ->
        {:next_state, :creating_app, update_deployment(data, app_info)}
      {:error, reason} ->
        {:next_state, :failed, %{data | error: reason}}
    end
  end
  
  def handle_event(:info, {:app_ready, app_name}, :creating_app, data) do
    case deploy_machine(data.deployment) do
      {:ok, machine_info} ->
        {:next_state, :deploying, Map.put(data, :machine, machine_info)}
      {:error, reason} ->
        {:next_state, :failed, %{data | error: reason}}
    end
  end
  
  def handle_event(:info, {:machine_ready, :healthy}, :deploying, data) do
    {:next_state, :running, data}
  end
  
  # Scaling Operations
  def handle_event(:cast, :scale, :running, data) do
    case create_additional_machines(data.deployment) do
      {:ok, new_machines} ->
        {:keep_state, Map.update!(data, :machines, &(&1 ++ new_machines))}
      {:error, _reason} ->
        {:keep_state, data}
    end
  end
end
```

### FSM State Persistence

Each deployment state is persisted to JSON:

```json
// ./data/tenants/{tenant_id}/applications/deployments/dep_789.json
{
  "id": "dep-789",
  "application_id": "app-456",
  "tenant_id": "123e4567-e89b-12d3-a456-426614174000",
  "version": "v1.2.0",
  "state": "running",  // FSM current state
  "infrastructure": {
    "server_ids": ["srv-123", "srv-124"],
    "load_balancer_id": "lb-456", 
    "network_id": "net-789"
  },
  "endpoints": [
    "https://api.acme.com",
    "https://acme-api.fly.dev"
  ],
  "started_at": "2024-01-15T11:30:00Z",
  "last_health_check": "2024-01-15T15:25:00Z",
  "health_status": "healthy",
  "state_history": [
    {"state": "pending", "timestamp": "2024-01-15T11:25:00Z"},
    {"state": "creating_app", "timestamp": "2024-01-15T11:26:00Z"},
    {"state": "deploying", "timestamp": "2024-01-15T11:27:00Z"},
    {"state": "running", "timestamp": "2024-01-15T11:30:00Z"}
  ]
}
```

### BrokenRecord Native FSM Applications

The platform includes a specialized **BrokenRecord FSM Server** application:

```elixir
"brokenrecord_fsm" => %{
  name: "BrokenRecord FSM Server",
  description: "Finite State Machine server for workflow orchestration",
  base_cost: 28.00,  # Highest cost native app - most complex
  features: [
    "Visual workflow designer",
    "State persistence", 
    "Event-driven transitions",
    "Parallel state execution",
    "Workflow versioning",
    "Real-time monitoring"
  ],
  default_config: %{
    "brokenrecord_config" => %{
      "max_state_machines" => 1000,
      "max_transitions_per_hour" => 10000,
      "persistence_mode" => "database",
      "clustering_enabled" => true,
      "workflow_timeout_seconds" => 3600
    }
  }
}
```

---

## Multi-Tenancy Implementation

### Tenant Context Propagation

```elixir
# Every operation is scoped to a tenant
def create_application(tenant_id, app_attrs) do
  with {:ok, tenant} <- Tenants.get_tenant(tenant_id),
       {:ok, app} <- validate_app_config(app_attrs, tenant),
       :ok <- check_resource_limits(tenant, app) do
    
    application = %Application{
      id: UUID.uuid4(),
      tenant_id: tenant_id,  # Always scoped!
      name: app_attrs.name,
      # ... rest of attributes
    }
    
    ETSManager.put_application(application)
  end
end
```

### Resource Isolation

```elixir
# Tenant Resource Limits
%{
  "resource_limits" => %{
    "cpu_cores" => 8,
    "memory_gb" => 32,
    "storage_gb" => 500,
    "applications_limit" => 10
  },
  "billing_plan" => "pro"
}

# Resource Enforcement
def check_resource_limits(tenant, new_app) do
  current_usage = calculate_tenant_usage(tenant.id)
  
  if current_usage.cpu_cores + new_app.cpu_cores > tenant.config.resource_limits.cpu_cores do
    {:error, :cpu_limit_exceeded}
  else
    :ok
  end
end
```

### Fly.io Integration Per Tenant

```elixir
# Tenant-specific Fly.io apps
app_name = "#{tenant_id}-#{application_name}"
fly_app = "tenant-123-web-api"

# 6PN Private Networking per tenant
network_name = "tenant-#{tenant_id}-network"
```

---

## UI & Authentication Flow

### Authentication Architecture

```elixir
# JWT-based authentication with tenant context
defmodule BrokenRecordWeb.AuthPlug do
  def on_mount(:ensure_authenticated, _params, session, socket) do
    with {:ok, token} <- get_token_from_session(session),
         {:ok, claims} <- Guardian.decode_and_verify(token),
         {:ok, user} <- get_user_from_claims(claims),
         {:ok, tenant_context} <- get_tenant_context(user, session) do
      
      socket = socket
      |> assign(:current_user, user)
      |> assign(:current_tenant, tenant_context.tenant)
      |> assign(:member_role, tenant_context.role)
      |> assign(:permissions, tenant_context.permissions)
      
      {:cont, socket}
    else
      _ -> {:halt, redirect(socket, to: "/auth")}
    end
  end
end
```

### LiveView Components

```elixir
# Dashboard with real-time tenant-scoped updates
defmodule BrokenRecordWeb.DashboardLive do
  def mount(_params, %{"tenant_id" => tenant_id}, socket) do
    if connected?(socket) do
      # Subscribe to tenant-specific updates
      Phoenix.PubSub.subscribe(BrokenRecord.PubSub, "tenant:#{tenant_id}")
      Phoenix.PubSub.subscribe(BrokenRecord.PubSub, "deployments:#{tenant_id}")
    end
    
    tenant = Tenants.get_tenant!(tenant_id)
    applications = Applications.list_by_tenant(tenant_id)
    deployments = Deployments.list_recent_by_tenant(tenant_id)
    
    {:ok, assign(socket,
      tenant: tenant,
      applications: applications,  
      deployments: deployments
    )}
  end
end
```

### Tenant Switching Flow

```elixir
# Router configuration
scope "/", BrokenRecordWeb do
  # Tenant switching route with token
  get "/auth/switch_tenant", AuthController, :switch_tenant
  
  live_session :authenticated, 
    on_mount: {BrokenRecordWeb.AuthPlug, :ensure_authenticated} do
    live "/dashboard", DashboardLive, :index
  end
end

# Tenant switching implementation
def switch_tenant(conn, %{"token" => token, "return_to" => return_to}) do
  with {:ok, tenant_id} <- verify_tenant_switch_token(token),
       {:ok, user} <- get_current_user(conn),
       {:ok, _member} <- verify_tenant_membership(user.id, tenant_id) do
    
    conn
    |> put_session(:current_tenant_id, tenant_id)
    |> redirect(to: return_to || "/dashboard")
  else
    _ -> redirect(conn, to: "/auth")
  end
end
```

### UI Tenant Context

Every LiveView automatically receives tenant context:

```elixir
# Template rendering with tenant data
~H"""
<div class="max-w-7xl mx-auto py-6">
  <h1 class="text-3xl font-bold">
    <%= @tenant.name %> Dashboard
  </h1>
  
  <!-- Real-time deployment status -->
  <div class="mt-8">
    <%= for deployment <- @deployments do %>
      <div class="bg-white shadow rounded-lg p-6">
        <div class="flex items-center justify-between">
          <h3><%= deployment.application.name %></h3>
          <span class={"px-2 py-1 rounded-full #{status_color(deployment.state)}"}>
            <%= deployment.state %>
          </span>
        </div>
      </div>
    <% end %>
  </div>
</div>
"""
```

---

## Filesystem Organization

### System-Wide Data Structure

```
./data/
├── system/                         # Global platform data
│   ├── users/
│   │   ├── user_{uuid}.json        # Global user accounts
│   │   └── index.json              # User lookup index
│   ├── sessions/
│   │   └── active_sessions.json    # User session data  
│   ├── global_metrics.json         # System-wide metrics
│   ├── ets_backups/               # Periodic ETS snapshots
│   │   └── backup_YYYY-MM-DD-HH.json.gz
│   └── maintenance.json           # Maintenance schedules
└── tenants/                       # Tenant-isolated data
    ├── {tenant_uuid}/            # Each tenant completely isolated
    │   └── [full tenant structure as detailed above]
    └── index.json                # Tenant lookup index
```

### JSON File Examples

#### Global User File
```json
// ./data/system/users/user_abc123.json
{
  "id": "user_abc123",
  "email": "john.doe@example.com",
  "name": "John Doe",
  "created_at": "2024-01-15T10:30:00Z",
  "status": "active",
  "platform_role": "user",
  "tenant_memberships": [
    {
      "tenant_id": "tenant_123",
      "tenant_name": "Acme Corp",
      "role": "admin", 
      "joined_at": "2024-01-15T10:35:00Z"
    }
  ]
}
```

#### Tenant Member File  
```json
// ./data/tenants/tenant_123/members/member_user_abc123.json
{
  "user_id": "user_abc123",
  "tenant_id": "tenant_123", 
  "tenant_role": "admin",
  "permissions": [
    "deploy", "scale", "billing", "user_management"
  ],
  "joined_at": "2024-01-15T10:35:00Z",
  "member_status": "active",
  "activity_summary": {
    "deployments_created": 15,
    "last_deployment": "2024-01-19T16:30:00Z",
    "login_count": 42
  }
}
```

#### Application Definition
```json
// ./data/tenants/tenant_123/applications/app_456.json  
{
  "id": "app-456",
  "tenant_id": "tenant_123",
  "name": "web-api",
  "type": "web_app",
  "source": "custom",
  "image": "mycompany/web-api:v1.2.0",
  "config": {
    "ports": [80, 443],
    "env_vars": {
      "NODE_ENV": "production"
    },
    "resources": {
      "cpu_cores": 2,
      "memory_mb": 1024,
      "storage_gb": 10
    }
  }
}
```

---

## ETS Memory Management

### Memory Optimization Strategy

```elixir
# Aggressive memory management for Fly.io containers
@memory_threshold 268_435_456  # 256MB limit
@entry_ttl 3600               # 1-hour TTL
@shard_count 10               # Horizontal scaling

# Automatic Cleanup Process
def handle_info(:memory_check, state) do
  total_memory = calculate_total_ets_memory()
  
  if total_memory > @memory_threshold do
    # 1. Persist all data to JSON
    persist_all_data()
    
    # 2. Clean old entries
    cleanup_old_entries()
    
    # 3. Emergency cleanup if still over threshold
    if calculate_total_ets_memory() > @memory_threshold do
      emergency_memory_cleanup()
    end
  end
  
  schedule_memory_check()
  {:noreply, state}
end
```

### Sharding Strategy

```elixir
# Tenant sharding for scalability
defp get_tenant_shard(tenant_id) do
  shard_number = :erlang.phash2(tenant_id, @shard_count)
  :"tenants_#{shard_number}"
end

# Creates 10 tenant shards:
:tenants_0, :tenants_1, :tenants_2, ..., :tenants_9
```

### Data Persistence Flow

```elixir
# Immediate persistence for critical operations
def put_tenant(tenant) do
  shard = get_tenant_shard(tenant.id)
  :ets.insert(shard, {tenant.id, tenant})
  
  # Always persist immediately for data integrity
  JSONPersistence.persist_tenant(tenant)
  :ok
end

# Background archival for old data
def cleanup_old_entries do
  cutoff = DateTime.add(DateTime.utc_now(), -@entry_ttl, :second)
  
  # Archive old deployments to compressed files
  old_deployments = get_old_deployments(cutoff)
  Enum.each(old_deployments, &JSONPersistence.persist_deployment_archived/1)
  
  # Remove from ETS
  delete_old_ets_entries(cutoff)
end
```

---

## Application Types & Native Catalog

### BrokenRecord Native Applications (Premium)

The platform provides 6 native applications with premium licensing:

```elixir
@brokenrecord_apps %{
  "brokenrecord_database" => %{
    name: "BrokenRecord Database",
    base_cost: 17.00,
    features: ["High-performance Elixir/Ecto", "Built-in replication"]
  },
  
  "brokenrecord_fsm" => %{
    name: "BrokenRecord FSM Server", 
    base_cost: 28.00,  # Highest cost - most complex
    features: [
      "Visual workflow designer",
      "State persistence", 
      "Event-driven transitions",
      "Parallel execution",
      "Real-time monitoring"
    ],
    usage_metrics: ["state_transitions", "active_machines", "workflow_executions"]
  },
  
  "brokenrecord_chat" => %{
    name: "BrokenRecord Chat",
    base_cost: 22.00,
    features: ["Phoenix Channels", "Presence tracking", "Real-time messaging"]
  },
  
  "brokenrecord_queue" => %{
    name: "BrokenRecord Queue", 
    base_cost: 20.00,
    features: ["Distributed job processing", "Oban integration", "Dead letter queues"]
  },
  
  "brokenrecord_auth" => %{
    name: "BrokenRecord Auth",
    base_cost: 13.00,  # Lowest cost
    features: ["Multi-tenant auth", "JWT tokens", "Role-based access"]
  },
  
  "brokenrecord_analytics" => %{
    name: "BrokenRecord Analytics",
    base_cost: 33.00,
    features: ["Real-time metrics", "Business intelligence", "Custom dashboards"]
  }
}
```

### Third-Party Applications (Standard)

- **Databases**: PostgreSQL, MySQL, Redis, MongoDB
- **Load Balancers**: HAProxy, Nginx
- **Web Applications**: Any containerized app or API
- **Custom Containers**: Docker-compatible applications

### Application Deployment Flow

```elixir
# Native app deployment with licensing
def deploy_native_app(tenant_id, app_type, config) do
  with {:ok, app_config} <- NativeCatalog.get_app_config(app_type),
       {:ok, license_key} <- generate_license_key(tenant_id, app_type),
       {:ok, deployment} <- create_deployment(tenant_id, app_config, license_key) do
    
    # Start FSM for deployment
    {:ok, pid} = FlyStateMachine.start_link(deployment.id)
    GenStateMachine.cast(pid, :start_deployment)
    
    {:ok, deployment}
  end
end
```

---

## Security & Isolation

### Multi-Level Security

1. **Platform Level**: JWT authentication, RBAC
2. **Tenant Level**: Complete data isolation, resource quotas  
3. **Infrastructure Level**: Separate Fly.io apps and networks
4. **Application Level**: Container isolation, process boundaries

### Data Security

```elixir
# Tenant data access validation
def get_application(app_id, user_context) do
  with {:ok, app} <- ETSManager.get_application(app_id),
       {:ok, _member} <- verify_tenant_access(user_context.user_id, app.tenant_id) do
    {:ok, app}
  else
    _ -> {:error, :unauthorized}
  end
end

# All operations are tenant-scoped
def list_tenant_applications(tenant_id, user_context) do
  if user_context.current_tenant_id == tenant_id do
    ETSManager.list_tenant_applications(tenant_id)
  else
    {:error, :unauthorized}
  end
end
```

### Network Isolation

```elixir
# Fly.io private networking per tenant
def create_tenant_network(tenant_id) do
  network_config = %{
    name: "tenant-#{tenant_id}-network",
    region: "ord",
    ipv6_prefix: generate_ipv6_prefix(tenant_id)
  }
  
  FlyClient.create_network(network_config)
end
```

---

## Performance & Scalability

### Horizontal Scaling

```elixir
# ETS sharding across multiple shards
@shard_count 10
defp get_tenant_shard(tenant_id) do
  :erlang.phash2(tenant_id, @shard_count) |> then(&:"tenants_#{&1}")
end

# Phoenix node clustering
config :libcluster,
  topologies: [
    fly: [
      strategy: Cluster.Strategy.Fly,
      config: [
        app_name: "brokenrecord"
      ]
    ]
  ]
```

### Vertical Scaling

```elixir
# Automatic Fly.io machine scaling
def handle_high_cpu_usage(deployment) do
  current_config = deployment.fly_config
  
  scaled_config = %{current_config | 
    cpu_cores: current_config.cpu_cores * 2,
    memory_mb: current_config.memory_mb * 2
  }
  
  FlyClient.update_machine(deployment.machine_id, scaled_config)
end
```

### Memory Optimization

- **Aggressive ETS cleanup**: 10-second memory checks
- **Immediate JSON persistence**: No data loss during cleanup
- **Compressed archives**: Old data stored as `.json.gz`
- **Emergency cleanup**: Nuclear option for memory pressure

### Performance Metrics

```elixir
# Telemetry tracking
:telemetry.execute([:brokenrecord, :ets, :memory_usage], %{
  memory_bytes: total_memory,
  table_sizes: table_breakdown
})

:telemetry.execute([:brokenrecord, :deployment, :complete], %{
  duration: deployment_time,
  tenant_id: tenant_id,
  success: true
})
```

---

## Optimization Recommendations

### For Memory Optimization

1. **Increase shard count** for larger tenant bases (current: 10 shards)
2. **Implement LRU eviction** for less-active tenants
3. **Background compression** of JSON files older than 24 hours
4. **Separate read replicas** for analytics queries

### For Scalability

1. **Redis cluster** for session storage across Phoenix nodes
2. **Separate deployment workers** to reduce memory pressure
3. **Database migration** for high-volume analytics data
4. **CDN integration** for static assets and logs

### For Multi-Tenancy

1. **Subdomain routing** for better tenant isolation  
2. **Custom domains** for enterprise tenants
3. **Tenant-specific feature flags** for A/B testing
4. **Resource quotas by billing tier** for cost optimization

### For Development

1. **GraphQL API** for better frontend integration
2. **Webhook system** for third-party integrations  
3. **Audit logging** for compliance requirements
4. **Backup/restore utilities** for disaster recovery

---

## Conclusion

BrokenRecord implements a sophisticated multi-tenant architecture that balances simplicity with scalability. The dual-level user model (global users + tenant members), combined with aggressive ETS memory management and complete tenant isolation, provides a robust foundation for a modern PaaS platform.

The finite state machine approach to deployment management ensures reliability and observability, while the JSON persistence strategy maintains transparency and debuggability without database complexity.

This architecture can scale from hundreds to thousands of tenants while maintaining performance and isolation guarantees essential for enterprise multi-tenant applications.
