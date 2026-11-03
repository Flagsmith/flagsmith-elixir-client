SDK_BENCHMARKS := test/support/sdk-benchmarks
INSTRUMENT_HOOKS := bench/instrument-hooks
INSTRUMENT_HOOKS_NIF := _build/codspeed/instrument_hooks_nif.so

ERTS_INCLUDE_DIR = $(shell erl -noshell -eval 'io:format("~ts/erts-~ts/include", [code:root_dir(), erlang:system_info(version)]), halt().')
NIF_CFLAGS := -std=c11 -O3 -g -fPIC -Wno-format -Wno-format-security -Wno-unused-but-set-variable -Wno-unused-const-variable -Wno-type-limits -Wno-uninitialized -Wno-incompatible-pointer-types
ifeq ($(shell uname -s),Darwin)
NIF_LDFLAGS := -dynamiclib -undefined dynamic_lookup
else
NIF_LDFLAGS := -shared
BENCHMARK_ERL_FLAGS := +JPperf true
endif

$(SDK_BENCHMARKS)/environments:
	git submodule update --init -- $(SDK_BENCHMARKS)

$(INSTRUMENT_HOOKS)/dist/core.c:
	git submodule update --init -- $(INSTRUMENT_HOOKS)

$(INSTRUMENT_HOOKS_NIF): bench/instrument_hooks_nif.c | $(INSTRUMENT_HOOKS)/dist/core.c
	mkdir -p $(@D)
	$(CC) $(NIF_CFLAGS) -I$(ERTS_INCLUDE_DIR) -I$(INSTRUMENT_HOOKS)/includes $(NIF_LDFLAGS) -o $@ $< $(INSTRUMENT_HOOKS)/dist/core.c

.PHONY: benchmark-build
benchmark-build: $(INSTRUMENT_HOOKS_NIF) | $(SDK_BENCHMARKS)/environments
	mix deps.get
	mix compile

.PHONY: benchmark
benchmark: benchmark-build
	SDK_BENCHMARKS_ENVIRONMENTS_DIR=$(abspath $(SDK_BENCHMARKS)/environments) \
	INSTRUMENT_HOOKS_NIF=$(abspath $(basename $(INSTRUMENT_HOOKS_NIF))) \
	ERL_FLAGS="$(BENCHMARK_ERL_FLAGS)" \
	codspeed run --mode walltime -- mix run --no-compile --no-deps-check bench/sdk_benchmark.exs
