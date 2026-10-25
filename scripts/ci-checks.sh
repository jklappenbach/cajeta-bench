#!/usr/bin/env bash
# The full CI check chain: the cajeta-unit suite, then the fidelity gate's
# fixture tests. release.yml's `test-command` points here so the list lives in
# one place.
set -euo pipefail
cd "$(dirname "$0")/.."

./run-tests.sh
./tools/test-verify-fidelity.sh
