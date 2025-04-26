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
- **Metadata:** Added `allow-direct-references = true` under `[tool.hatch.metadata]` to support the direct Git dependencies.

## 4. Installation and Bootstrapping (`README.md`, `Makefile.inc`)

- **Installation Process:** The recommended installation method was significantly updated:
    1. Install the core package and its `[ai]` extras using `pipx install solai[ai] --include-deps`.
    2. Use `pipx inject solai ...` to install/update the specific Git versions of `SWE-agent` and `SWE-ReX` into the `solai` `pipx` environment. This ensures the latest versions from the repositories are used.
- **`Makefile.inc` (`bootstrap-solai`):** The `bootstrap-solai` target was updated to reflect the new `pipx install solai[ai]` and `pipx inject ...` commands. It now forces the injection of the AI backends on every run.

## 5. Configuration (`.solai.yaml` Template)

The template configuration file (`src/solai/templates/dot_solai.yaml`) was restructured and expanded:

- **`agent`:**
    - `model`: Now requires pinning to a dated model version (e.g., `gpt4o-2025-04-25`).
    - `usd_cap`: Kept from Phase 1.
    - `repo_prompt`: Added field for the high-level task description given to the agent (default: "Fix failing tests").
- **`env`:**
    - `docker_image`: Changed to use a placeholder format `ghcr.io/yourorg/foundry_sol@sha256:<YOUR_DIGEST_HERE>` by default, prompting the user to build/push their own image and update the digest. *Note: The runner code currently uses tags (`foundry_sol:0.4.x`), this template change anticipates a shift towards digests.*
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
- **`image_present`:** Updated to check for the existence of a Docker image based on its *tag* (Repository:Tag format).
- **`doctor` function:**
    - **Checks:**
        - Added check for `swerex-remote --version` (SWE-ReX CLI).
        - Added an *optional* check for `sweagent --version`, printing a warning and installation instructions if missing (since it requires manual source install).
        - Checks for the Docker image *tag* specified in `.solai.yaml` using `image_present`. Exits if missing, directing the user to `solai image-rebuild`.
    - **Guidance:** Prints informational messages about running in WSL2 on Windows and ensuring sufficient Docker RAM (≥ 6 GB).
    - **Removed:** No longer attempts to automatically build the Docker image if missing; relies on the user running `image-rebuild` or managing it manually.
- **`rebuild_image` function (New):**
    - Builds the Docker image using `src/solai/docker/foundry_sol.Dockerfile` with a hardcoded tag (e.g., `foundry_sol:0.4.1`). *Note: Version synchronization between build tag and package version should be considered.*
    - Prints the built image tag to the console.
    - *Does not currently push the image or update `.solai.yaml` automatically.*
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
        - Sets up Python 3.12 using `actions/setup-python@v4`.
        - Installs build dependencies (`build`, `hatchling`) to support PEP 517 wheel building.
    - Sets up Docker Buildx/QEMU.
    - **Package Building & Installation:**
        - Builds the `solai` wheel (`python -m build`).
        - Uses shell expansion to locate the built wheel file.
        - Installs the wheel with `[ai]` extras using `pipx install --include-deps "${wheel}[ai]"`.
    - **Smoke Test:** Creates a temporary directory, initializes a git repo, adds minimal Solidity contract (`Y.sol`) and a failing test (`Y.t.sol`), runs `solai init`, `make bootstrap-solai`, and finally `solai run --once --max-concurrency 1`. This provides a basic end-to-end test of the core workflow.

## 10. Development Environment Setup (`bootstrap/`)

- Added `bootstrap/install_python_env.sh`: A script to create a Python 3.12 virtual environment (`.venv`), install core dependencies, and install `solai` in editable mode with the `[ai]` extras. Useful for local development.

## 11. Documentation (`README.md`)

- Updated significantly:
    - New installation instructions using `pipx install ...[ai]` and `pipx inject`.
    - Added section explaining SWE-ReX authentication requirements (executable name, API key header/flag).
    - Added "Environment Notes" section covering WSL2 guidance, Docker RAM requirements (≥ 6 GB), and log file location (`.solai/logs/run.log`).
    - Added reference link placeholder for this Phase 2 summary.

## 12. Gitignore

- Added a root `.gitignore` file with common Python patterns, IDE files, and `solai` specific directories (`.solai/worktrees/`, `.solai/logs/`).
- Updated `src/solai/templates/gitignore_snip.txt` (no functional change, perhaps formatting).

## 13. Conclusion

Phase 2 successfully implemented the core AI task execution pipeline. `solai` can now be configured to use SWE-Agent (via SWE-ReX) within a specified Docker environment to attempt automated fixes for issues like failing tests. Key additions include the `[ai]` extra dependencies, the `run_backlog` implementation, the `image-rebuild` command, updated `doctor` checks, CI smoke tests, and improved documentation/installation instructions. The project is now capable of performing its primary function, with further refinements and features planned for subsequent phases. 