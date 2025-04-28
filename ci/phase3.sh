#!/usr/bin/env bash
# ci/phase3.sh – Phase 3 “hello-world” SWE-Agent run
set -euo pipefail

# ────────────────────────────────  Config & helpers  ────────────────────────────────
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' missing"; exit 1; }; }

: "${PYBIN_DIR:=$(dirname "$(which python)")}"
SCRIPT_DIR="$(pwd)"
: "${DEMO_DIR:=/tmp/demo}"
: "${FOUNDRY_SEARCH_PATHS:=${FOUNDRY_DIR:-}:/home/runner/.config/.foundry:$HOME/.config/.foundry}"

require_cmd docker                                  # only binary guaranteed pre-installs
python -m pip install --quiet 'sweagent==1.0.1'     # pin schema version for reproducibility

# ────────────────────────────────  Write / validate swe.yaml  ───────────────────────
cat > swe.yaml <<'YAML'
# Minimal RunSingleConfig (SWE-Agent 1.0.x)
problem_statement:
  text: Fix failing tests

agent:
  model:
    name: gpt-4o-mini

actions:
  apply_patch_locally: true
  open_pr: false

env:
  repo:
    path: .
  deployment:
    type: local
YAML
echo "✓ Created swe.yaml"

echo "--- Validating swe.yaml (non-sudo python) ---"
"$PYBIN_DIR/python" - <<'PY'
from importlib import import_module
import yaml, sys
try:
    RunSingleConfig = import_module("sweagent.config").RunSingleConfig
    RunSingleConfig.model_validate(yaml.safe_load(open("swe.yaml")))
    print("✓ swe.yaml validation passed")
except ModuleNotFoundError as e:
    print(f"⚠️  swe.yaml validation skipped ({e})\n   → Did sweagent install correctly?")
except Exception as e:
    print(f"❌ swe.yaml validation failed: {e}", file=sys.stderr); sys.exit(1)
PY

# ────────────────────────────────  Ensure Foundry in PATH  ─────────────────────────
IFS=':' read -ra FOUND_CANDIDATES <<<"$FOUNDRY_SEARCH_PATHS"
for dir in "${FOUND_CANDIDATES[@]}"; do
  [[ -n "$dir" && -x "$dir/bin/forge" ]] && { export PATH="$dir/bin:$PATH"; echo "✓ Found forge in: $dir/bin"; break; }
done
require_cmd forge
forge_bin="$(command -v forge)"
echo "Using forge from: $forge_bin"
echo "Foundry version: $(forge --version)"

# ────────────────────────────────  Build red-bar demo repo  ────────────────────────
rm -rf "$DEMO_DIR"; mkdir -p "$DEMO_DIR"; cd "$DEMO_DIR"
git init -q

cat > Greeter.sol <<'SOL'
pragma solidity ^0.8.26;
contract Greeter {
  string private greeting = "hello";
  function greet() external view returns (string memory) {
    return greeting;
  }
}
SOL

cat > Greeter.t.sol <<'SOLTEST'
pragma solidity ^0.8.26;
import "forge-std/Test.sol";
import "./Greeter.sol";
contract GreeterTest is Test {
  Greeter g;
  function setUp() public { g = new Greeter(); }
  function testGreetingFails() public { assertEq(g.greet(), "HELLO"); }
}
SOLTEST

if forge test -q 2>/dev/null; then
  echo "❌ tests unexpectedly green"; exit 1
else
  echo "✓ baseline red"
fi

# ────────────────────────────────  Run SWE-Agent  ─────────────────────────────────
TS=$(date +%Y%m%dT%H%M%S)
LOGFILE="${DEMO_DIR}/run_${TS}.log"
PATCH_TAR="${DEMO_DIR}/patch.tar"

pushd "$DEMO_DIR" >/dev/null
SWE_CMD="$PYBIN_DIR/python -m sweagent run --config ${SCRIPT_DIR}/swe.yaml --output_dir ${SCRIPT_DIR}"
eval "$SWE_CMD" 2>&1 | tee "$LOGFILE"
popd >/dev/null

