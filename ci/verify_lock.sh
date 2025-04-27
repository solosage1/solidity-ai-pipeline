#!/bin/bash
set -euo pipefail

tmp_new="$(mktemp)"
tmp_norm_new="$(mktemp)"
tmp_norm_cur="$(mktemp)"

# Function to clean up temp files
cleanup() {
  rm -f "$tmp_new" "$tmp_norm_new" "$tmp_norm_cur"
}
# Ensure cleanup happens on exit, error, or interrupt
trap cleanup EXIT ERR INT

# Attempt to compile constraints.txt
pip-compile --quiet --no-strip-extras --generate-hashes -o "$tmp_new" constraints.txt || {
  echo "::error::pip-compile failed to generate lock file from constraints.txt"
  exit 1
}

# Normalize and sort current and new requirements
grep -E '^[A-Za-z0-9_.-]+==' requirements.txt | sort > "$tmp_norm_cur"
grep -E '^[A-Za-z0-9_.-]+==' "$tmp_new"       | sort > "$tmp_norm_new"

# Compare the normalized files
echo "Comparing committed lock file (requirements.txt) with freshly compiled one…"
if ! diff -u "$tmp_norm_cur" "$tmp_norm_new"; then
  echo "::error::requirements.txt is out of sync with constraints.txt"
  echo "Please run the following command locally and commit the changes:"
  echo "  pip-compile --no-strip-extras --generate-hashes -o requirements.txt constraints.txt"
  exit 1
fi

# If diff passes, confirm
echo "✓ requirements.txt is up to date." 