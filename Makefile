# Top-level Makefile
-include Makefile.inc

# -----------------------------
# VENV & DEP MANAGEMENT
# -----------------------------
VENV_DIR ?= venv
PYTHON    = $(VENV_DIR)/bin/python
PIP       = $(VENV_DIR)/bin/pip

# The "true" constraint file
CONSTRAINTS_FILE = hashed_constraints.txt

# Configuration
MAX_LOC ?= 2000
COVERAGE_DIR ?= coverage

# Check if forge-coverage is available
HAS_FORGE_COVERAGE := $(shell command -v forge-coverage 2>/dev/null)

.PHONY: venv clean-venv install-sweagent lockfile sync-requirements dev all \
        test-solidity lint-solidity test-python lint-python ci \
        coverage format clean

venv:
	@echo "🐍 Creating virtualenv…"
	python -m venv $(VENV_DIR)
	$(PIP) install --upgrade pip
	$(PIP) install --force-reinstall "pip<25.1"
	$(PIP) install "pip-tools==7.4.1"
	@echo "✅ venv ready"

install-sweagent: venv
	@echo "📦 Installing SWE-Agent…"
	$(PIP) install --upgrade \
	  git+https://github.com/princeton-nlp/swe-agent.git@v1.0.1
	@echo "✅ SWE-Agent installed"

lockfile: venv
	@echo "🔄 Regenerating requirements.txt from $(CONSTRAINTS_FILE)…"
	$(PYTHON) -m piptools compile \
	  --rebuild \
	  --no-strip-extras \
	  --generate-hashes \
	  -o requirements.txt \
	  $(CONSTRAINTS_FILE)
	@echo "✅ Lockfile updated"

sync-requirements: venv lockfile install-sweagent
	@echo "📥 Syncing deps into venv…"
	$(PYTHON) -m piptools sync requirements.txt
	@echo "✅ Requirements in sync"

clean-venv:
	@echo "🧹 Removing venv…"
	rm -rf $(VENV_DIR)
	@echo "✅ venv removed"

# -----------------------------
# TEST TARGETS
# -----------------------------
## Solidity unit tests via Foundry
test-solidity: venv
	@echo "🔍 Running Solidity tests…"
	forge test -q
	@echo "✅ Solidity tests passed"

## Solidity coverage report (requires forge-coverage)
coverage-solidity: venv
	@echo "📊 Generating Solidity coverage report…"
	@if [ -n "$(HAS_FORGE_COVERAGE)" ]; then \
		mkdir -p $(COVERAGE_DIR); \
		forge coverage --report lcov; \
		echo "✅ Coverage report generated in $(COVERAGE_DIR)"; \
	else \
		echo "⚠️ forge-coverage not found. Install with: foundryup --version nightly"; \
		exit 1; \
	fi

## Python tests with coverage
test-python: dev
	@echo "🐍 Running Python tests with coverage…"
	$(PYTHON) -m pytest --cov=. --cov-report=term-missing tests/
	@echo "✅ Python tests passed"

## Generate coverage reports
coverage: coverage-solidity test-python
	@echo "📊 Coverage reports complete"

# -----------------------------
# LINT & FORMAT TARGETS
# -----------------------------
## Solidity static analysis via Slither
lint-solidity: venv
	@echo "🔍 Running Slither analysis…"
	docker run --rm -v "$$(pwd)":/src ghcr.io/crytic/slither:latest-slim \
	  slither /src --exclude-dependencies --disable-color
	@echo "✅ Slither analysis complete"

## Python linting with Ruff
lint-python: dev
	@echo "✨ Running Python linter…"
	$(PYTHON) -m ruff check .
	@echo "✅ Python linting passed"

## Format Python code
format-python: dev
	@echo "🎨 Formatting Python code…"
	$(PYTHON) -m ruff format .
	@echo "✅ Python formatting complete"

## Format Solidity code
format-solidity: venv
	@echo "🎨 Formatting Solidity code…"
	forge fmt
	@echo "✅ Solidity formatting complete"

## Format all code
format: format-python format-solidity

# -----------------------------
# CLEAN TARGETS
# -----------------------------
## Clean all generated files
clean: clean-venv
	@echo "🧹 Cleaning generated files…"
	rm -rf $(COVERAGE_DIR)
	rm -rf .pytest_cache
	rm -rf .ruff_cache
	rm -rf .coverage
	@echo "✅ Clean complete"

# -----------------------------
# META TARGETS
# -----------------------------
## Bring up a full dev environment
dev: sync-requirements

## Alias for all development setup
all: dev

## Local CI runner: setup + tests + lint
ci: dev test-solidity lint-solidity test-python lint-python
	@echo "🏁 All checks passed!" 