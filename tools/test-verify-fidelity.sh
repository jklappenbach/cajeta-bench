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

[[ "$fails" -eq 0 ]] && echo "verify-fidelity: all cases pass" || { echo "verify-fidelity: $fails case(s) failed"; exit 1; }
