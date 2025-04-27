# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.5] - 2023-08-11

### Added
- Complete Phase 3 workflow implementation
- SWE-Agent integration with gpt-4o-mini
- Automated test validation in CI pipeline
- Slither security analysis integration
- NEW: `tests/test_setup_stub_pkgs.py` ensures stub script (`scripts/setup_stub_pkgs.py`) is idempotent and handles missing `sweagent` correctly.
- CI: Added `lint-and-test` job to `.github/workflows/solai.yml` to run `actionlint` and `pytest`.
- CI: Added pip caching to `lint-and-test` job for faster dependency installation.
- CI: Slither analysis now runs inside a Docker container after a successful patch application in the `phase3_hello_world` job.
- CI: Added comment linking to issue #125 in `scripts/setup_stub_pkgs.py` for future stub removal.

### Changed
- Optimized GitHub Actions workflow structure
- Moved long bash script to dedicated file
- Fixed actionlint validation
- CI: Pinned `pytest<9` in the `lint-and-test` job.
- STYLE: Ran `ruff format` across the repository for consistent code style.

### Fixed
- Cross-platform stat command issues
- OpenAI package version pinned exactly to 1.76.1
- Fixed heredoc syntax issues in workflow
- CI: Corrected various linting errors (unused imports, f-strings, boolean comparisons) identified by Ruff.
- CI: Hardened workflow security using `sudo --preserve-env` and aligned Ruff action Python version. 