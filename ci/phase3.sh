#!/usr/bin/env bash
set -euo pipefail

# Phase 3: Hello-World SWE-Agent Run
# This script is invoked by GitHub Actions via:
#   sudo --preserve-env=OPENAI_API_KEY,PYBIN_DIR bash ci/phase3.sh

# 1️⃣ Create isolated failing demo repo
cd /tmp
rm -rf demo && mkdir demo && cd demo
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

# 2️⃣ Create swe.yaml with spending cap
{
  set -euo pipefail
  cat > 'swe.yaml' << 'YAML'
# Minimal, fully-valid RunSingleConfig
problem_statement:
  text: Fix failing tests

agent:
  model: gpt-4o-mini               # simple model string, no retry loop here

actions:
  apply_patch_locally: true
  open_pr: false

# Simple chooser retry policy (avoids complex reviewer templates)
retry_loop:
  type: chooser
  chooser: gpt-4o-mini
  max_attempts: 3
  cost_limit: 0.2
  backoff_seconds: 1

env:
  repo:
    path: .
  deployment:
    type: local
YAML

  # Validate the configuration
  echo "Validating SWE-Agent configuration..."
  if ! "$PYBIN_DIR/python" -m sweagent validate --config swe.yaml; then
    echo "❌ SWE-Agent configuration validation failed"
    exit 1
  fi
  echo "✓ Configuration validated successfully"
}

echo "✓ Created and validated swe.yaml"

# 3️⃣ Run SWE-Agent via python -m
TS=$(date +%Y%m%dT%H%M%S)
LOGFILE="run_${TS}.log"
SWE_CMD="$PYBIN_DIR/python -m sweagent run --config swe.yaml --output_dir ."
eval "$SWE_CMD" 2>&1 | tee "$LOGFILE"
ret=$?
if [ $ret -ne 0 ] || [ ! -s patch.tar ]; then
  echo "❌ SWE-Agent run failed or patch.tar missing"; exit 1
fi
echo "✓ Agent produced patch.tar"

# 4️⃣ Apply patch & guard-rails
tar -xf patch.tar

# Use mapfile to handle multiple patch files if necessary
mapfile -d $'\0' patch_files < <(find . -maxdepth 1 -name '*.[pd][ia][ft]' -print0)

if [ "${#patch_files[@]}" -eq 0 ]; then
  echo "❌ No patch files found in patch.tar"
  exit 1
fi

TOTAL_LOC_INS=0
TOTAL_LOC_DEL=0

for p in "${patch_files[@]}"; do
  [ -z "$p" ] && continue # Skip empty entries if any
  echo "--- Validating patch file: $p ---"
  
  # Check size
  size=$(stat -c%s "$p")
  if [ "$size" -ge 100000 ]; then
    echo "💥 Patch file $p is too large ($size bytes)"
    exit 1
  fi
  echo "  ✓ Size check passed ($size bytes)"

  # Check LOC changed
  git apply --stat "$p" > stat.txt
  loc_ins=$(grep -oP '(\d+)\s+insertions?' stat.txt | awk '{s+=$1} END{print s+0}')
  loc_del=$(grep -oP '(\d+)\s+deletions?' stat.txt | awk '{s+=$1} END{print s+0}')
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
done

# Add summary to GitHub Step Summary
echo '### Phase 3 Summary' >> "$GITHUB_STEP_SUMMARY"
TOTAL_LOC_INS=$((TOTAL_LOC_INS + loc_ins))
TOTAL_LOC_DEL=$((TOTAL_LOC_DEL + loc_del))

echo "--- Applying patch file: $p ---"
git apply "$p" || { echo "❌ Applying patch $p failed"; git diff; exit 1; }
echo "  ✓ Applied successfully"

# Add summary to GitHub Step Summary
COST_LINE=$(grep -oP 'Estimated cost: \$\K[0-9.]+' "$LOGFILE" || true)
{
echo "- **LOC Changed:** +$TOTAL_LOC_INS / -$TOTAL_LOC_DEL"
[ -n "$COST_LINE" ] && echo "- Estimated Cost: $$COST_LINE"
} >> "$GITHUB_STEP_SUMMARY"

forge test -q || { echo "❌ tests still failing after applying patch(es)"; git diff; exit 1; }
echo "✓ tests green after patch"

# Cache Slither image if not already
SLITHER_IMG="ghcr.io/crytic/slither:latest-slim"
docker pull "$SLITHER_IMG" || true

# 5️⃣ Run Slither inside container
echo "--- Running Slither ---"
# never re-pull if cached layer is present
docker run --pull=never --rm -v "$PWD":/src "$SLITHER_IMG" \
    slither /src --exclude-dependencies --disable-color > slither.txt || \
    echo "Slither exited non-zero → continuing"
echo "✓ Slither analysis complete"

# 6️⃣ Bundle evidence
mkdir -p .evidence
[ -f stat.txt ] && mv stat.txt .evidence/
mv patch.tar "$LOGFILE" slither.txt .evidence/
TB="evidence_${TS}.tgz"
tar -czf "$TB" .evidence
echo "bundle_name=$TB" >> "$GITHUB_OUTPUT"

# Extract cost for summary
# COST is now handled inline above when writing to GITHUB_STEP_SUMMARY
# COST=$(grep -oP 'Estimated cost: \$\K[0-9.]+' "$LOGFILE" || echo "N/A")
# echo "- **Estimated Cost:** $$COST" >> "$GITHUB_STEP_SUMMARY"

echo "✅ Phase 3 complete" 