[[ -s "$PATCH_TAR" ]] || { echo "❌ SWE-Agent failed or patch missing"; exit 1; }
echo "✓ Agent produced $PATCH_TAR"

# ────────────────────────────────  Apply patch with guard-rails  ──────────────────
cd "$SCRIPT_DIR"
tar -xf "$PATCH_TAR"

mapfile -d '' -t patch_files < <(find . -maxdepth 1 -name '*.[pd][ia][ft]' -print0)
[[ ${#patch_files[@]} -ne 0 ]] || { echo "❌ No patch files found"; exit 1; }

TOTAL_LOC_INS=0 TOTAL_LOC_DEL=0
STATS_DIR=".patch_stats"; mkdir -p "$STATS_DIR"
trap 'rm -rf "$STATS_DIR"' EXIT

for p in "${patch_files[@]}"; do
  echo "--- Validating patch: $p ---"
  size=$(wc -c <"$p")
  (( size < 100000 )) || { echo "💥 $p too large ($size bytes)"; exit 1; }
  echo "  ✓ Size check passed ($size bytes)"

  patch_stats=$(git apply --numstat "$p") || { echo "❌ git apply --numstat failed"; exit 1; }
  printf '%s\n' "$patch_stats" >"$STATS_DIR/$(basename "$p").stats"

  loc_ins=$(awk '$1!="-" {i+=$1} END{print i+0}' <<<"$patch_stats")
  loc_del=$(awk '$2!="-" {d+=$2} END{print d+0}' <<<"$patch_stats")
  total_loc=$(( loc_ins + loc_del ))
  (( total_loc <= 2000 )) || { echo "💥 $p changes $total_loc LOC"; exit 1; }
  echo "  ✓ LOC check passed (+$loc_ins / -$loc_del = $total_loc)"

  TOTAL_LOC_INS=$(( TOTAL_LOC_INS + loc_ins ))
  TOTAL_LOC_DEL=$(( TOTAL_LOC_DEL + loc_del ))

  echo "--- Applying: $p ---"
  git apply "$p" || { echo "❌ git apply failed"; git diff; exit 1; }
  echo "  ✓ Applied"
done

# ────────────────────────────────  Summary & test  ───────────────────────────────
{
  echo "### Phase 3 Summary"
  echo "- **LOC Changed:** +$TOTAL_LOC_INS / -$TOTAL_LOC_DEL"
  cost=$(grep -E 'Estimated cost: \$[0-9.]+' "$LOGFILE" | sed -E 's/.*\$(.*)/\1/' || true)
  [[ -n "$cost" ]] && echo "- Estimated Cost: $cost"
} >> "$GITHUB_STEP_SUMMARY"

forge test -q || { echo "❌ tests still failing"; git diff; exit 1; }
echo "✓ tests green after patch"

# ────────────────────────────────  Slither static-analysis  ──────────────────────
SLITHER_IMG="ghcr.io/crytic/slither:latest-slim"
docker pull --quiet "$SLITHER_IMG" || true
echo "--- Running Slither ---"
docker run --pull=never --rm -v "$PWD":/src "$SLITHER_IMG" \
  slither /src --exclude-dependencies --disable-color > slither.txt || \
  echo "Slither exited non-zero → continuing"
echo "✓ Slither analysis complete"

# ────────────────────────────────  Evidence bundle  ─────────────────────────────
mkdir -p .evidence
cp "$STATS_DIR"/* .evidence/ 2>/dev/null || true
mv "$PATCH_TAR" "$LOGFILE" slither.txt .evidence/

{
  echo "Evidence Bundle Contents:"
  echo "------------------------"
  find .evidence -type f | sort
  echo "------------------------"
  echo "Total files: $(find .evidence -type f | wc -l)"
} > .evidence/manifest.txt

TB="evidence_${TS}.tgz"
tar -czf "$TB" .evidence
echo "bundle_name=$TB" >> "$GITHUB_OUTPUT"

echo "✅ Phase 3 complete"
# macOS tip: `brew install coreutils` for GNU versions of utilities