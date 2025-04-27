#!/usr/bin/env bash
set -euo pipefail
# Ensure deterministic toolchain for all CI jobs
python -m pip install --quiet "pip==24.3.1"
python -m pip install --quiet "pip-tools>=7.4,<7.5" build 