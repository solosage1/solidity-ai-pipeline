# solai

Plug-and-play AI improvement pipeline for Solidity projects.

## Installation

```bash
# Installs solai and swe-rex
pipx install solai

# SWE-Agent requires manual installation from source:
git clone https://github.com/princeton-nlp/SWE-agent.git
cd SWE-agent
pip install -e .
# Ensure the sweagent command is now in your PATH
```

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
# In your Solidity project directory (after installing solai and SWE-Agent):
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

## Docker RAM Requirements

**Docker RAM** – Foundry + SWE-Agent require ~6 GB.  
Docker Desktop → Settings → Resources → Memory ≥ 6 GB.

## Implementation Details

For a detailed summary of the Phase 1 implementation (v0.4.0), please refer to the document in the specs directory:

- [Phase 1 Summary](specs/phase1_summary.md) 