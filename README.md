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
    "dependencies": { "dev.cajeta.bench": "0.1.7" },
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
| `--variant <label>` | select one variant label of the selected benchmarks |
| `--backend <name>` | select the variants that run on one backend (`cpu`, `cuda`, `hip`, `vulkan`), whatever their labels |
| `--verbose` | with `--list`: every variant, the backend it runs on, and skip reasons |
| `--out <path>` | results CSV (default `results.csv`); `<dir>/results.csv` puts env at `<dir>/env.csv`. A missing directory is created; one that cannot be (a file in the way) is exit 2 before anything is measured, naming the path |

Exit status is 0 when every row is `ok` or `skipped`, 1 when any row `failed` or
was `invalid` (or the selection matched nothing), 2 on a usage error or an
unwritable `--out`. "wrote" is printed only after the write happened. A failing
benchmark never stops the run.

| Environment | |
|---|---|
| `CAJETA_BENCH_SMOKE=1` | warmup 1, trials 3, every row's notes tagged `smoke` (never published) |
| `CAJETA_BENCH_MACHINE` | the `machine` column; default the hostname, lowercased |
| `CAJETA_BENCH_RUN_ID` | the `run_id` column (`PROFILE_RUN_ID` still honored) |
| `CAJETA_BENCH_CAJETA_VERSION` | `language_version` of cajeta rows (`PROFILE_CAJETA_VERSION` still honored). Unset: `cajeta --version` of the compiler on PATH (the runtime has no version API), which under `cajeta bench` is the compiler that built the binary; empty when none is on PATH |
| `CAJETA_BENCH_NO_GPU=1` | run no driver probe (nvidia-smi, hipconfig, vulkaninfo): `driver` stays empty and non-cpu rows' notes say `driver: not probed`. Without it a probe runs once per driver family, only for a measured non-cpu row, never for a cpu, skipped or failed one |
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
| `unit()` | `""` | `throughput_unit` (`MB/s`, `tokens/s`); empty on a skipped row, which measured nothing |
| `flags()` | `""` | `flags` ("" on a cajeta row = `CAJETA_BENCH_FLAGS`) |
| `competitorNote()` | `""` | appended to `notes` |
| `platform()` | `"cajeta"` | `platform` (`cajeta-llm 0.9.0 hip`, `llama.cpp b6123 cuda`) |
| `model()` | `""` | `model` (`Llama-3.1-8B Q4_K_M sha256:…`) |
| `language()`, `languageVersion()` | `cajeta`, `""` | `language`, `language_version` ("" on a cajeta row = the compiler version) |
| `unavailableReason()` | `unavailable (dataset not configured or not fetched)` | `notes` of the skipped row when `available()` is false |
| `library()`, `libraryVersion()` | `""` | `library`, `library_version` (`dev.cajeta.ml`, `0.10.6`) |
| `backendFor(variant)` | `backend()` | `backend` and `driver` of that variant's row; decides interleaving |
| `skipReasonFor(variant)` | `skipReason()` | `notes` of that variant's skipped row |
| `languageFor`, `languageVersionFor`, `platformFor`, `libraryFor`, `libraryVersionFor`, `flagsFor`, `noteFor` `(variant)` | the whole-benchmark hook | that variant's identity columns and notes |
| `variantLabel(variant)` | the variant | the `variant` column (`primavera@64` written as `64 connections`) |
| `finishVariant(variant)` | nothing | called after each measured variant, even one that threw |

A benchmark can emit rows for several platforms (primavera, Spring Boot,
FastAPI) by returning one variant per platform and answering the `*For`
hooks. Variant keys must be unique within one benchmark, not across
benchmarks; `--variant` selects by key.

A variant's label says what is measured and `backendFor(variant)` says where
it runs, so the two filters answer different questions. `--backend cuda` runs
every variant that lands on the GPU, whether it is labelled `device`, `n4096`
or a dataset name, and `--backend cpu` runs the rest. Given together, a variant
must pass both.

