FROM ghcr.io/foundry-rs/foundry:latest
RUN apt-get update && apt-get install -y slither-analyzer \
    && pip install --no-cache-dir swe-rex
ENV PATH="$PATH:/root/.local/bin" 