# Pinned base image for reproducibility
# FROM ghcr.io/foundry-rs/foundry:1.0.0   # ← replace with your desired tag/digest
# Using latest for now as 1.0.0 tag was not found
FROM ghcr.io/foundry-rs/foundry:latest
USER root

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-pip python3-venv \
 && python3 -m pip install --upgrade pip \
 # Install Slither in the global site-packages
 && python3 -m pip install --no-cache-dir slither-analyzer \
 # Install pipx & SWE-ReX inside its own venv
 && python3 -m pip install --no-cache-dir pipx \
 && pipx install swe-rex \
 # Clean up apt cache
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Expose pipx shims & Slither
ENV PATH="/root/.local/bin:$PATH"

# Helpful for humans: show versions at build-time
RUN forge --version && slither --version && swerex-remote --version 