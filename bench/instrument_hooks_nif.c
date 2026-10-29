#include <erl_nif.h>
#include <string.h>
#include <unistd.h>

#include "core.h"

static InstrumentHooks *hooks = NULL;

static ERL_NIF_TERM make_result(ErlNifEnv *env, uint8_t status) {
  if (status == 0) {
    return enif_make_atom(env, "ok");
  }
  return enif_make_tuple2(env, enif_make_atom(env, "error"),
                          enif_make_uint(env, status));
}

static int read_string(ErlNifEnv *env, ERL_NIF_TERM term, char *buffer,
                       size_t size) {
  ErlNifBinary binary;
  if (!enif_inspect_binary(env, term, &binary) || binary.size >= size) {
    return 0;
  }
  memcpy(buffer, binary.data, binary.size);
  buffer[binary.size] = '\0';
  return 1;
}

static ERL_NIF_TERM is_instrumented(ErlNifEnv *env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  return enif_make_atom(
      env, instrument_hooks_is_instrumented(hooks) ? "true" : "false");
}

static ERL_NIF_TERM set_integration(ErlNifEnv *env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  char name[256];
  char version[64];
  if (!read_string(env, argv[0], name, sizeof(name)) ||
      !read_string(env, argv[1], version, sizeof(version))) {
    return enif_make_badarg(env);
  }
  return make_result(env,
                     instrument_hooks_set_integration(hooks, name, version));
}

static ERL_NIF_TERM start_benchmark(ErlNifEnv *env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  return make_result(env, instrument_hooks_start_benchmark(hooks));
}

static ERL_NIF_TERM stop_benchmark(ErlNifEnv *env, int argc,
                                   const ERL_NIF_TERM argv[]) {
  return make_result(env, instrument_hooks_stop_benchmark(hooks));
}

static ERL_NIF_TERM set_executed_benchmark(ErlNifEnv *env, int argc,
                                           const ERL_NIF_TERM argv[]) {
  char uri[1024];
  if (!read_string(env, argv[0], uri, sizeof(uri))) {
    return enif_make_badarg(env);
  }
  return make_result(env, instrument_hooks_set_executed_benchmark(
                              hooks, (int32_t)getpid(), uri));
}

static ERL_NIF_TERM add_benchmark_timestamps(ErlNifEnv *env, int argc,
                                             const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 start;
  ErlNifUInt64 end;
  if (!enif_get_uint64(env, argv[0], &start) ||
      !enif_get_uint64(env, argv[1], &end)) {
    return enif_make_badarg(env);
  }
  int32_t pid = (int32_t)getpid();
  uint8_t status = instrument_hooks_add_marker(
      hooks, pid, MARKER_TYPE_BENCHMARK_START, start);
  if (status == 0) {
    status = instrument_hooks_add_marker(hooks, pid,
                                         MARKER_TYPE_BENCHMARK_END, end);
  }
  return make_result(env, status);
}

static ERL_NIF_TERM current_timestamp(ErlNifEnv *env, int argc,
                                      const ERL_NIF_TERM argv[]) {
  return enif_make_uint64(env, instrument_hooks_current_timestamp());
}

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  hooks = instrument_hooks_init();
  return hooks == NULL ? 1 : 0;
}

static void unload(ErlNifEnv *env, void *priv_data) {
  instrument_hooks_deinit(hooks);
  hooks = NULL;
}

static ErlNifFunc nif_funcs[] = {
    {"is_instrumented", 0, is_instrumented, 0},
    {"set_integration", 2, set_integration, 0},
    {"start_benchmark", 0, start_benchmark, 0},
    {"stop_benchmark", 0, stop_benchmark, 0},
    {"set_executed_benchmark", 1, set_executed_benchmark, 0},
    {"add_benchmark_timestamps", 2, add_benchmark_timestamps, 0},
    {"current_timestamp", 0, current_timestamp, 0},
};

ERL_NIF_INIT(Elixir.Flagsmith.Bench.InstrumentHooks, nif_funcs, load, NULL,
             NULL, unload)
