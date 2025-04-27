# syntax=docker/dockerfile:1.7
# Pinned base image for reproducibility
# FROM ghcr.io/foundry-rs/foundry:1.0.0   # ← replace with your desired tag/digest
# Using latest for now as 1.0.0 tag was not found
FROM ghcr.io/foundry-rs/foundry:latest
USER root

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-pip \
 && python3 -m pip install --upgrade pip \
 # Install Slither and SWE-ReX directly into system site-packages
 && python3 -m pip install --no-cache-dir slither-analyzer swe-rex \
 # Clean up apt cache
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- DEBUG ONLY — uncomment below to check install location during build --- 
# RUN echo "PATH after pip install: $PATH"                 \
#  && echo "--- Contents of /root/.local/bin ---"          \
#  && ls -lR /root/.local/bin || true                       \
#  && echo "--- Contents of /usr/local/bin ---"           \
#  && ls -lR /usr/local/bin || true
# ------------------------------------------------------------------------

# Standard PATH should already include /usr/local/bin where pip installs scripts

# Helpful for humans: show versions at build-time
RUN forge --version && slither --version && swerex-remote --version 