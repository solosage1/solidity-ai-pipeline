#!/usr/bin/env bash
#
# Check if the committed requirements.txt lock file is consistent
# with the declared constraints in constraints.txt.
# Ensures reproducibility and catches uncommitted lock file updates.
#

set -euo pipefail # Fail on error, unset var, pipe failure

# --- Configuration ---
CONSTRAINT_FILE="constraints.txt"
LOCK_FILE="requirements.txt" # The committed lock file
TEMP_LOCK_FILE=$(mktemp)     # Temporary file for fresh compilation

# Using mktemp for temporary normalized files as well
COMMITTED_LOCK_CLEAN=$(mktemp)
TEMP_LOCK_CLEAN=$(mktemp)

# --- Input Validation ---
if [[ ! -f "$CONSTRAINT_FILE" ]]; then
    echo "❌ Error: Constraint file not found at \"$CONSTRAINT_FILE\"" >&2
    exit 1
fi
if [[ ! -f "$LOCK_FILE" ]]; then
    echo "❌ Error: Committed lock file not found at \"$LOCK_FILE\"" >&2
    echo "   Maybe it hasn't been generated and committed yet? Try running locally:" >&2
    echo "   pip-compile --output-file=\"${LOCK_FILE}\" --generate-hashes --no-strip-extras \"${CONSTRAINT_FILE}\" && git add \"${LOCK_FILE}\"" >&2
    exit 1
fi

# --- Cleanup ---
# Ensure temporary files are cleaned up on exit (including errors)
cleanup() {
  rm -f "$TEMP_LOCK_FILE" "$COMMITTED_LOCK_CLEAN" "$TEMP_LOCK_CLEAN"
}
trap cleanup EXIT

# --- Check Step: Generate fresh lock file --- 
echo "Generating temporary lock file from \"${CONSTRAINT_FILE}\" for comparison..."
# Assumes pip-compile (from pip-tools) is available in the PATH
# Ensure pip-tools is installed in the CI environment before running this script
# Attempting with hashes again, remove --generate-hashes if it causes errors
pip-compile \
  --quiet \
  --output-file "$TEMP_LOCK_FILE" \
  --generate-hashes \
  --no-strip-extras \
  "$CONSTRAINT_FILE"

# --- Normalize Files ---
echo "Normalizing committed lock file (\"${LOCK_FILE}\")..."
# Normalize by removing comments, blank lines, and then sorting uniquely.
sed '/^\s*#/d;/^\s*$/d' "$LOCK_FILE" | LC_ALL=C sort -u > "$COMMITTED_LOCK_CLEAN"

echo "Normalizing temporary lock file..."
sed '/^\s*#/d;/^\s*$/d' "$TEMP_LOCK_FILE" | LC_ALL=C sort -u > "$TEMP_LOCK_CLEAN"

# --- Compare Files ---
echo "Comparing normalized lock files (committed vs generated)..."
if diff --brief "$COMMITTED_LOCK_CLEAN" "$TEMP_LOCK_CLEAN"; then
  echo "✅ Success: Committed \"${LOCK_FILE}\" is consistent with \"${CONSTRAINT_FILE}\"."
  exit 0
else
  echo "❌ Error: Committed \"${LOCK_FILE}\" is out of sync with \"${CONSTRAINT_FILE}\"." >&2
  echo "   Please run the following command locally, commit the updated \"${LOCK_FILE}\", and push:" >&2
  # Make sure the suggested command exactly matches the one used for generation
  echo "   pip-compile --output-file=\"${LOCK_FILE}\" --generate-hashes --no-strip-extras \"${CONSTRAINT_FILE}\"" >&2
  echo "   (Consider adding '--upgrade' if you want to update to the latest compatible versions)" >&2

  # Show a unified diff for easier debugging in CI logs
  echo "--- Differences detected (committed vs generated): ---" >&2
  # diff returns non-zero if files differ, || true prevents set -e from exiting here
  diff -u "$COMMITTED_LOCK_CLEAN" "$TEMP_LOCK_CLEAN" >&2 || true

  exit 1
fi 