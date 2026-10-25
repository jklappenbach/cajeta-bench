# cajeta-bench

`dev.cajeta.bench` — the benchmark harness every repo in the Cajeta ecosystem
measures with: one `Benchmark` contract, one CSV schema (v2), one command line.
It is the `samples/profile` harness from the compiler repo, published as a
library the way `dev.cajeta.unit` is the test library
(cajeta `specs/benchmark-reference-spec.md` §3).

## Use it

```jsonc
// your bench project's cajeta.json
"settings": {
    "capabilities": ["filesystem", "clock", "env", "process"],
    "dependencies": { "dev.cajeta.bench": "0.1.0" },
    "build": { "entry-method": "my.bench.Main::main" }
},
"tasks": {
    "bench": {
        "actions": [
            { "action": "build", "flavor": { "base": "release", "opt": "O3", "cpu": "native" },
              "output-path": "build/my-bench", "id": "art" },
            { "action": "exec", "command": "${art.path}",
              "args": ["--run", "--out", "build/results.csv"] }
        ]
    }
}
```

The four capabilities are the library's own: it times trials (clock), writes
the CSVs and reads `/proc` and `/etc/os-release` (filesystem), reads
`CAJETA_BENCH_*` (env), and runs `nvidia-smi`, `hipconfig`, `vulkaninfo` and
`cmd /c ver` to record the driver and OS (process).

```cajeta
public final class Main {
    public static int32 main(String[] args) {
        ArrayList<Benchmark> b = heap ArrayList<Benchmark>();
        b.add(heap HashMapIntBench());
        return BenchMain.run(args, b);
    }
}
```

```cajeta
public class HashMapIntBench extends Benchmark {
    public String name() { return "hashmap-int-insert"; }
    public String area() { return "collection/hashmap"; }   // the catalog path
    public void setup() { ... }
    public void run(int32 iterations) { ... }
    public boolean checkResult() { ... }
}
```

## Command line

| | |
|---|---|
| `--list` | print each benchmark as `area/name [backend]` |
| `--run` | measure and write `results.csv` and `env.csv` beside it |
| `--area <path>` | select a catalog path, or a prefix of one (`collection` selects `collection/*`) |
| `--bench <name>` | select one benchmark by `name()` |
| `--out <path>` | results CSV (default `results.csv`); `<dir>/results.csv` puts env at `<dir>/env.csv` |

Exit status is 0 when every row is `ok` or `skipped`, 1 when any row `failed` or
was `invalid` (or the selection matched nothing), 2 on a usage error. A failing
benchmark never stops the run.

| Environment | |
|---|---|
| `CAJETA_BENCH_SMOKE=1` | warmup 1, trials 3, every row's notes tagged `smoke` (never published) |
| `CAJETA_BENCH_MACHINE` | the `machine` column; default the hostname, lowercased |
| `CAJETA_BENCH_RUN_ID` | the `run_id` column (`PROFILE_RUN_ID` still honored) |
| `CAJETA_BENCH_CAJETA_VERSION` | `language_version` of cajeta rows (`PROFILE_CAJETA_VERSION` still honored) |
| `CAJETA_BENCH_FLAGS` | the `flags` column of cajeta rows; default `--release -O3 -march=native` |

## The contract

Kept from profile: `name`, `area`, `backend`, `datasetInfo`, `warmupIters`,
`measuredIters`, `baselineNanos`, `inputSize`, `available`,
`variants`/`prepare`/`runVariant`, `supportsVariant`/`skipReason`,
`setup`/`run`/`teardown`/`checkResult`.

New in v2:

| Method | Default | Column |
|---|---|---|
| `machine()` | `CAJETA_BENCH_MACHINE`, else the hostname | `machine` |
| `unit()` | `""` | `throughput_unit` (`MB/s`, `tokens/s`) |
| `competitorNote()` | `""` | appended to `notes` |
| `platform()` | `"cajeta"` | `platform` (`cajeta-llm 0.9.0 hip`, `llama.cpp b6123 cuda`) |
| `model()` | `""` | `model` (`Llama-3.1-8B Q4_K_M sha256:…`) |

`os` and `driver` are detected, not declared: `os` is `Ubuntu 26.04`,
`Ubuntu 24.04 (WSL2)` or `Windows 11 (10.0.26100.4652)`; `driver` is
`NVIDIA 610.88 CUDA 13.3`, `ROCm 6.4.1-120` or `Vulkan radv Mesa 25.0.7` for a
row whose `backend()` is cuda/nvptx, hip/amdgpu or vulkan/spirv, detected once
per run, and empty on cpu rows.

**Failures.** A throw from `setup`, `run` or `runVariant` becomes a
`status=failed` row with the message in `notes`; the harness moves on to the
next variant or benchmark.

**Interleaved device rounds.** A benchmark whose `backend()` is not `cpu` and
that returns `hasCompetitor() == true` is measured in rounds of ours then the
competitor (`runCompetitor`), so both see the same clocks and thermal state.
Each side's median goes on its own row; the competitor row takes
`competitorLanguage()`, `competitorPlatform()` and `competitorVersion()`, and
both rows carry `interleaved` in `notes`.

## Schema v2

v1's 32 columns, unchanged and in order, then five: 37 columns,
`schema_version=2`.

```
schema_version,run_id,timestamp_unix,benchmark,area,dataset_name,dataset_bytes,dataset_sha256,input_size,language,language_version,library,library_version,flags,warmup,trials,min_ns,median_ns,mean_ns,p95_ns,throughput,throughput_unit,peak_rss_kb,cgroup_peak_kb,alloc_bytes,alloc_count,working_set_kb,status,check_ok,notes,variant,backend,machine,os,driver,model,platform
```

`status` is `ok`, `skipped`, `invalid` (the correctness check failed) or
`failed` (the benchmark threw).

`tools/verify-fidelity.py <results.csv>` checks a file of either schema
(header shape, per-row version and status, and on v2 a machine and platform on
every row), then the benchmark-fidelity outcomes for whichever of their
benchmarks the file holds. `--require-suite` makes an absent one a failure,
`--no-smoke` rejects smoke rows.

## Develop

```sh
./run-tests.sh                 # build the .cja, compile the suite against it, run
./scripts/ci-checks.sh         # the suite plus tools/test-verify-fidelity.sh
cajeta install                 # into ~/.olla/dev.cajeta.bench/<version>/
```

The suite runs on cajeta-unit; `run-tests.sh` resolves it from a sibling
checkout, `~/.olla`, or Olla.

## License

Apache-2.0.
