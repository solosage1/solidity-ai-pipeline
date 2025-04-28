#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Phase 3 – Hello-World SWE-Agent Run
#
# This script is invoked by GitHub Actions via:
#   sudo --preserve-env=OPENAI_API_KEY,PYBIN_DIR bash ci/phase3.sh
#
# Environment Variables
# ────────────────────────────────────────────────────────────────
#   PYBIN_DIR             Path to python bin dir (default: dirname "which python")
#   DEMO_DIR              Directory for demo repository (default: /tmp/demo)
#   FOUNDRY_DIR           Optional path to Foundry installation
#   FOUNDRY_SEARCH_PATHS  Colon-separated list of dirs to search for Foundry
#   OPENAI_API_KEY        Required for SWE-Agent operation
# ────────────────────────────────────────────────────────────────

# ---------- helpers -----------------------------------------------------------

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' missing"; exit 1; }; }

# ---------- configuration -----------------------------------------------------

: "${PYBIN_DIR:=$(dirname "$(which python)")}"
SCRIPT_DIR="$(pwd)"
: "${DEMO_DIR:=/tmp/demo}"
: "${FOUNDRY_SEARCH_PATHS:=${FOUNDRY_DIR:-}:/home/runner/.config/.foundry:$HOME/.config/.foundry}"

require_cmd docker   # only binary guaranteed before installs

# ---------- create & validate swe.yaml (non-sudo context) --------------------

{
  set -euo pipefail
  cat > swe.yaml <<YAML
# Minimal RunSingleConfig
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
    path: "."          # relative path avoids chown race
  deployment:
    type: local        # default & supported
YAML

  echo "✓ Created swe.yaml"

  echo "--- Validating swe.yaml (non-sudo python) ---"
  "$PYBIN_DIR/python" - <<'PY'
from importlib import import_module
import yaml, sys
try:
    RunSingleConfig = import_module("sweagent.config").RunSingleConfig
    RunSingleConfig.model_validate(yaml.safe_load(open('swe.yaml')))
    print("✓ swe.yaml validation passed")
except ModuleNotFoundError as e:
    print(f"⚠️  swe.yaml validation skipped ({e})")
    print("   → Hint: run 'make bootstrap-solai' to install SWE-Agent")
except Exception as e:
    print(f"❌ swe.yaml validation failed: {e}", file=sys.stderr)
    sys.exit(1)
PY
}

# ────────────────────────────────────────────────────────────────
# Everything below may run under sudo / root; validation is done.
# ────────────────────────────────────────────────────────────────

# ---------- make sure forge is on PATH ---------------------------------------

IFS=':' read -ra FOUND_CANDIDATES <<<"$FOUNDRY_SEARCH_PATHS"
for dir in "${FOUND_CANDIDATES[@]}"; do
  [[ -n "$dir" && -x "$dir/bin/forge" ]] && { export PATH="$dir/bin:$PATH"; echo "✓ Found forge in: $dir/bin"; break; }
done

require_cmd forge
forge_bin="$(command -v forge)"
echo "Using forge from: $forge_bin"
echo "Foundry version: $(forge --version)"

# ---------- create failing demo repo -----------------------------------------

rm -rf "$DEMO_DIR" && mkdir -p "$DEMO_DIR" && cd "$DEMO_DIR"
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

# ---------- run SWE-Agent -----------------------------------------------------

TS=$(date +%Y%m%dT%H%M%S)
LOGFILE="run_${TS}.log"
PATCH_TAR="${DEMO_DIR}/patch.tar"

# Run from inside the demo repo so that repo.path='.' is correct
pushd "$DEMO_DIR" >/dev/null
SWE_CMD="$PYBIN_DIR/python -m sweagent run --config ${SCRIPT_DIR}/swe.yaml --output_dir ${SCRIPT_DIR}"
eval "$SWE_CMD" 2>&1 | tee "$LOGFILE"
popd >/dev/null
[[ -s "$PATCH_TAR" ]] || { echo "❌ SWE-Agent failed or patch missing"; exit 1; }
echo "✓ Agent produced $PATCH_TAR"

