# Phase 2 Implementation Summary: `solai` Package v0.4.2

This document summarizes the significant changes and additions made during Phase 2 of the `solidity-ai-pipeline` project, culminating in version `0.4.2` of the `solai` package. This phase focused on integrating the core AI agent functionality and building the task execution pipeline.

Refer to the main [README.md](../README.md) for quick start instructions and general usage information.

## 1. Goal: AI Integration and Task Execution

The primary objective of Phase 2 was to move beyond the foundational package structure and implement the core logic for running AI agents (specifically SWE-Agent orchestrated via SWE-ReX) to automatically attempt fixes within a Solidity project based on configuration.

## 2. Version Update

- The package version was bumped to `0.4.2` in `pyproject.toml` and `src/solai/__init__.py` (implied).

## 3. Packaging and Dependencies (`pyproject.toml`)

- **Version:** Updated to `0.4.2`.
- **Dependencies:**
    - Core dependencies remain `typer`, `rich`, `pyyaml`.
    - **`[ai]` Extra:** Introduced an optional dependency group `[ai]` to handle the AI backend installations. This extra includes:
        - `sweagent` (installed directly from the `princeton-nlp/SWE-agent` GitHub repository).
        - `swe-rex` (installed directly from the `SWE-agent/SWE-ReX` GitHub repository).
- **Build Configuration:**
    - Added `only-packages = true` to ensure proper package building
    - Configured wheel target to include `src/solai` package
    - Properly handles src-layout Python package structure
- **Metadata:** Added `allow-direct-references = true` under `[tool.hatch.metadata]` to support the direct Git dependencies.

## 4. Installation and Bootstrapping (`README.md`, `Makefile.inc`)

- **Installation Process:** The recommended installation method (both from source and potentially PyPI) is `pip install .[ai]` (or the built wheel `dist/solai-*.whl[ai]`). This installs `solai` along with `sweagent` and `swe-rex` from their Git repositories due to the `[ai]` extra.
- **Bootstrapping:** Use `make bootstrap-solai` to:
    - Ensure `pipx` is available and on the PATH (though `solai` itself is installed via `pip`).
    - Run `solai doctor` to verify the complete environment (Python, Docker, Foundry, Slither, SWE-ReX, SWE-Agent, configured Docker image).
- **`Makefile.inc`:** The `bootstrap-solai` target primarily runs `pipx ensurepath` and `solai doctor`. It *no longer* handles the installation of `solai` or its dependencies itself (this is done via `pip install`). The `pipx inject` lines shown in earlier diffs were part of an intermediate step and removed.

## 5. Configuration (`.solai.yaml` Template)

The template configuration file (`src/solai/templates/dot_solai.yaml`) was restructured and expanded:

- **`agent`:**
    - `model`: Now requires pinning to a dated model version (e.g., `gpt4o-2025-04-25`).
    - `usd_cap`: Kept from Phase 1.
    - `repo_prompt`: Added field for the high-level task description given to the agent (default: "Fix failing tests").
- **`env`:**
    - `docker_image`: Changed to use a placeholder format `ghcr.io/yourorg/foundry_sol@sha256:<YOUR_DIGEST_HERE>` by default. *Note: The CI workflow builds and uses a *tag* (`solai-smoke-test:latest`) and updates the config file in the CI environment. The `doctor` command checks for the *tag* specified in the config. The `image-rebuild` command currently builds a tag like `foundry_sol:0.4.1` but doesn't integrate with the main workflow or config update automatically.*
    - `post_startup_cmds`: Format changed to a list of command lists (e.g., `[["forge", "test", "-q"]]`).
- **`task`:** New section added:
    - `branch`: Specifies the Git branch name the agent should create/use (default: `fix-demo`).
    - `max_attempts`: Placeholder for future retry logic (default: 1).
- **`worktrees_dir`:** Path for temporary worktrees (default: `.solai/worktrees`).
- **`backlog`:**
    - `file`: Location of the backlog definition (default: `backlog.yaml`).

## 6. CLI Enhancements (`cli.py`)

