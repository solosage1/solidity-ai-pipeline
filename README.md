# solai

Plug-and-play AI improvement pipeline for Solidity projects.

## Installation

```bash
# 1) install core CLI
pipx install solai --include-deps

# 2) inject the latest AI backends into that same solai venv
make bootstrap-solai
```

The `bootstrap-solai` make target will:
1. Ensure pipx is on your PATH
2. Install/upgrade solai if needed
3. Inject SWE-Agent & SWE-ReX into the solai venv
4. Verify the environment with `solai doctor`

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
# In your Solidity project directory (after installing solai & AI deps):
solai init
make bootstrap-solai
make solai-run
```

## Requirements

- Python 3.12+
- Docker
- Foundry
- Slither
- SWE-ReX (automatically installed with solai)
- SWE-Agent (requires manual installation from source, see above)

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