**Figures measured inside the work.** A trial may call
`reportedNanos(ns)` (exec to first 200, a build without its clean): it
replaces that trial's wall-clock time and `notes` say `reported`. It may call
`reportedThroughput(value, unit)` (a load generator's req/s): the row's
throughput is the median reported value with that unit, in preference to the
`inputSize()` derivation. It may call `reportedStats(min, median, mean, p95)`
(a load generator's own latency percentiles, ns): the row's four time columns
become the median over trials of each, and `notes` say `reported-stats`; once
in the trial set is enough. All three are cleared before every warmup and
trial. `isWarmup()` is true during warmups (to shorten a load generator's own
warm-up), false in trials and in the untimed allocation-count run.

**Order per variant.** `supportsVariant(v)`, then `prepare(v)`, then
`available()` and the interleave decision, so both may read what `prepare` set.
An unavailable variant is a skipped row with `unavailableReason()`; a
benchmark whose `setup()` throws while `available()` is false is skipped, not
failed.

**Baselines.** A `baselineNanos()` at or above a trial's measured time clamps
that trial to 0, writes `baseline>=measured` in `notes`, and makes the row
`invalid` unless `allowZeroAfterBaseline()` returns true.

**env.csv extras.** `envExtra(key, value)`, called from `setup()`, adds a line
to `env.csv` (the last value for a key wins): toolchain versions, a load
generator's flags.

**Ports.** `Ports.free(n)` returns `n` distinct free TCP ports above the
kernel's ephemeral range (`Ports.ephemeralRange()`, from
`/proc/sys/net/ipv4/ip_local_port_range`, default 32768-60999), where a load
generator's client sockets cannot take them; successive calls walk forward.
`Ports.freeIn(n, low, high)` does the same inside a range you choose, for a run
that must keep its services where a firewall rule or another tool expects them;
it throws when the range has fewer than `n` free.

`throughput` is filled when `inputSize()` is not -1: `inputSize / median
seconds`, scaled by the unit's prefix, three decimals, labelled `unit()`. Give
`inputSize()` raw (bytes, ops, items); a K, M, G or T prefix divides by 1024^n
on a byte unit (`MB/s` is 2^20 bytes a second, as the competitor drivers
write) and by 1000^n otherwise (`Mop/s`, `GFLOP/s`); `items/s` is unscaled. `timestamp_unix` is the
wall-clock second each row was made.

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

## External commands

`ExternalBenchmark` times a child process per trial with the harness clock:
compiles, start-up, a load generator such as `oha` against a server.

```cajeta
ExternalBenchmark e = heap ExternalBenchmark();
e.describe("hello-start", "toolchain/startup");
e.command(#argv);                 // String[]; argv[0] resolved on PATH
e.environment(#entries);          // optional "KEY=VALUE" list, replaces the env
e.workingDirectory("build");      // optional
e.iterations(3, 20);              // warmup, trials
e.timeoutMillis(60000);           // optional
```

Subclass it to vary the command per variant (`argvFor(variant)`) or to check
output (`checkResult()` reading `stdout()`; test `lastExitCode == 0` first).
A non-zero exit, a program that cannot start, or a timeout is a `failed` row
with the reason in `notes`. `peak_rss_kb` is the child's peak resident set from
`wait4` rusage, as GNU time reports it, taken in one extra untimed run under
`/usr/bin/time -f %M` (the runtime's own reaping uses `waitpid` and exposes no
rusage; `/proc` sampling misses short children). Without `/usr/bin/time` it is
-1. When that extra run is costly, a cold compile say, `rssFromTimedRuns(true)`
takes the peak from the timed runs instead, each under GNU time, and makes no
extra run; the timed region then includes GNU time's own fork and wait.
`alloc_bytes` and `working_set_kb` are -1, since they describe the waiting
harness, and `notes` carry `external`, which the fidelity gate's allocation
check honors.

## Services

`ServiceBenchmark` (an `ExternalBenchmark`) measures a long-running service:
per variant it starts the service (`service(#argv)`, `serviceDirectory`,
`serviceEnvironment`, `serviceLog`), waits for it (`readyOnPort(port)` or
`readyOnUrl(port, "/health", 200)`, `readyTimeoutMillis`), runs the measured
phase once per warmup and trial, and stops it.

- The phase is the `command(#argv)` (say oha), whose stdout `checkResult`
  reads through `stdout()`, or, with no command, a subclass's
  `runPhase(variant)`, which may call `reportedNanos` / `reportedThroughput`.
- `peak_rss_kb` is the service's VmHWM from `/proc/<pid>/status`, summed over
  it and its descendants, sampled every `samplingMillis` while the phase runs
  and after each phase. No extra run is made for it. Linux only (-1 elsewhere).
  A subclass whose row should report the phase command's peak instead overrides
  `measuredPeakRssKb()` to return `childPeakRssKb()`, the measurement
  `ExternalBenchmark` makes.
- The stop is SIGTERM to the recorded PID, then SIGKILL after
  `stopTimeoutMillis`; never by pattern. `lastStopSignal` says which.
- A service that dies before it is ready, or is not ready in time, fails the
  row (the service is stopped); the log's last line is in `notes`.
- `relaunchEachTrial(true)` starts and stops the service in every trial; with
  no phase command the trial's time is exec to ready (`reported`).
- `readyPollMillis(ms)` sets the readiness loop's wait between probes
  (default 5).
- `CAJETA_BENCH_TRACE=1` prints each step (start, ready, phase, stop).

Readiness uses `cajeta.io.net`, so the library declares the `network`
capability. POSIX only (the service runs under `/bin/sh -c 'exec …'` so its
output goes to the log and its PID stays its own).

## Schema v2

v1's 32 columns, unchanged and in order, then five: 37 columns,
`schema_version=2`.

```
schema_version,run_id,timestamp_unix,benchmark,area,dataset_name,dataset_bytes,dataset_sha256,input_size,language,language_version,library,library_version,flags,warmup,trials,min_ns,median_ns,mean_ns,p95_ns,throughput,throughput_unit,peak_rss_kb,cgroup_peak_kb,alloc_bytes,alloc_count,working_set_kb,status,check_ok,notes,variant,backend,machine,os,driver,model,platform
```

`status` is `ok`, `skipped`, `invalid` (the correctness check failed) or
`failed` (the benchmark threw).

Fields are RFC 4180: one containing a comma, a double quote, CR or LF is
quoted, with inner quotes doubled; numbers stay bare. The file is UTF-8, and
0.1.3 fixed a bug where a field holding a multi-byte character was scanned
and copied short, so a comma past an em dash went unquoted and shifted the
columns. `env.csv` values follow the same rule.

**Reading a column in a smoke script.** Because free text is quoted,
`awk -F,` and `cut -d,` split fields such as `notes` and read the wrong
column. Use `tools/csv-column.py`:

```sh
python3 tools/csv-column.py results.csv status --where benchmark=decode
python3 tools/csv-column.py --count-columns results.csv        # 37
```

or the one-liner it documents:
`python3 -c 'import csv,sys; [print(r[sys.argv[2]]) for r in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8"))]' results.csv status`.

`tools/verify-fidelity.py <results.csv>` checks a file of either schema
(header shape, per-row version and status, and on v2 a machine and platform on
every row), then the benchmark-fidelity outcomes for whichever of their
benchmarks the file holds. `--require-suite` makes an absent one a failure,
`--no-smoke` rejects smoke rows. The absolute checks (the matmul band, the
SIMD ceilings) are keyed by the row's `machine` in the script's `CEILINGS`
table; a machine without a table is skipped, and v1 rows (no machine column)
read Proton's. Phoenix's ceilings are provisional, 2x the 2026-10-25 smoke
medians. The relative and structural checks are machine-independent.

## Develop

```sh
./run-tests.sh                 # build the .cja, compile the suite against it, run
CAJETA_UNIT_FILTER=ServiceTests ./run-tests.sh   # a subset
BENCH_TEST_TIMEOUT=120 ./run-tests.sh            # stop the test binary after 120 s (default 600)
./scripts/ci-checks.sh         # the suite plus tools/test-verify-fidelity.sh
cajeta install                 # into ~/.olla/dev.cajeta.bench/<version>/
```

The suite runs on cajeta-unit; `run-tests.sh` resolves it from a sibling
checkout, `~/.olla`, or Olla.

## License

Apache-2.0.