- **`init` command:**
    - Added a check after copying templates. If the generated `.solai.yaml` contains the placeholder Docker image digest, it prints a warning (`typer.secho`) prompting the user to run `solai image-rebuild` (or manually update).
- **`run` command:**
    - **Parameters:**
        - `--once`/`--watch`: Changed the flag logic. Default is now `--watch` (run continuously), use `--once` to exit after one pass.
        - `--max-concurrency`: Kept from Phase 1.
        - `--log-file`: Added option to specify the run log file path (default: `.solai/logs/run.log`).
    - **Functionality:** Calls the newly implemented `run_backlog` function from `runner.py`.
- **`doctor` command:**
    - Calls the updated `doctor` function (`run_doctor`) from `runner.py`.
- **`image-rebuild` command (New):**
    - Added a new command `solai image-rebuild`.
    - Calls the `rebuild_image` helper function from `runner.py`.
    - Intended to automate building the `foundry_sol` Docker image and potentially updating the config (currently just prints the tag/digest).

## 7. Core Logic Implementation (`runner.py`)

The `runner.py` module saw the most significant changes, replacing the Phase 1 stubs with functional logic.

- **`_run` Helper:** Introduced a helper function to execute shell commands, stream their stdout/stderr to the console and optionally to a log file, and raise an error on non-zero exit codes.
- **`image_present`:** Updated to check for the existence of a Docker image based on its *tag* (Repository:Tag format) as specified in `.solai.yaml`.
- **`doctor` function:**
    - **Checks:**
        - Verifies Python version (`>=3.12`).
        - Checks core tools: `pipx`, `docker` CLI/engine, `forge`, `slither`, `swerex-remote`.
        - *Optionally* checks for `sweagent`, printing a warning if missing (as it's installed via the `[ai]` extra).
        - Checks if the Docker image *tag* specified in `.solai.yaml` (`env.docker_image`) exists locally using `image_present`.
    - **Guidance:** Prints informational messages about WSL2 and Docker RAM.
    - **Removed:** No longer attempts to automatically build the Docker image.
    - **Binary Name:** The check for the SWE-ReX binary now looks for `swerex-remote` (the name installed by `pip install swe-rex`), replacing the previous check for `swe-rex`.
- **`rebuild_image` function (New):**
    - Builds the Docker image using `src/solai/docker/foundry_sol.Dockerfile` with a hardcoded tag (e.g., `foundry_sol:0.4.1`).
    - Prints the built image tag to the console.
    - *Does not push the image or update `.solai.yaml`.*
- **`run_backlog` function (Implemented):**
    - **Configuration Loading:** Reads settings from the specified config file (`.solai.yaml`).
    - **Model Date Pinning:** Validates that the `agent.model` string includes a date suffix (e.g., `-YYYY-MM-DD`).
    - **Logging:** Ensures the log directory exists and opens the specified log file for appending.
    - **Worker Thread (`_worker`):**
        - Uses `concurrent.futures.ThreadPoolExecutor` to manage workers (though currently runs one task at a time in the main loop).
        - **Temporary Worktree:** Creates a temporary directory.
        - **Git Operations:** Clones the current repository into the worktree, checks out a new branch based on `task.branch` config.
        - **SWE-Agent Configuration:** Dynamically generates a `swe.yaml` file inside the worktree, configuring `sweagent` with:
            - `open_pr: false`
            - `apply_patch_locally: true`
            - `problem_statement.repo_path: .`
            - `problem_statement.text`: From `agent.repo_prompt` config.
            - `env.deployment.image`: From `env.docker_image` config.
        - **Agent Execution:** Runs `swe-rex run --image <image_tag> -- sweagent run ...` using the `_run` helper, logging output. Passes the generated `swe.yaml` and specifies `--output-tar patch.tar`.
            - **Binary Name:** The command executed is now `swerex-remote` by default, read from the `env.swe_rex_bin` config setting. This can be overridden globally using the `SWE_REX_BIN` environment variable for backward compatibility if the binary is still named `swe-rex` on a system.
        - **Patch Handling:**
            - Checks if `patch.tar` was created.
            - Extracts the tarball.
            - Finds the resulting `.diff` or `.patch` file.
            - **Validation:** Uses `git apply --stat` to check the patch and extracts insertion/deletion counts. Rejects patches with 0 LOC, > 2000 LOC, or > 100KB file size.
            - **Application:** Applies the patch using `git apply`.
        - **Testing:** Runs `forge test -q` within the worktree after applying the patch.
        - **Outcome:** Prints success ("🎉 ... tests green") or failure messages ("Tests still failing", "No patch produced", etc.).
    - **Main Loop:**
        - Runs the `_worker` function.
        - If `--once` is specified, breaks after the first run.
        - If `--watch` (default), sleeps for 30 seconds and repeats.
        - Includes basic exception handling around the worker execution.

## 8. Docker Environment (`src/solai/docker/`)

- No changes were made to the `foundry_sol.Dockerfile` itself in this phase. The interaction model changed via the `image-rebuild` command and configuration references (tags).

## 9. Continuous Integration (`.github/workflows/solai.yml`)

- A new GitHub Actions workflow was added (`solai-phase2`).
- **Trigger:** Runs on push events.
- **Job (`smoke`):**
    - Runs on `ubuntu-latest`.
    - **Python Environment:**
        - Sets up Python 3.12 using `actions/setup-python@v4` to match package requirements (`>=3.12`).
        - This ensures both build and installation steps use the correct Python version.
    - **Build Process:**
        - Installs the PEP 517 build frontend (`python -m pip install build`).
        - Builds the `solai` wheel (`python -m build`).
    - **Package Installation & Verification:**
        - Locates the built wheel file.
        - Installs the wheel with its AI extras using `pip install "${wheel}[ai]".
        - Installs Slither explicitly (`pip install slither-analyzer`).
        - Installs Foundry using a multi-step process involving `curl` and `foundryup`, ensuring binaries are correctly placed and PATH is updated.
        - *Does not* run `solai doctor` at this stage.
    - **Smoke Test:**
        - Creates a temporary directory (`smoke/`) and sets up a minimal Solidity project with a failing test.
        - Runs `solai init`.
        - Runs `make bootstrap-solai` (which now primarily runs `solai doctor`).
        - **Builds the required Docker image** (`docker build -t solai-smoke-test:latest ...`).
        - **Updates the `.solai.yaml** in the `smoke/` directory to use the `solai-smoke-test:latest` tag via an inline python script.
        - **Runs `solai doctor** to verify the environment *after* all setup, including the Docker image build and config update.
        - Runs the core workflow `solai run --once --max-concurrency 1`.

## 10. Development Environment Setup (`bootstrap/`)

- Added `bootstrap/install_python_env.sh`: A script to create a Python 3.12 virtual environment (`.venv`), install core dependencies (`typer`, `rich`, `pyyaml`), and install `solai` in editable mode with the `[ai]` extras (`pip install -e .[ai]`). Useful for local development.

## 11. Documentation (`README.md`)

- Updated significantly:
    - Installation instructions clarified to use `pip install .[ai]` (or the wheel) for both `solai` and AI dependencies.
    - Requirements updated (Slither, SWE-Agent, SWE-ReX installed via `[ai]` extra).
    - SWE-ReX authentication details added.
    - Environment notes (WSL2, Docker RAM, Logs) added/updated.
    - Phase summary links updated.

## 12. Gitignore

- Added a root `.gitignore` file with common Python patterns, IDE files, and `solai` specific directories (`.solai/worktrees/`, `.solai/logs/`).
- Updated `src/solai/templates/gitignore_snip.txt` (no functional change, perhaps formatting).

## 13. Conclusion

Phase 2 successfully implemented the core AI task execution pipeline. `solai` can now be configured to use SWE-Agent (via SWE-ReX) within a specified Docker environment to attempt automated fixes for issues like failing tests. Key additions include the streamlined installation process via `make bootstrap-solai`, the `run_backlog` implementation, the `image-rebuild` command, updated `doctor` checks, CI smoke tests, and improved documentation/installation instructions. The project is now capable of performing its primary function, with further refinements and features planned for subsequent phases. 