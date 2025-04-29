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

## Setup Questions & Answers

### 1. How do I install SWE-Agent from source?
Clone the repo, then in its root run:
```bash
python -m pip install --upgrade pip && pip install --editable .
```
It's recommended to use a Conda environment or a Python venv for dependency isolation.

### 2. How can I verify that sweagent is on my PATH?
After installation, run:
```bash
sweagent --help
```
or, if that fails:
```bash
python -m sweagent --help
```
Ensure which python points to the same interpreter used for pip install.

### 3. What is SWE-Agent's default execution backend?
By default, SWE-Agent uses Docker to sandbox code execution.

### 4. Can I run SWE-Agent without Docker?
Yes—SWE-Agent supports cloud-based code evaluation if you don't install Docker locally.

### 5. What should I do if Docker isn't starting or commands hang?
See the "Docker issues" section under Installation → Troubleshooting for common fixes (e.g., increasing timeouts).

### 6. How do I set up the web GUI?
Install Node.js, then run the SWE-Agent web interface per the "In browser" tutorial.

### 7. How are API keys configured for LMs and GitHub?
You have three options:
1. Export the environment variables (e.g. OPENAI_API_KEY, GITHUB_TOKEN).
2. Create a .env file at your repo root with the same variable assignments.
3. Pass --agent.model.api_key on the CLI.

### 8. Which environment variable names are recognized?
- OPENAI_API_KEY for OpenAI models
- ANTHROPIC_API_KEY for Anthropic
- TOGETHER_API_KEY for Together AI
- GITHUB_TOKEN for private-repo access

### 9. Where can I learn how to obtain each API key?
The docs link to tutorials on:
- Anthropic: docs.anthropic.com
- OpenAI: platform.openai.com
- GitHub: docs.github.com

### 10. Which model names can I specify for OpenAI?
You may use any OpenAI model supported by Litellm, for example:
gpt-4o-mini, gpt-4o, gpt-3.5-turbo, etc.

### 11. How do I disable cost tracking when using local models?
In your config:
```yaml
agent:
  model:
    name: ollama/llama2
    api_base: http://localhost:11434
    per_instance_cost_limit: 0
    total_cost_limit: 0
    per_instance_call_limit: 100
    max_input_tokens: 0
```
This prevents the default cost calculator from erroring out.

### 12. Why must I set per_instance_cost_limit to 0 for local LLMs?
Because the cost calculator has no pricing for custom or local models; setting it to 0 bypasses that check.

### 13. How do I select a different function-parsing strategy if my model lacks function calling?
In your config, under agent.tools.parse_function set:
```yaml
type: thought_action
```
This extracts the last ... block as the action.

### 14. What major migration changes occurred in SWE-Agent v1.0?
- Switched config validation to Pydantic
- Replaced templates with Jinja2
- Core refactor to use SWE-ReX for code execution

### 15. How do I switch to the EnIGMA mode?
EnIGMA mode is only compatible with the v0.7 branch. After cloning, run:
```bash
git switch v0.7
```

### 16. How can I keep SWE-Agent up to date?
Simply cd into your clone and run git pull. No need to reinstall via pip unless moving between major versions.

### 17. What command shows all available SWE-Agent commands?
```bash
python -m sweagent --help
```
It lists subcommands like run, batch, etc.

### 18. Where do I find detailed RunSingleConfig schema docs?
Under API Reference → Run config → Run single in the online docs.

### 19. How do I review the full changelog?
Visit /latest/installation/changelog/ to see version-by-version additions, fixes, and breaking changes.

### 20. How do I report bugs or request features?
Use the "Report bug" or "Ask question" links at the bottom of any doc page to open an issue on GitHub.

## Self-Audit: Potential Gaps in These Answers
- Docker troubleshooting (Q5) is summarized; the tips page timed out, so specifics may be missing.
- Log-level configuration (from the changelog) isn't covered in docs, so we didn't include an explicit flag.
- Exact default hyperparameters (temperature, timeouts) for gpt-4o-mini aren't documented here.
- Advanced config file fields (e.g. environment_setup, cache_task_images) from older versions may differ in v1.0.

## Remaining Ambiguities & Next Steps
1. **Docker Tips Details**
   The "Installation tips" section timed out—please share any local cache or file copy so we can extract specific Docker workarounds.

2. **Log-Level & Timeout Config**
   The changelog mentions configurable TRACE levels and timeouts—if you have sample keys.cfg or config.yaml from your environment, that'd clarify how to set these.

3. **Model Hyperparameters**
   If you require non-default temperature or retry settings, please share your desired agent configuration or point to your existing swe.yaml.

4. **Legacy Flags**
   Features like --cache_task_images and --environment_setup existed in v0.5; if you rely on them, let me know so I can compare against your v1.0 setup.

## CI Pipeline and Makefile Integration

### 21. What is the purpose of the new Makefile-based CI pipeline?
The Makefile provides a unified interface for:
- Dependency management (venv, pip-tools, SWE-Agent)
- Testing (Solidity via Foundry, Python via pytest)
- Linting (Slither for Solidity, Ruff for Python)
- Local development setup
- GitHub Actions integration

### 22. How do I run the full CI pipeline locally?
Simply run:
```bash
make ci
```
This will:
1. Set up the virtual environment
2. Install dependencies
3. Run all tests (Solidity and Python)
4. Run all linters (Slither and Ruff)

### 23. What are the individual targets I can run?
- `make venv`: Create Python virtual environment
- `make install-sweagent`: Install SWE-Agent
- `make test-solidity`: Run Foundry tests
- `make lint-solidity`: Run Slither analysis
- `make test-python`: Run Python tests
- `make lint-python`: Run Ruff linter
- `make dev`: Full development environment setup

### 24. How does the GitHub Actions integration work?
The CI workflow in `.github/workflows/ci.yml`:
1. Sets up Python 3.12
2. Installs Docker
3. Runs `make ci` to execute the full pipeline

### 25. What are the dependency management features?
- Uses pip-tools for deterministic builds
- Maintains a `hashed_constraints.txt` for exact versions
- Generates `requirements.txt` with hashes
- Handles SWE-Agent installation from GitHub

### 26. What are the requirements for running the pipeline locally?
- Python 3.12
- Docker (for Slither)
- Foundry (for Solidity tests)
- Git

### 27. How do I clean up the development environment?
Run:
```bash
make clean-venv
```
This removes the virtual environment and all installed packages.

### 28. How do I update dependencies?
1. Edit `hashed_constraints.txt`
2. Run `make lockfile` to regenerate `requirements.txt`
3. Run `make sync-requirements` to update the venv 