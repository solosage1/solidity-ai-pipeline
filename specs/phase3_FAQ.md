# Phase 3 FAQ

## Overview and Purpose

### 1. What is the exact purpose of the phase3.sh script in the overall pipeline?
It orchestrates the Phase 3 "hello-world" integration test for the SWE-Agent CI pipeline by:
- Creating a minimal Foundry repo (Greeter.sol + failing test) in a temp directory
- Verifying the test initially fails ("red")
- Invoking SWE-Agent to generate a patch that makes the test pass
- Validating & applying that patch under strict size/LOC guardrails
- Rerunning tests to confirm success
- Running Slither for static-security analysis
- Bundling logs, stats, patch, and slither output into an evidence archive

### 2. What specific changes were made in the recent commit?
From the diff of ci/phase3.sh (commit ae7058007…):
- Header fix: Changed smart quotes to straight quotes in the script comment
- DEMO_DIR: Switched from hardcoded `: "${DEMO_DIR:=/tmp/demo}"` to `DEMO_DIR=$(mktemp -d)` and added `trap 'rm -rf "$DEMO_DIR"' EXIT`
- pip install: Replaced `pip install --quiet 'sweagent==1.0.1'` with `pip install --quiet 'git+https://github.com/princeton-nlp/swe-agent.git@v1.0.1'`
- swe.yaml handling:
  - Introduced `SWE_CONFIG_PATH="/tmp/swe.yaml"`
  - Redirected the YAML via `cat > "$SWE_CONFIG_PATH"` (allowing $DEMO_DIR expansion)
  - Updated the repo path in that YAML to `${DEMO_DIR}`
  - Echo now reports `✓ Created $SWE_CONFIG_PATH`
- Validation block: Commented out the Python-based RunSingleConfig validation (using the new "$SWE_CONFIG_PATH")
- Directory setup: Removed `rm -rf "$DEMO_DIR"` before creation; now simply `mkdir -p "$DEMO_DIR"; cd "$DEMO_DIR"`
- SWE-Agent env fixes:
  - Added detection of `site.getsitepackages()[0]` to set `SWE_AGENT_TOOLS_DIR`
  - Added `SWE_AGENT_TRAJECTORY_DIR="$DEMO_DIR"`
  - Changed SWE_CMD to point to `--config ${SWE_CONFIG_PATH}` and `--output_dir ${DEMO_DIR}` instead of `${SCRIPT_DIR}`

## Technical Implementation

### 3. What is the expected behavior of the SWE-Agent in this context?
- Load the demo repo in DEMO_DIR
- Read the prompt "Fix failing tests" from /tmp/swe.yaml
- Analyze the failing GreeterTest assertion
- Produce a patch archive (patch.tar) that, when applied, makes forge test pass

### 4. What are the specific test cases that the Greeter.sol and Greeter.t.sol contracts are meant to verify?
- Greeter.sol: greet() returns the private string greeting (initially "hello")
- Greeter.t.sol:
  - setUp() deploys Greeter
  - testGreetingFails() asserts greet() equals "HELLO", ensuring the test fails until patched

### 5. What is the exact failure condition that the script is trying to fix?
- forge test -q should exit non-zero because "hello" != "HELLO"
- The script explicitly fails if tests are green before patching

### 6. What version of Solidity is being targeted, and why was 0.8.26 chosen?
- Both source and test use `pragma solidity ^0.8.26;`
- Likely chosen to align with the team's Foundry default and benefit from any 0.8.26 bug-fixes or language features

### 7. What are the specific requirements for the Foundry setup in the pipeline?
- A forge binary on $PATH, discovered via FOUNDRY_SEARCH_PATHS
- Verified by require_cmd forge and forge --version output

### 8. What is the purpose of the temporary directory (DEMO_DIR) and why is it needed?
- To isolate all demo files (repo init, code, tests, patches, logs) in a throwaway location
- It's auto-cleaned on exit to avoid polluting the workspace

## Validation and Security

### 9. What are the specific guardrails in place for patch validation?
- Existence: ≥1 patch file matching *.[pd][ia][ft]
- Size: each <100 000 bytes
- LOC delta: insertions + deletions ≤ 2000 (via git apply --numstat)
- Clean apply: git apply must succeed

### 10. What is the significance of the 2000 LOC limit in the patch validation?
- Ensures the patch is narrowly scoped and reviewable; prevents huge or wholesale rewrites

### 11. What is the purpose of the Slither static analysis step?
- After tests pass, run Slither in Docker to detect Solidity security issues and output results to slither.txt

### 12. What specific security checks is Slither configured to perform?
- All default detectors (with --exclude-dependencies and --disable-color)
- No additional custom filters—full standard suite

## Output and Evidence

### 13. What is the expected format and content of the evidence bundle?
- Directory .evidence/ containing:
  - Per-patch .stats files
  - patch.tar, the run log, and slither.txt
  - manifest.txt listing contents
- Compressed into evidence_${TS}.tgz and exposed via bundle_name

### 14. What are the specific requirements for the GitHub Actions environment?
- bash, git, mktemp, docker CLI, python, and forge installed
- Permissions to write to $GITHUB_STEP_SUMMARY and $GITHUB_OUTPUT

## Configuration

### 15. What is the purpose of the swe.yaml configuration file?
- Defines the SWE-Agent run: problem statement, model (gpt-4o-mini), actions (apply_patch_locally, open_pr: false), and environment (repo path = ${DEMO_DIR}, deployment type = local)

### 16. What specific model parameters are being used for the GPT-4o-mini agent?
- Only name: gpt-4o-mini is set. Other hyperparameters (temperature, max_tokens, etc.) use SWE-Agent's defaults

## Error Handling

### 17. What are the specific error conditions that should trigger a pipeline failure?
- Missing required commands (require_cmd)
- Tests unexpectedly green on baseline
- SWE-Agent produces no patch.tar
- No patch files found
- Patch too large (>100 000 bytes)
- LOC delta >2000
- git apply failure
- Tests still failing after patch

### 18. What is the expected behavior when tests fail after patch application?
- The script prints ❌ tests still failing, dumps git diff, and exits with code 1

## Environment Requirements

### 19. What are the specific requirements for the Docker environment?
- docker CLI to pull and run the Slither image (ghcr.io/crytic/slither:latest-slim) with the repo mounted at /src

### 20. What is the exact workflow for handling multiple patch files if they exist?
- Uses `find . -maxdepth 1 -name '*.[pd][ia][ft]'` to collect all patches
- Iterates over them in sorted order, validating size & LOC, applying each via git apply
- Accumulates total LOC ins/del for the summary 