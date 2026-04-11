FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Core build tools
RUN apt-get update && apt-get install -y \
    gcc \
    golang-go \
    python3 \
    ruby \
    curl \
    nasm \
    binutils \
    time \
    wrk \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /bench
