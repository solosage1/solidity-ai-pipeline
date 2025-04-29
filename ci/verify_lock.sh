#!/bin/bash
set -euo pipefail

# Configuration
PC_FLAGS="--verbose --no-strip-extras --generate-hashes"

echo "Current pip version:"
pip --version
echo "Current pip-tools version:"
pip-compile --version

tmp_new="$(mktemp)"
tmp_norm_new="$(mktemp)"
tmp_norm_cur="$(mktemp)"

# Function to clean up temp files
cleanup() {
  rm -f "$tmp_new" "$tmp_norm_new" "$tmp_norm_cur"
}
# Ensure cleanup happens on exit, error, or interrupt
trap cleanup EXIT ERR INT

echo "Generating new requirements file..."
# Attempt to compile constraints.txt
pip-compile $PC_FLAGS -o "$tmp_new" constraints.txt || {
  echo "::error::pip-compile failed to generate lock file from constraints.txt"
  exit 1
}

# Show requirements files in folded groups
echo "::group::Current requirements.txt"
head -n 100 requirements.txt
echo "::endgroup::"

echo "::group::Newly generated requirements"
head -n 100 "$tmp_new"
echo "::endgroup::"

# Normalize and sort current and new requirements
# Improved regex to handle extras and VCS URLs
sed 's/ *#.*//' requirements.txt | grep -E '^[A-Za-z0-9_.+-]+(\[[A-Za-z0-9_,-]+\])?==|^[A-Za-z0-9_.+-]+ @ ' | sort > "$tmp_norm_cur"
sed 's/ *#.*//' "$tmp_new" | grep -E '^[A-Za-z0-9_.+-]+(\[[A-Za-z0-9_,-]+\])?==|^[A-Za-z0-9_.+-]+ @ ' | sort > "$tmp_norm_new"

# Compare the normalized files
echo "Comparing committed lock file (requirements.txt) with freshly compiled one…"
if ! diff -u "$tmp_norm_cur" "$tmp_norm_new"; then
  echo "::error::requirements.txt is out of sync with constraints.txt"
  echo "Please run the following command locally and commit the changes:"
  echo "  pip-compile $PC_FLAGS -o requirements.txt constraints.txt"
  
  # Check if the diff is only in VCS URLs
  if grep -q '@ git+' "$tmp_new" && ! diff -u <(grep -v '@ git+' "$tmp_norm_cur") <(grep -v '@ git+' "$tmp_norm_new"); then
    echo "Note: The differences appear to be only in VCS URLs. Consider:"
    echo "1. Pinning to specific commit hashes instead of tags"
    echo "2. Using --no-annotate flag to skip hash generation for VCS URLs"
  fi
  
  exit 1
fi

# If diff passes, confirm
echo "✓ requirements.txt is up to date." 