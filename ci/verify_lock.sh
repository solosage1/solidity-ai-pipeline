#!/bin/bash
set -euo pipefail

# Configuration
PC_FLAGS="--verbose --no-strip-extras --generate-hashes"
# Regex for matching package lines (handles extras and VCS URLs)
RE_LINE='^[A-Za-z0-9_.+-]+(\[[A-Za-z0-9_,-]+\])?==|^[A-Za-z0-9_.+-]+ @ '
# Set to 1 to allow VCS-only changes without failing
ALLOW_VCS_CHANGES=${ALLOW_VCS_CHANGES:-0}

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

# Function to show file with truncation marker
show_truncated() {
  local file=$1
  head -n 100 "$file"
  if [ "$(wc -l < "$file")" -gt 100 ]; then
    echo "...(truncated, showing first 100 of $(wc -l < "$file") lines)"
  fi
}

echo "Generating new requirements file..."
# Attempt to compile constraints.txt
pip-compile $PC_FLAGS -o "$tmp_new" constraints.txt || {
  echo "::error::pip-compile failed to generate lock file from constraints.txt"
  exit 1
}

# Show requirements files in folded groups
echo "::group::Current requirements.txt"
show_truncated requirements.txt
echo "::endgroup::"

echo "::group::Newly generated requirements"
show_truncated "$tmp_new"
echo "::endgroup::"

# Normalize and sort current and new requirements
sed 's/ *#.*//' requirements.txt | grep -E "$RE_LINE" | sort > "$tmp_norm_cur"
sed 's/ *#.*//' "$tmp_new" | grep -E "$RE_LINE" | sort > "$tmp_norm_new"

# Compare the normalized files
echo "Comparing committed lock file (requirements.txt) with freshly compiled one…"
if ! diff -u "$tmp_norm_cur" "$tmp_norm_new"; then
  # Check if the diff is only in VCS URLs
  if grep -q '@ git+' "$tmp_new" && ! diff -u <(grep -v '@ git+' "$tmp_norm_cur") <(grep -v '@ git+' "$tmp_norm_new"); then
    echo "::warning::The differences appear to be only in VCS URLs."
    echo "Note: Consider:"
    echo "1. Pinning to specific commit hashes instead of tags"
    echo "2. Using --no-annotate flag to skip hash generation for VCS URLs"
    
    if [ "$ALLOW_VCS_CHANGES" = "1" ]; then
      echo "VCS-only changes detected, but ALLOW_VCS_CHANGES=1, continuing..."
      exit 0
    fi
  fi
  
  echo "::error::requirements.txt is out of sync with constraints.txt (see diff above)"
  echo "Please run the following command locally and commit the changes:"
  echo "  pip-compile $PC_FLAGS -o requirements.txt constraints.txt"
  exit 1
fi

# If diff passes, confirm
echo "✓ requirements.txt is up to date." 