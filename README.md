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

# Build and install
python -m pip install build
python -m build
pip install dist/solai-*.whl[ai]

# Verify installation
make bootstrap-solai
```

The `bootstrap-solai` make target will:
1. Verify the environment with `solai doctor`
2. Ensure all dependencies are properly installed
3. Set up any necessary local development tools

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
    source ~/.bashrc  # or restart your terminal
    foundryup
    ```
- Slither
- SWE-ReX (installed automatically with solai[ai])
- SWE-Agent (installed automatically with solai[ai])

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