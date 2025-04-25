FROM ghcr.io/foundry-rs/foundry:latest
USER root
RUN apt-get update && apt-get install -y python3-pip \
    && pip install --no-cache-dir slither-analyzer swe-rex
ENV PATH="$PATH:/root/.local/bin" 