# ---------- apply patch with guard-rails -------------------------------------

cd "$SCRIPT_DIR"
tar -xf "$PATCH_TAR"

# gather patch files
if command -v mapfile >/dev/null 2>&1; then
  mapfile -d '' -t patch_files < <(find . -maxdepth 1 -name '*.[pd][ia][ft]' -print0)
else
  patch_files=()
  while IFS= read -r -d '' f; do patch_files+=("$f"); done < <(find . -maxdepth 1 -name '*.[pd][ia][ft]' -print0)
fi
[[ ${#patch_files[@]} -eq 0 ]] && { echo "❌ No patch files found"; exit 1; }

TOTAL_LOC_INS=0 TOTAL_LOC_DEL=0
STATS_DIR=".patch_stats"
mkdir -p "$STATS_DIR"
# shellcheck disable=SC2064
trap "rm -rf '$STATS_DIR'" EXIT

for p in "${patch_files[@]}"; do
  echo "--- Validating patch: $p ---"
  size=$(wc -c <"$p")
  (( size >= 100000 )) && { echo "💥 $p too large ($size bytes)"; exit 1; }
  echo "  ✓ Size check passed ($size bytes)"

  patch_stats=$(git apply --numstat "$p") || { echo "❌ git apply --numstat failed"; exit 1; }
  printf '%s\n' "$patch_stats" >"$STATS_DIR/$(basename "$p").stats"

  loc_ins=$(awk '$1!="-" {i+=$1} END{print i+0}' <<<"$patch_stats")
  loc_del=$(awk '$2!="-" {d+=$2} END{print d+0}' <<<"$patch_stats")
  total_loc=$((loc_ins+loc_del))
  (( total_loc > 2000 )) && { echo "💥 $p changes $total_loc LOC"; exit 1; }
  echo "  ✓ LOC check passed (+$loc_ins / -$loc_del = $total_loc)"

  TOTAL_LOC_INS=$((TOTAL_LOC_INS+loc_ins))
  TOTAL_LOC_DEL=$((TOTAL_LOC_DEL+loc_del))

  echo "--- Applying: $p ---"
  git apply "$p" || { echo "❌ git apply failed"; git diff; exit 1; }
  echo "  ✓ Applied"
done

# ---------- summary ----------------------------------------------------------

{
  echo "### Phase 3 Summary"
  echo "- **LOC Changed:** +$TOTAL_LOC_INS / -$TOTAL_LOC_DEL"
  cost=$(grep -E 'Estimated cost: \$[0-9.]+' "$LOGFILE" | sed -E 's/.*\$([0-9.]+).*/\1/' || true)
  [ -n "$cost" ] && echo "- Estimated Cost: $cost"
} >> "$GITHUB_STEP_SUMMARY"

forge test -q || { echo "❌ tests still failing"; git diff; exit 1; }
echo "✓ tests green after patch"

# ---------- Slither ----------------------------------------------------------

SLITHER_IMG="ghcr.io/crytic/slither:latest-slim"
docker pull --quiet "$SLITHER_IMG" || true
echo "--- Running Slither ---"
docker run --pull=never --rm -v "$PWD":/src "$SLITHER_IMG" \
  slither /src --exclude-dependencies --disable-color >slither.txt || \
  echo "Slither exited non-zero → continuing"
echo "✓ Slither analysis complete"

# ---------- evidence bundle --------------------------------------------------

mkdir -p .evidence
cp "$STATS_DIR"/* .evidence/ 2>/dev/null || true
mv "$PATCH_TAR" "$LOGFILE" slither.txt .evidence/

{
  echo "Evidence Bundle Contents:"
  echo "------------------------"
  find .evidence -type f | sort
  echo "------------------------"
  echo "Total files: $(find .evidence -type f | wc -l)"
} >.evidence/manifest.txt

TB="evidence_${TS}.tgz"
tar -czf "$TB" .evidence
echo "bundle_name=$TB" >>"$GITHUB_OUTPUT"

echo "✅ Phase 3 complete"

# Note (macOS): install GNU coreutils for full compatibility:
#   brew install coreutils