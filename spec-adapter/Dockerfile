# Builds the SDK from source with the adapter for the Flagsmith SDK behavioural spec.
# Build from the repository root: docker build -f spec-adapter/Dockerfile .
FROM elixir:1.15-slim

# The SDK's HTTP client (httpc) loads the OS CA certificates on every request.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /sdk
COPY mix.exs mix.lock ./
COPY lib ./lib
COPY spec-adapter/mix.exs spec-adapter/mix.lock ./spec-adapter/
COPY spec-adapter/lib ./spec-adapter/lib

WORKDIR /sdk/spec-adapter
RUN mix deps.get --only prod && mix compile

ENV PORT=8080
EXPOSE 8080
CMD ["mix", "run", "--no-halt"]
