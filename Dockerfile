# BrokenRecord PaaS - Production Dockerfile for Fly.io
# Multi-stage build for optimized production image

# Build stage
FROM hexpm/elixir:1.18.0-erlang-27.0.1-debian-bookworm-20231009-slim as build

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl nodejs npm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set up work directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets and lib directory for Tailwind content scanning
COPY assets assets
COPY priv priv
COPY lib lib

# Setup and compile assets in the container (lib is now available for content scanning)
RUN mix assets.setup
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Copy runtime files and health check script
COPY config/runtime.exs config/
COPY bin/health_check /app/bin/health_check

# Create the release
RUN mix release

# Runtime stage
FROM debian:bookworm-20231009-slim as runtime

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Create app user
RUN useradd --create-home app
WORKDIR /app

# Set ownership
RUN chown app:app /app

USER app

# Copy the release (use explicit prod path since MIX_ENV isn't available in runtime stage)
COPY --from=build --chown=app:app /app/_build/prod/rel/fsm_app ./

# Create data directory for JSON storage
RUN mkdir -p /app/data/system/users /app/data/tenants

# Copy health check script
COPY --from=build --chown=app:app /app/bin/health_check /app/bin/health_check
RUN chmod +x /app/bin/health_check

# Expose port
EXPOSE 8080

# Run the Phoenix server
CMD ["/app/bin/fsm_app", "start"]
