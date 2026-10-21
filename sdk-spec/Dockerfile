# Runs this SDK, built from source, under the Flagsmith SDK behavioural spec.
# docker build -f sdk-spec/Dockerfile --build-context harness=<sdk-spec>/harness/elixir .
FROM docker.io/library/elixir:1.15-slim

# The SDK's HTTP client (httpc) loads the OS CA certificates on every request.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /sdk
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile
COPY lib ./lib
RUN mix compile

COPY --from=harness harness.exs /harness/harness.exs
COPY sdk-spec/steps.exs ./sdk-spec/steps.exs

ENTRYPOINT ["mix", "run", "--no-compile", "--no-deps-check", "/harness/harness.exs", "sdk-spec/steps.exs"]
