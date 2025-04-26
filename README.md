# solai

Plug-and-play AI improvement pipeline for Solidity projects.

## Installation

From PyPI (coming soon):
```bash
pip install solai[ai]
```

From source:
```bash
# Clone the repository
git clone https://github.com/solosage1/solidity-ai-pipeline.git
cd solidity-ai-pipeline

# Build the wheel
python -m pip install --upgrade pip build
python -m build

# Install the wheel with AI dependencies
# This installs solai, sweagent, and swe-rex
pip install dist/solai-*.whl[ai]

# Verify installation and environment
# (This also runs `solai doctor`)
make bootstrap-solai
```

The `bootstrap-solai` make target will:
1. Verify the environment with `solai doctor`
2. Ensure all dependencies are properly installed and accessible
3. Set up any necessary local development tools (like checking pipx path)

## SWE-ReX Authentication

The SWE-ReX service uses API key authentication. When making requests to the service:

1. The executable is named `swerex-remote` (not `swe-rex`)
2. Authentication is done via the `X-API-Key` HTTP header
3. The API key must be provided in the following ways:
   - For HTTP requests: Include header `X-API-Key: your_api_key`
   - For CLI usage: Use `swerex-remote --api-key your_api_key`
   - For Python: Use headers dictionary `{"X-API-Key": "your_api_key"}`

## Quick Start

```bash
# In your Solidity project directory:
solai init
make bootstrap-solai
solai run --once  # Run once and exit
solai run         # Run continuously (default)
```

## Requirements

- Python 3.12+
- Docker
- Foundry (installed via foundryup - automated in CI, manual install needed locally)
    ```bash
    # Local installation:
    curl -L https://foundry.paradigm.xyz | bash
    # Add foundry to your shell's PATH (e.g., in ~/.bashrc or ~/.zshrc)
    # Example for bash/zsh: export PATH="$HOME/.foundry/bin:$PATH"
    # Then run:
    source ~/.bashrc # or ~/.zshrc or restart your terminal
    foundryup
    ```
- Slither (installed automatically with `solai[ai]`)
- SWE-ReX (installed automatically with `solai[ai]`)
- SWE-Agent (installed automatically with `solai[ai]`)

## Environment Notes

- **WSL2** (Windows): For Windows users, run `solai` inside WSL2 to ensure full Docker & POSIX support.
- **Docker RAM**: Allocate at least **6 GB** to Docker (Settings → Resources → Memory) for Foundry and SWE-Agent.
- **Logs**: Detailed run output is written to `.solai/logs/run.log`; inspect this for troubleshooting.

## Docker RAM Requirements

**Docker RAM** – Foundry + SWE-Agent require ~6 GB.  
Docker Desktop → Settings → Resources → Memory ≥ 6 GB.

## Implementation Details

For detailed summaries of the implementation phases, please refer to the documents in the specs directory:

- [Phase 1 Summary (v0.4.0)](specs/phase1_summary.md)
- [Phase 2 Summary (v0.4.2)](specs/phase2_summary.md)

### Running the Pipeline

Once configured, start the pipeline:

```bash
# Run once and exit
solai run --once --max-concurrency 1

# Run continuously (default)
solai run

# Override the swe-rex binary location (if needed)
export SWE_REX_BIN=/path/to/my/swe-rex
solai run
```

The agent (via `swerex-remote`) will then:
1.  Clone your repo into a temporary worktree.
2.  Checkout a new branch (e.g., `fix-demo`).

### Troubleshooting & FAQ

*   **Docker Issues:** Ensure Docker Desktop (or Docker Engine on Linux) is running and has sufficient resources allocated (>= 6GB RAM recommended).
*   **`solai doctor` fails:** Follow the error messages to install missing tools or fix configuration.
*   **Authentication:** `swerex-remote` needs API keys for the chosen model (e.g., `OPENAI_API_KEY`). See SWE-ReX documentation for details.
*   **Q: I'm on an older system where the binary is still called `swe-rex`.**
    **A:** Run `export SWE_REX_BIN=swe-rex` in your terminal before running `solai` commands.

## Contributing

Please see the [CONTRIBUTING.md](CONTRIBUTING.md) file for more information on how to contribute to this project. 