#!/usr/bin/env bash
# Verify the project's core claim: the planner behaves identically on native,
# wasm-gc and js.
#
# 1. run the portable test suite on each backend
# 2. generate the example plan with each backend's CLI
# 3. compare the three plans byte-for-byte
#
# Usable locally and in CI; needs `moon` on PATH and nothing else.

set -euo pipefail

cd "$(dirname "$0")/.."

PORTABLE_PKGS=(src/manifest src/ir src/plan src/wac_adapter src/exec_plan)
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "== fixtures =="
moon run src/tools/make_fixtures --target native -- examples >/dev/null 2>&1

for target in native wasm-gc js; do
  echo "== test ($target) =="
  moon test "${PORTABLE_PKGS[@]}" --target "$target" 2>&1 \
    | grep -E "Total tests|^Error" || true

  echo "== plan ($target) =="
  moon run src/cli --target "$target" -- plan examples/chain.json 2>/dev/null \
    | tr -d '\r' > "$OUT/plan-$target.json"
done

echo "== compare =="
if cmp -s "$OUT/plan-native.json" "$OUT/plan-wasm-gc.json" \
   && cmp -s "$OUT/plan-native.json" "$OUT/plan-js.json"; then
  echo "OK: all three backends produced byte-identical plans"
  echo "plan_hash: $(sed -n 's/.*"plan_hash":"\([^"]*\)".*/\1/p' "$OUT/plan-native.json")"
else
  echo "FAIL: plans differ"
  for f in "$OUT"/plan-*.json; do
    echo "--- $f"
    cat "$f"
  done
  exit 1
fi
