#!/usr/bin/env bash
set -euo pipefail

# Phase 3: Hello-World SWE-Agent Run
# This script is invoked by GitHub Actions via:
#   sudo --preserve-env=OPENAI_API_KEY,PYBIN_DIR bash ci/phase3.sh
#
# Environment Variables:
#   PYBIN_DIR: Path to Python binary directory (defaults to dirname of which python)
#   DEMO_DIR: Directory for the demo repository (defaults to /tmp/demo)
#   FOUNDRY_DIR: Optional path to Foundry installation
#   FOUNDRY_SEARCH_PATHS: Colon-separated list of paths to search for Foundry
#   OPENAI_API_KEY: Required for SWE-Agent operation

# Helper for command existence checks
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' missing"; exit 1; }
}

# Guard PYBIN_DIR for local runs
: "${PYBIN_DIR:=$(dirname "$(which python)")}"

# Configurable paths
# Absolute path to repo root *before* we cd into the demo folder
SCRIPT_DIR="$(pwd)"
: "${DEMO_DIR:=/tmp/demo}"          # Can be overridden for concurrent local runs
# Colon-separated list
: "${FOUNDRY_SEARCH_PATHS:=${FOUNDRY_DIR:-}:/home/runner/.config/.foundry:$HOME/.config/.foundry}"

# Early command check – only tools guaranteed to exist **before** installs
require_cmd docker

# 2️⃣ Create swe.yaml with spending cap **and validate it _before_ sudo-only code**
# ------------------------------------------------------------------
# This block runs as the original (non-root) user, so the same Python
# environment that installed `sweagent` can import it without trouble.
# ------------------------------------------------------------------
{
  set -euo pipefail
  cat > 'swe.yaml' << 'YAML'
# Minimal, fully-valid RunSingleConfig
problem_statement:
  text: Fix failing tests

# Revert to simple agent model config
agent:
  # Specify model as a dictionary
  model:
    name: gpt-4o-mini

actions:
  apply_patch_locally: true
  open_pr: false

env:
  repo:
    path: .
  deployment:
    type: local          # SWE-Agent ≥1.0 accepted literal
#    # If the API ever regains copy-control, uncomment:
#    # copy_repo: false
YAML

  echo "✓ Created swe.yaml"
  
  # Add lightweight validation step
  echo "--- Validating swe.yaml (non-sudo python) ---"
  "$PYBIN_DIR/python" - <<'PY'
from importlib import import_module
import yaml, sys
try:
    RunSingleConfig = import_module("sweagent.config").RunSingleConfig
    RunSingleConfig.model_validate(yaml.safe_load(open('swe.yaml')))
    print("✓ swe.yaml validation passed")
except ModuleNotFoundError as e:
    # Continue gracefully – the main SWE-Agent run will still fail loudly
    # if the package is truly absent; this keeps local runs ergonomic.
    print(f'⚠️  swe.yaml validation skipped ({e})')
    print('   → Hint: Run `make bootstrap-solai` to install SWE-Agent and its dependencies')
except Exception as e:
    print(f"❌ swe.yaml validation failed: {e}", file=sys.stderr)
    sys.exit(1)
PY
}

# ────────────────────────────────────────────────────────────────
# Everything below may run under sudo / root; validation is done.
# ────────────────────────────────────────────────────────────────

# ---------------------------------------------------------------------
# Ensure Foundry (forge) is on PATH even when running under `sudo`
# ---------------------------------------------------------------------
#  CI installs Foundry in $HOME/.config/.foundry/bin (runner user).
#  When the workflow invokes this script via `sudo`, that path is LOST.
#  We proactively search the typical install dirs and patch $PATH.

IFS=':' read -ra FOUND_CANDIDATES <<< "$FOUNDRY_SEARCH_PATHS"

for dir in "${FOUND_CANDIDATES[@]}"; do
  if [[ -n "$dir" && -x "$dir/bin/forge" ]]; then
    export PATH="$dir/bin:$PATH"
    echo "✓ Found forge in: $dir/bin"
    break
  fi
done

# Require forge after PATH injection
require_cmd forge
echo "Using forge from: $(command -v forge)"
echo "Foundry version: $(forge --version)"

# 1️⃣ Create isolated failing demo repo
rm -rf "$DEMO_DIR" && mkdir -p "$DEMO_DIR" && cd "$DEMO_DIR"
git init -q

cat > 'Greeter.sol' << 'SOL'
pragma solidity ^0.8.26;
contract Greeter {
    string private greeting = "hello";
    function greet() external view returns (string memory) {
        return greeting;
    }
}
SOL

cat > 'Greeter.t.sol' << 'SOLTEST'
pragma solidity ^0.8.26;
import "forge-std/Test.sol";
import "./Greeter.sol";

contract GreeterTest is Test {
    Greeter g;
    function setUp() public { g = new Greeter(); }
    /// @notice Wrong on purpose
    function testGreetingFails() public {
        assertEq(g.greet(), "HELLO");
    }
}
SOLTEST

# Expect failure – baseline should be red.
if forge test -q 2>/dev/null; then
  echo "❌ tests unexpectedly green"
  exit 1
else
  echo "✓ baseline red"
fi

