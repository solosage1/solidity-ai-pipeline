# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.5] - YYYY-MM-DD
### Added
- NEW: `tests/test_setup_stub_pkgs.py` ensures stub script (`scripts/setup_stub_pkgs.py`) is idempotent and handles missing `sweagent` correctly.
- CI: Added `lint-and-test` job to `.github/workflows/solai.yml` to run `actionlint` and `pytest`.
- CI: Added pip caching to `lint-and-test` job for faster dependency installation.
- CI: Slither analysis now runs inside the `foundry_sol` Docker container after a successful patch application in the `phase3_hello_world` job.
- CI: Added comment linking to issue #125 in `scripts/setup_stub_pkgs.py` for future stub removal.

### Changed
- CI: Pinned `pytest<9` in the `lint-and-test` job.
- STYLE: Ran `ruff format` across the repository for consistent code style. 