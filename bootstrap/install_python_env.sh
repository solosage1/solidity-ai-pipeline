#!/usr/bin/env bash
set -euo pipefail
echo "▶ Creating Python 3.12 virtualenv (.venv)"
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
# install core CLI deps
pip install typer rich pyyaml
# install solai itself with the [ai] extra (this pulls SWE-Agent & SWE-ReX from GitHub)
pip install -e ".[ai]"
python -m pip install --quiet --no-cache-dir \
    git+https://github.com/SWE-agent/SWE-agent.git@v1.0.1 \
    git+https://github.com/SWE-agent/SWE-ReX.git@main

deactivate 