# 3️⃣ Run SWE-Agent via python -m
TS=$(date +%Y%m%dT%H%M%S)
LOGFILE="run_${TS}.log"
PATCH_TAR="${DEMO_DIR}/patch.tar"

# SWE-Agent ≥1.0 reads env.repo.path from swe.yaml; --repo_path was removed.
# We still want logs & patch artefacts back in the repo root (${SCRIPT_DIR})
SWE_CMD="$PYBIN_DIR/python -m sweagent run --config ${SCRIPT_DIR}/swe.yaml --output_dir ${SCRIPT_DIR}"
eval "$SWE_CMD" 2>&1 | tee "$LOGFILE"
ret=$?
if [ $ret -ne 0 ] || [ ! -s "${PATCH_TAR}" ]; then
  echo "❌ SWE-Agent run failed or ${PATCH_TAR} missing"; exit 1
fi
echo "✓ Agent produced ${PATCH_TAR}"

# 4️⃣ Apply patch & guard-rails
cd "${SCRIPT_DIR}"
tar -xf "${PATCH_TAR}"

# Use mapfile to handle multiple patch files if necessary
if command -v mapfile >/dev/null 2>&1; then
  # Modern bash with mapfile
  mapfile -d $'\0' patch_files < <(find . -maxdepth 1 -name '*.[pd][ia][ft]' -print0)
else
  # Fallback for systems without mapfile (e.g. macOS)
  patch_files=()
  while IFS= read -r -d '' f; do
    patch_files+=("$f")
  done < <(find . -maxdepth 1 -name '*.[pd][ia][ft]' -print0)
fi

if [ "${#patch_files[@]}" -eq 0 ]; then
  echo "❌ No patch files found in ${PATCH_TAR}"
  exit 1
fi

TOTAL_LOC_INS=0
TOTAL_LOC_DEL=0

# Create a temporary directory for patch stats
STATS_DIR=".patch_stats"
mkdir -p "$STATS_DIR"

# Ensure cleanup happens even on script failure
trap 'rm -rf "$STATS_DIR"' EXIT

for p in "${patch_files[@]}"; do
  [ -z "$p" ] && continue # Skip empty entries if any
  echo "--- Validating patch file: $p ---"
  
  # Check size
  size=$(wc -c < "$p")
  if [ "$size" -ge 100000 ]; then
    echo "💥 Patch file $p is too large ($size bytes)"
    exit 1
  fi
  echo "  ✓ Size check passed ($size bytes)"

  # Check LOC changed - store stats per patch file
  STATS_FILE="${STATS_DIR}/$(basename "$p").stats"
  # Process patch once and reuse for both stats and application
  {
    # First get the stats
    git apply --numstat "$p" > "$STATS_FILE"
    # Then read the stats file
    loc_ins=$(awk '$1!="-" {ins+=$1} END{print ins+0}' "$STATS_FILE")
    loc_del=$(awk '$2!="-" {del+=$2} END{print del+0}' "$STATS_FILE")
    total_loc=$((loc_ins + loc_del))
    
    if [ "$total_loc" -gt 2000 ]; then
      echo "💥 Patch $p changes too many lines ($total_loc LOC)"
      exit 1
    fi
    echo "  ✓ LOC check passed (+${loc_ins}/-${loc_del} = ${total_loc} total)"
    
    TOTAL_LOC_INS=$((TOTAL_LOC_INS + loc_ins))
    TOTAL_LOC_DEL=$((TOTAL_LOC_DEL + loc_del))

    echo "--- Applying patch file: $p ---"
    git apply "$p" || { echo "❌ Applying patch $p failed"; git diff; exit 1; }
    echo "  ✓ Applied successfully"
  } < "$p"
done

# Add summary to GitHub Step Summary
echo '### Phase 3 Summary' >> "$GITHUB_STEP_SUMMARY"

# summary – now that loop is done TOTAL_LOC_INS/DEL are final
# Use portable grep -E with look-around instead of GNU-specific -P
COST_LINE=$(grep -E 'Estimated cost: \$[0-9.]+' "$LOGFILE" | sed -E 's/.*Estimated cost: \$([0-9.]+).*/\1/' || true)
{
echo "- **LOC Changed:** +$TOTAL_LOC_INS / -$TOTAL_LOC_DEL"
[ -n "$COST_LINE" ] && echo "- Estimated Cost: $$COST_LINE"
} >> "$GITHUB_STEP_SUMMARY"

forge test -q || { echo "❌ tests still failing after applying patch(es)"; git diff; exit 1; }
echo "✓ tests green after patch"

# Cache Slither image if not already
SLITHER_IMG="ghcr.io/crytic/slither:latest-slim"
docker pull --quiet "$SLITHER_IMG" || true

# 5️⃣ Run Slither inside container
echo "--- Running Slither ---"
# never re-pull if cached layer is present
docker run --pull=never --rm -v "$PWD":/src "$SLITHER_IMG" \
    slither /src --exclude-dependencies --disable-color > slither.txt || \
    echo "Slither exited non-zero → continuing"
echo "✓ Slither analysis complete"

# 6️⃣ Bundle evidence
mkdir -p .evidence
# Move all patch stats files
mv "$STATS_DIR"/* .evidence/ 2>/dev/null || true
# Move artefacts with absolute paths
mv "${PATCH_TAR}" "$LOGFILE" slither.txt .evidence/

# Create evidence manifest
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