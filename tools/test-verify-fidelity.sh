#!/usr/bin/env bash
# Pins verify-fidelity.py's schema handling on small fixtures: both schemas
# and every v1 header shape accepted; the v2 row rules, the status set, an
# unknown header and --no-smoke rejected.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/verify-fidelity.py"
fx="$here/fixtures"
fails=0

expect() {   # expect <exit-code> <args...>
    local want="$1"; shift
    local got=0
    python3 "$gate" "$@" >/dev/null 2>&1 || got=$?
    if [[ "$got" == "$want" ]]; then
        echo "  ok    exit $got  $*"
    else
        echo "  FAIL  exit $got (wanted $want)  $*"
        fails=$((fails + 1))
    fi
}

expect 0 "$fx/v1-32.csv"
expect 0 "$fx/v1-31.csv"
expect 0 "$fx/v2-ok.csv"
expect 0 "$fx/v2-smoke.csv"
expect 1 --no-smoke "$fx/v2-smoke.csv"
expect 0 --no-smoke "$fx/v2-ok.csv"
expect 1 "$fx/v2-no-machine.csv"
expect 1 "$fx/v2-wrong-version.csv"
expect 1 "$fx/v2-short-header.csv"
expect 1 "$fx/v1-failed-status.csv"
expect 1 --require-suite "$fx/v2-ok.csv"
expect 2 --bogus "$fx/v2-ok.csv"
# 0.1.1: matmul is the catalog id math/matmul, never the bare name.
expect 0 "$fx/v2-xpu-matmul.csv"
expect 1 "$fx/v2-math-matmul-slow.csv"
expect 0 "$fx/v2-math-matmul-ok-beside-xpu.csv"
# 0.1.1: an ExternalBenchmark row (notes tag `external`) has no in-process
# allocation count; any other measured cajeta row still must.
expect 0 "$fx/v2-external-no-alloc.csv"
expect 1 "$fx/v2-alloc-missing.csv"
# 0.1.3: RFC 4180 quoted fields (commas, doubled quotes, a newline, UTF-8)
# are one field each; the row keeps its 37 columns and its machine/platform.
expect 0 "$fx/v2-quoted-fields.csv"
expect 0 --no-smoke "$fx/v2-quoted-fields.csv"

# 0.1.5: absolute ceilings are keyed by machine (relative checks are not).
# Phoenix's smoke medians pass on Phoenix's table and fail on Proton's; a
# machine with no table skips the absolute checks; v1 (no machine column)
# reads the Proton table the ceilings were set on.
expect 0 "$fx/v2-phoenix-smoke.csv"
expect 1 "$fx/v2-proton-slow.csv"
expect 0 "$fx/v2-unknown-machine.csv"
expect 1 "$fx/v2-phoenix-too-slow.csv"
expect 0 "$fx/v1-32.csv"

# tools/csv-column.py: the CSV-aware reader smoke scripts use instead of
# `awk -F,` (0.1.3 quotes free-text fields, so a comma splits nothing).
col() { python3 "$here/csv-column.py" "$@"; }
want() {   # want <expected> <args...>
    local exp="$1"; shift
    local got
    got="$(col "$@" 2>&1)" || true
    if [[ "$got" == "$exp" ]]; then
        echo "  ok    csv-column $*"
    else
        echo "  FAIL  csv-column $*: got <$got> wanted <$exp>"
        fails=$((fails + 1))
    fi
}
want 'cajeta-llm 0.9.0 — hip, gfx1151' "$fx/v2-quoted-fields.csv" platform
want 'Débian, 12' "$fx/v2-quoted-fields.csv" os
want '37' --count-columns "$fx/v2-quoted-fields.csv"
want $'ok\tfailed' "$fx/v2-ok.csv" status --join-tab
want 'triad' "$fx/v2-ok.csv" benchmark --where status=failed
want 'csv-column: no column nope (have: schema_version, run_id, …)' "$fx/v2-ok.csv" nope

[[ "$fails" -eq 0 ]] && echo "verify-fidelity: all cases pass" || { echo "verify-fidelity: $fails case(s) failed"; exit 1; }
